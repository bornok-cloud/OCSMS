import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared layout for the Login / Register screens (black & white theme).
///
///  * Wide screens (>= 900px): split view — black brand panel on the left,
///    white form panel on the right.
///  * Narrow screens: compact black header with the logo, and the form sits on
///    a white sheet with rounded top corners.
///
/// Only presentation lives here; each screen keeps its own form logic.
class AuthLayout extends StatelessWidget {
  final Widget child;
  final double maxFormWidth;
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.child,
    this.maxFormWidth = 420,
    this.onBack,
  });

  static const double _wideBreakpoint = 900;

  /// Scopes a calmer, monochrome input style to the auth screens only, so the
  /// rest of the app keeps its global input theme.
  ThemeData _authTheme(ThemeData base) {
    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: AppColors.cardWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(AppColors.beigeDark),
        enabledBorder: border(AppColors.beigeDark),
        focusedBorder: border(AppColors.darkBrown, 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _authTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppColors.darkBrown,
        body: LayoutBuilder(
          builder: (context, c) =>
              c.maxWidth >= _wideBreakpoint ? _wide() : _narrow(),
        ),
      ),
    );
  }

  Widget _wide() {
    return Row(
      children: [
        const Expanded(flex: 5, child: _BrandPanel()),
        Expanded(
          flex: 6,
          child: Container(
            color: AppColors.cardWhite,
            child: SafeArea(
              child: Column(
                children: [
                  if (onBack != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: TextButton.icon(
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxFormWidth),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrow() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: onBack == null
                          ? null
                          : IconButton(
                              tooltip: 'Back',
                              onPressed: onBack,
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.1),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                    ),
                    Expanded(
                      child: Center(
                        child: Image.asset('assets/images/logo_transparent.png',
                            height: 36),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'CAFE, COMFORT & CONVENIENCE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxFormWidth),
                      child: child,
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

/// Left-hand black panel shown on wide screens.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  Widget _point(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkBrown,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _RingsPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 40, 56, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/images/logo_transparent.png', height: 44),
                  const Spacer(),
                  const Text(
                    'Run the cafe\nfrom one place.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Orders, inventory, attendance and payroll, kept in sync.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _point(
                      Icons.point_of_sale_outlined, 'POS and kitchen ordering'),
                  _point(Icons.inventory_2_outlined,
                      'Live inventory and low-stock alerts'),
                  _point(Icons.fingerprint, 'Attendance and payroll tracking'),
                  const Spacer(),
                  Text(
                    'Overnight Cafe',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint concentric rings in the bottom-right corner of the brand panel.
class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    final center = Offset(size.width * 0.95, size.height * 1.02);
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(center, i * 90.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Page heading used by Login / Register: title + one-line subtitle.
class AuthHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const AuthHeading({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.darkBrown,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 14.5, height: 1.4),
        ),
      ],
    );
  }
}

/// Full-width black primary button with a built-in loading state.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: AppColors.darkBrown,
          disabledForegroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.2),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
