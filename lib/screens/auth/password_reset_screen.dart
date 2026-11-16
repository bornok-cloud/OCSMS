import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../../widgets/shared_widgets.dart';
import 'login_screen.dart';

class PasswordResetFlowScreen extends StatefulWidget {
  final AppUser user;
  const PasswordResetFlowScreen({super.key, required this.user});

  @override
  State<PasswordResetFlowScreen> createState() => _PasswordResetFlowScreenState();
}

class _PasswordResetFlowScreenState extends State<PasswordResetFlowScreen> {
  bool _otpVerified = false;
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  int _secondsLeft = 60;
  Timer? _timer;
  String? _error;
  bool _verifying = false;
  bool _resending = false;

  // New password controllers & focus nodes
  final _formKey = GlobalKey<FormState>();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _passFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _newPassCtrl.addListener(_onPasswordChanged);
    _confirmPassCtrl.addListener(_onPasswordChanged);
    _passFocusNode.addListener(_onPasswordChanged);
    _confirmFocusNode.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    setState(() {});
  }

  void _startTimer() {
    _secondsLeft = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    _newPassCtrl.removeListener(_onPasswordChanged);
    _confirmPassCtrl.removeListener(_onPasswordChanged);
    _passFocusNode.removeListener(_onPasswordChanged);
    _confirmFocusNode.removeListener(_onPasswordChanged);
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _passFocusNode.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _error = 'Enter all 6 digits.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });

    final error = await AppData.instance.verifyOtp(widget.user.id, code);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      if (error == null) {
        _otpVerified = true;
      } else {
        _error = error;
      }
    });
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await AppData.instance.resendOtp(widget.user.id);
      if (!mounted) return;
      setState(() {
        _error = null;
        for (final c in _controllers) {
          c.clear();
        }
      });
      _nodes.first.requestFocus();
      _startTimer();
      showAppSnack(context, 'A new code was sent to ${widget.user.email}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not resend code: $e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String? _validatePassword(String? v) {
    final pass = v ?? '';
    if (pass.isEmpty) return 'Password is required';
    if (pass.length < 8) return 'At least 8 characters required';
    if (!RegExp(r'[a-z]').hasMatch(pass)) return 'Must contain a lowercase letter';
    if (!RegExp(r'[A-Z]').hasMatch(pass)) return 'Must contain an uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(pass)) return 'Must contain a number';
    if (!RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?/~]').hasMatch(pass)) {
      return 'Must contain a special character';
    }
    return null;
  }

  String? _validateConfirmPassword(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm password';
    if (v != _newPassCtrl.text) return 'Passwords do not match';
    return null;
  }

  Widget _buildCheckItem(String label, bool satisfied) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            satisfied ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 15,
            color: satisfied ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: satisfied ? AppColors.darkBrown : AppColors.textMuted,
                fontWeight: satisfied ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNewPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await AppData.instance.updatePassword(widget.user.id, _newPassCtrl.text.trim());
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Password Updated Successfully'),
          content: const Text('Your password has been changed. You can now login with your new password.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('Go to Login'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to update password: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final passText = _newPassCtrl.text;
    final confirmText = _confirmPassCtrl.text;

    final hasMinLength = passText.length >= 8;
    final hasLowercase = RegExp(r'[a-z]').hasMatch(passText);
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(passText);
    final hasNumber = RegExp(r'[0-9]').hasMatch(passText);
    final hasSpecialChar = RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?/~]').hasMatch(passText);
    final passwordsMatch = confirmText.isNotEmpty && confirmText == passText;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.darkBrown, AppColors.brown],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardWhite,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppShadows.lifted,
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    child: !_otpVerified
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Verify Email',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.headlineMedium),
                              const SizedBox(height: 8),
                              Text(
                                'We sent a 6-digit approval code to\n${widget.user.email}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 24),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(6, (i) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: SizedBox(
                                        width: 44,
                                        child: TextField(
                                          controller: _controllers[i],
                                          focusNode: _nodes[i],
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          maxLength: 1,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly
                                          ],
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.darkBrown),
                                          decoration: InputDecoration(
                                            counterText: '',
                                            contentPadding:
                                                const EdgeInsets.symmetric(vertical: 14),
                                            filled: true,
                                            fillColor: AppColors.beige.withValues(alpha: 0.5),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: AppColors.lightBrown
                                                      .withValues(alpha: 0.3)),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                  color: AppColors.brown, width: 2),
                                            ),
                                          ),
                                          onChanged: (v) {
                                            if (v.isNotEmpty && i < 5) {
                                              _nodes[i + 1].requestFocus();
                                            }
                                            if (v.isEmpty && i > 0) {
                                              _nodes[i - 1].requestFocus();
                                            }
                                            if (v.isNotEmpty && i == 5) {
                                              _verifyOtp();
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                                  ),
                                  child: Text(_error!,
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center),
                                ),
                              ],
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _verifying ? null : _verifyOtp,
                                  child: _verifying
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : const Text('Verify & Approve Email'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: _secondsLeft == 0 && !_resending
                                        ? _resend
                                        : null,
                                    child: Text(_secondsLeft > 0
                                        ? 'Resend code in $_secondsLeft s'
                                        : 'Resend Code'),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: AppColors.success),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Email approved successfully! You may now set your new password.',
                                          style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text('Change Password',
                                    style: Theme.of(context).textTheme.headlineSmall),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _newPassCtrl,
                                  focusNode: _passFocusNode,
                                  obscureText: _obscure1,
                                  decoration: InputDecoration(
                                    labelText: 'New Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure1 ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                                    ),
                                  ),
                                  validator: _validatePassword,
                                ),
                                if (_passFocusNode.hasFocus && passText.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.beige.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildCheckItem('At least 8 characters long', hasMinLength),
                                        _buildCheckItem('At least 1 lowercase letter (a-z)', hasLowercase),
                                        _buildCheckItem('At least 1 uppercase letter (A-Z)', hasUppercase),
                                        _buildCheckItem('At least 1 number (0-9)', hasNumber),
                                        _buildCheckItem('At least 1 special character (!@#\$%^&*...)', hasSpecialChar),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirmPassCtrl,
                                  focusNode: _confirmFocusNode,
                                  obscureText: _obscure2,
                                  decoration: InputDecoration(
                                    labelText: 'Confirm New Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                                    ),
                                  ),
                                  validator: _validateConfirmPassword,
                                ),
                                if (_confirmFocusNode.hasFocus && confirmText.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        passwordsMatch ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                        size: 15,
                                        color: passwordsMatch ? AppColors.success : AppColors.danger,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: passwordsMatch ? AppColors.success : AppColors.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                                ],
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brown),
                                    onPressed: _saving ? null : _saveNewPassword,
                                    child: _saving
                                        ? const CircularProgressIndicator(color: Colors.white)
                                        : const Text('Update Password'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
