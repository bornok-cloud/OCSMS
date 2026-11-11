import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/auth_layout.dart';
import '../../models/models.dart';
import '../admin/admin_shell.dart';
import '../employee/employee_shell.dart';
import '../customer/customer_shell.dart';
import '../landing/landing_page.dart';
import 'register_screen.dart';
import 'password_reset_screen.dart';
import '../guest/guest_ordering_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  Future<void> _login() async {
    if (_submitting) return;
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    final user = await AppData.instance.login(email, password);
    if (!mounted) return;
    if (user == null) {
      final specificError =
          await AppData.instance.checkLoginStatus(email, password);
      setState(() {
        _error = specificError ?? 'Invalid email or password';
        _submitting = false;
      });
      return;
    }
    Widget target;
    switch (user.role) {
      case UserRole.admin:
        target = const AdminShell();
        break;
      case UserRole.employee:
        target = const EmployeeShell();
        break;
      case UserRole.customer:
        target = const CustomerShell();
        break;
    }
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => target), (route) => false);
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() =>
          _error = 'Please enter your email in the email field above first.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error =
          'Enter a valid email address before resetting your password.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final user = await AppData.instance.findUserByEmail(email);
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _error = 'No account found with email: $email';
          _submitting = false;
        });
        return;
      }

      await AppData.instance.sendPasswordResetOtp(email);
      if (!mounted) return;
      setState(() => _submitting = false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PasswordResetFlowScreen(user: user),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to send reset email: $e';
        _submitting = false;
      });
    }
  }

  Widget _mockAccountChip(
      String label, IconData icon, String email, String pass) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.darkBrown),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      backgroundColor: AppColors.cardWhite,
      side: const BorderSide(color: AppColors.beigeDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      onPressed: () {
        setState(() {
          _emailCtrl.text = email;
          _passCtrl.text = pass;
          _error = null;
        });
      },
    );
  }

  Widget _errorBanner() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: _error == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      maxFormWidth: 420,
      onBack: () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LandingPage()));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AuthHeading(
            title: 'Welcome Back',
            subtitle: 'Login to Overnight Cafe',
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _login(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          _errorBanner(),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: TextButton(
                onPressed: _submitting ? null : _handleForgotPassword,
                child: const Text('Forgot Password?'),
              ),
            ),
          ),
          AuthPrimaryButton(
            label: 'Login',
            loading: _submitting,
            onPressed: _login,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkBrown,
              side: const BorderSide(color: AppColors.darkBrown, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuestOrderingShell()),
              );
            },
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Order as Walk in customer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text("Don't have an account?",
                  style: TextStyle(color: AppColors.textMuted)),
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('Register'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.beigeDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'DEMO ACCOUNTS · TAP TO AUTOFILL',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _mockAccountChip(
                        'Admin',
                        Icons.admin_panel_settings_outlined,
                        'binimikha108@gmail.com',
                        'Altair@1'),
                    _mockAccountChip('Employee', Icons.badge_outlined,
                        'maraltairc@gmail.com', 'Altair@1'),
                    _mockAccountChip('Customer', Icons.person_outline,
                        'micohobdosantos@gmail.com', 'Altair@1'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
