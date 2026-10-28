import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'home_screen.dart';
import 'widgets/ui.dart';

/// Animated intro: logo pulse + scan sweep, then fades into Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..forward();
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _in.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _in, curve: Curves.elasticOut);
    final fade = CurvedAnimation(parent: _in, curve: Curves.easeOut);
    return Scaffold(
      body: AuroraBackground(
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(
                scale: scale,
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: Stack(alignment: Alignment.center, children: [
                    ScannerOverlayRing(sweep: _sweep),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.brandGradient,
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.accent2.withValues(alpha: 0.5),
                              blurRadius: 40,
                              spreadRadius: 2),
                        ],
                      ),
                      child: const Icon(Icons.face_retouching_natural,
                          size: 52, color: Colors.black),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (r) => AppColors.brandGradient.createShader(r),
                child: const Text(AppConfig.appName,
                    style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Colors.white)),
              ),
              const SizedBox(height: 8),
              const Text('Offline • Private • Liveness-protected',
                  style: TextStyle(color: AppColors.textFaint, letterSpacing: 1.2, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Rotating dashed ring used on the splash.
class ScannerOverlayRing extends StatelessWidget {
  final Animation<double> sweep;
  const ScannerOverlayRing({super.key, required this.sweep});

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: sweep,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 2),
            gradient: SweepGradient(colors: [
              AppColors.accent2.withValues(alpha: 0.0),
              AppColors.accent2.withValues(alpha: 0.5),
            ]),
          ),
        ),
      );
}
