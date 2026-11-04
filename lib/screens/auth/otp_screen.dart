import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import '../../widgets/shared_widgets.dart';

class OtpScreen extends StatefulWidget {
  final AppUser user;
  final bool fromAdmin;
  const OtpScreen({super.key, required this.user, this.fromAdmin = false});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  int _secondsLeft = 60;
  Timer? _timer;
  String? _error;
  bool _verified = false;
  bool _resending = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
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
    super.dispose();
  }

  Future<void> _discardAndLeave() async {
    try {
      await AppData.instance.discardPendingRegistration(widget.user.id);
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, 'Could not cancel the registration. Please try again.', success: false);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmLeave() async {
    if (_verified) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change email?'),
        content: const Text(
          'Your email has not been verified yet. Leaving this page will discard this unverified registration so you can enter a new email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue verification'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change email'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _discardAndLeave();
    }
  }

  Future<void> _verify() async {
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
      _error = error;
      if (error == null) {
        _verified = true;
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

  Widget _otpField(BuildContext context, int i) {
    final hasValue = _controllers[i].text.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(right: i == 5 ? 0 : 8),
      child: SizedBox(
        width: 46,
        height: 58,
        child: TextField(
          controller: _controllers[i],
          focusNode: _nodes[i],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction: i == 5 ? TextInputAction.done : TextInputAction.next,
          autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 22,
            height: 1,
            fontWeight: FontWeight.w800,
            color: hasValue ? Colors.white : AppColors.darkBrown,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: hasValue ? AppColors.darkBrown : const Color(0xFFF2F2F2),
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: hasValue ? AppColors.darkBrown : const Color(0xFFD5D5D5),
                width: hasValue ? 1.4 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.darkBrown, width: 2),
            ),
          ),
          onChanged: (value) {
            setState(() {});
            if (value.isNotEmpty && i < 5) {
              _nodes[i + 1].requestFocus();
            }
            if (value.isEmpty && i > 0) {
              _nodes[i - 1].requestFocus();
            }
            if (value.isNotEmpty && i == 5) {
              _verify();
            }
          },
          onSubmitted: (_) {
            if (i == 5) _verify();
          },
        ),
      ),
    );
  }

  Widget _statusMessage() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_verified) return true;
        await _confirmLeave();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBrown,
        body: Stack(
          children: [
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 1),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -100,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      decoration: BoxDecoration(
                        color: AppColors.cardWhite,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 36, offset: const Offset(0, 18)),
                        ],
                      ),
                      child: _verified
                          ? _successContent(context)
                          : _verificationContent(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: widget.fromAdmin ? 'Back to User Management' : 'Back to Login',
          onPressed: _verified ? () => Navigator.of(context).pop() : _confirmLeave,
          icon: const Icon(Icons.arrow_back_rounded, size: 21),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        ),
        const Spacer(),
        Text(
          'EMAIL VERIFICATION',
          style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: AppColors.textMuted.withValues(alpha: 0.85)),
        ),
      ],
    );
  }

  Widget _verificationContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeader(context),
        const SizedBox(height: 18),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: AppColors.darkBrown, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 29),
        ),
        const SizedBox(height: 22),
        Text('Check your inbox', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 29, height: 1.1)),
        const SizedBox(height: 10),
        const Text('Enter the 6-digit code we sent to confirm your email address.', style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.45)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              const Icon(Icons.alternate_email_rounded, size: 17, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            ],
          ),
        ),
        const SizedBox(height: 26),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(children: List.generate(6, (i) => _otpField(context, i))),
        ),
        _statusMessage(),
        const SizedBox(height: 22),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _verifying ? null : _verify,
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _verifying
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('Verify email'), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, size: 18)]),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: _secondsLeft > 0
              ? Text('Resend available in $_secondsLeft s', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))
              : TextButton.icon(
                  onPressed: _resending ? null : _resend,
                  icon: _resending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Send a new code'),
                ),
        ),
        const SizedBox(height: 6),
        Center(child: Text('The code expires after 5 minutes.', style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.82), fontSize: 11.5))),
      ],
    );
  }

  Widget _successContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cardHeader(context),
        const SizedBox(height: 34),
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(color: AppColors.darkBrown, borderRadius: BorderRadius.circular(26)),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
        ),
        const SizedBox(height: 24),
        Text('You’re all set.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 29)),
        const SizedBox(height: 10),
        const Text('Your email has been verified successfully. Your account is ready to use.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.45)),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () {
              RegisterScreen.clearDraft();
              if (widget.fromAdmin) {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
              }
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(widget.fromAdmin ? 'Return to users' : 'Continue to login'), const SizedBox(width: 8), const Icon(Icons.arrow_forward_rounded, size: 18)]),
          ),
        ),
      ],
    );
  }
}
