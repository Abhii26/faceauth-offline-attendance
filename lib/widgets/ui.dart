import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Slowly drifting blurred colour blobs behind every screen.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(seconds: 14))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.bgAlt, AppColors.bg],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _AuroraPainter(_c.value)),
        ),
      ),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  void _blob(Canvas c, Offset o, double r, Color color) {
    final rect = Rect.fromCircle(center: o, radius: r);
    c.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.0),
        ]).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size s) {
    final a = t * 2 * math.pi;
    _blob(canvas, Offset(s.width * (0.15 + 0.10 * math.sin(a)), s.height * (0.12 + 0.05 * math.cos(a))),
        s.width * 0.75, AppColors.accent2);
    _blob(canvas, Offset(s.width * (0.90 + 0.06 * math.cos(a)), s.height * (0.42 + 0.06 * math.sin(a))),
        s.width * 0.70, AppColors.violet);
    _blob(canvas, Offset(s.width * (0.30 + 0.08 * math.sin(a + 2)), s.height * (0.95 - 0.04 * math.cos(a))),
        s.width * 0.80, AppColors.accent);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

/// Scaffold with the aurora behind it and a transparent app bar.
class AppScaffold extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget body;
  final bool showBack;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        automaticallyImplyLeading: showBack,
      ),
      body: AuroraBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass container.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final bool blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.borderColor,
    this.gradient,
    this.onTap,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: gradient,
        color: gradient == null ? AppColors.surface : null,
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );
    if (blur) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: content,
        ),
      );
    }
    if (onTap != null) {
      content = PressScale(onTap: onTap!, child: content);
    }
    return content;
  }
}

/// Subtle scale-down on press.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const PressScale({super.key, required this.child, required this.onTap});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _down ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      child: widget.child,
    ),
  );
}

/// Gradient pill button.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final bool loading;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient = AppColors.brandGradient,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressScale(
        onTap: enabled ? onPressed! : () {},
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent2.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: loading
              ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
              : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.black, size: 20),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
          ]),
        ),
      ),
    );
  }
}

/// Fade + slide up on first build, optionally staggered.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - v) * 24), child: c),
      ),
      child: child,
    );
  }
}

/// Number that counts up to [value].
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  const CountUp(this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) => Text(v.round().toString(), style: style),
  );
}

/// Small coloured status pill.
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const StatusPill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
      Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );
}

/// Circular arc gauge with a centred percentage.
class RingGauge extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final String label;
  final double size;
  const RingGauge({
    super.key,
    required this.value,
    required this.color,
    required this.label,
    this.size = 92,
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
    duration: const Duration(milliseconds: 1100),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(v, color),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(v * 100).round()}%',
                style: TextStyle(
                    fontSize: size * 0.22, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: TextStyle(fontSize: size * 0.11, color: AppColors.textFaint)),
          ]),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.09;
    final rect = Offset(stroke / 2, stroke / 2) & Size(s.width - stroke, s.height - stroke);
    canvas.drawArc(
        rect, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Colors.white10);
    canvas.drawArc(
        rect, -math.pi / 2, 2 * math.pi * v, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// Face-scanner overlay: dimmed surround, oval cut-out, corner brackets and
/// an animated sweep line while [scanning].
class ScannerOverlay extends StatelessWidget {
  final Color color;
  final Animation<double> sweep; // 0..1 repeating
  final bool scanning;
  const ScannerOverlay({
    super.key,
    required this.color,
    required this.sweep,
    this.scanning = true,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: sweep,
    builder: (_, __) => CustomPaint(
      painter: _ScannerPainter(color, sweep.value, scanning),
      size: Size.infinite,
    ),
  );
}

class _ScannerPainter extends CustomPainter {
  final Color color;
  final double t;
  final bool scanning;
  _ScannerPainter(this.color, this.t, this.scanning);

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.74,
      height: size.height * 0.56,
    );

    canvas.drawPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addOval(oval)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = const Color(0xFF060A14).withValues(alpha: 0.62),
    );

    // glow + ring
    canvas.drawOval(
        oval.inflate(2),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9);
    canvas.drawOval(
        oval,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // corner brackets on the oval's bounding box
    final b = oval.inflate(14);
    const len = 26.0;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c + Offset(dx * len, 0), p);
      canvas.drawLine(c, c + Offset(0, dy * len), p);
    }
    corner(b.topLeft, 1, 1);
    corner(b.topRight, -1, 1);
    corner(b.bottomLeft, 1, -1);
    corner(b.bottomRight, -1, -1);

    // sweep line clipped to the oval
    if (scanning) {
      canvas.save();
      canvas.clipPath(Path()..addOval(oval));
      final y = oval.top + oval.height * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
      final r = Rect.fromLTWH(oval.left, y - 28, oval.width, 56);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          ).createShader(r),
      );
      canvas.drawLine(Offset(oval.left, y), Offset(oval.right, y),
          Paint()..color = color.withValues(alpha: 0.9)..strokeWidth = 2);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ScannerPainter o) =>
      o.color != color || o.t != t || o.scanning != scanning;
}