import 'dart:async';
import 'package:flutter/material.dart';
import '../models/tutorial_step.dart';
import '../theme/app_theme.dart';

class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.onFinished,
  });

  final List<TutorialStep> steps;
  final VoidCallback onFinished;

  static Future<void> show({
    required BuildContext context,
    required List<TutorialStep> steps,
    required VoidCallback onFinished,
  }) async {
    if (steps.isEmpty) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Interactive Tour',
      barrierColor: Colors.black.withValues(alpha: 0.90),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) {
        return TutorialOverlay(steps: steps, onFinished: onFinished);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _autoPlayProgressController;
  int _currentIndex = 0;
  bool _isAutoPlay = true;
  Timer? _autoPlayTimer;

  static const Duration _stepDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _autoPlayProgressController = AnimationController(
      vsync: this,
      duration: _stepDuration,
    );

    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayProgressController.reset();
    _autoPlayProgressController.forward();

    _autoPlayTimer = Timer.periodic(_stepDuration, (_) {
      if (!mounted) return;
      if (_currentIndex < widget.steps.length - 1) {
        _nextStep(fromAutoPlay: true);
      } else {
        _finishTour();
      }
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _autoPlayProgressController.stop();
  }

  void _toggleAutoPlay() {
    setState(() {
      _isAutoPlay = !_isAutoPlay;
    });
    if (_isAutoPlay) {
      _startAutoPlay();
    } else {
      _stopAutoPlay();
    }
  }

  void _nextStep({bool fromAutoPlay = false}) {
    if (!fromAutoPlay && _isAutoPlay) {
      // Restart timer for user interaction
      _startAutoPlay();
    }

    if (_currentIndex < widget.steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishTour();
    }
  }

  void _prevStep() {
    if (_isAutoPlay) {
      _startAutoPlay();
    }
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _finishTour() {
    _stopAutoPlay();
    Navigator.of(context).pop();
    widget.onFinished();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _autoPlayProgressController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E0D), // Deep rich dark background
      body: Stack(
        children: [
          // Background ambient gradient circles
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brown.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Full-Page Layout
          SafeArea(
            child: Column(
              children: [
                // Top Navigation Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      // Brand Tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.local_cafe_rounded, size: 14, color: AppColors.accent),
                            SizedBox(width: 8),
                            Text(
                              'OVERNIGHT CAFE • SYSTEM TOUR',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Auto-Play Toggle Button
                      InkWell(
                        onTap: _toggleAutoPlay,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: _isAutoPlay
                                ? AppColors.accent.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isAutoPlay
                                  ? AppColors.accent.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isAutoPlay ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                size: 16,
                                color: _isAutoPlay ? AppColors.accent : Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isAutoPlay ? 'Auto-Playing' : 'Auto-Play Off',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isAutoPlay ? AppColors.accent : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Skip Button
                      TextButton.icon(
                        onPressed: _finishTour,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text(
                          'Skip',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

                // Top Auto-Play Progress Bar Indicator
                if (_isAutoPlay)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedBuilder(
                      animation: _autoPlayProgressController,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _autoPlayProgressController.value,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      ),
                    ),
                  ),

                // Page Content (Full Page View)
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.steps.length,
                    onPageChanged: (idx) {
                      setState(() {
                        _currentIndex = idx;
                      });
                      if (_isAutoPlay) {
                        _autoPlayProgressController.reset();
                        _autoPlayProgressController.forward();
                      }
                    },
                    itemBuilder: (context, index) {
                      final step = widget.steps[index];
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: isWide ? 680 : 440),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Step Badge & Counter
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                                    boxShadow: AppShadows.soft,
                                  ),
                                  child: Text(
                                    'MODULE ${index + 1} OF ${widget.steps.length}',
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 36),

                                // Icon Container with glowing double ring
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF1E1C1A),
                                    border: Border.all(
                                      color: AppColors.accent.withValues(alpha: 0.35),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.accent.withValues(alpha: 0.15),
                                        blurRadius: 30,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black,
                                    ),
                                    child: Icon(
                                      step.icon,
                                      size: 56,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 36),

                                // Title
                                Text(
                                  step.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isWide ? 32 : 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Description Card
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: Text(
                                    step.description,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isWide ? 16 : 14.5,
                                      color: Colors.white.withValues(alpha: 0.85),
                                      height: 1.6,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Page Indicators & Action Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        // Dots Indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            widget.steps.length,
                            (idx) => GestureDetector(
                              onTap: () {
                                _pageController.animateToPage(
                                  idx,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: idx == _currentIndex ? 32 : 10,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: idx == _currentIndex
                                      ? AppColors.accent
                                      : Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Action Buttons: Previous & Next / Finish
                        Row(
                          children: [
                            if (_currentIndex > 0) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.2),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  onPressed: _prevStep,
                                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                  label: const Text(
                                    'Previous',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 6,
                                  shadowColor: Colors.black54,
                                ),
                                onPressed: () {
                                  if (_currentIndex == widget.steps.length - 1) {
                                    _finishTour();
                                  } else {
                                    _nextStep();
                                  }
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _currentIndex == widget.steps.length - 1 ? 'Finish Tour' : 'Next Step',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      _currentIndex == widget.steps.length - 1
                                          ? Icons.check_circle_rounded
                                          : Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
