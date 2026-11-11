import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../models/models.dart';
import '../admin/admin_shell.dart';
import '../employee/employee_shell.dart';
import '../customer/customer_shell.dart';
import '../guest/guest_ordering_shell.dart';
import '../landing/landing_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final minSplashTime = Future.delayed(const Duration(milliseconds: 2200));

    // Restore persistent login session across restarts / background kills
    await AppData.instance.restoreSession();
    await minSplashTime;

    if (!mounted) return;

    // Check if opened via Walk-In QR Code URL on web
    if (kIsWeb) {
      final uriString = Uri.base.toString().toLowerCase();
      if (uriString.contains('walk-in') || uriString.contains('guest')) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GuestOrderingShell()),
        );
        return;
      }
    }

    final user = AppData.instance.currentUser;
    Widget target = const LandingPage();
    if (user != null) {
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
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBrown,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1.5),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo_white_cropped.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_cafe_rounded,
                          size: 80,
                          color: AppColors.beige,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'OVERNIGHT CAFE',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sip, Savour & Stay Overnight',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                        color: AppColors.beige.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
