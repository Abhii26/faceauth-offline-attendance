import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../services/settings_service.dart';
import '../widgets/ui.dart';

/// Verification outcome with animated status, face comparison and score gauges.
///
/// enrolledImage = registered cropped face from DB
/// currentImage  = just-captured cropped face from camera
class ResultScreen extends StatefulWidget {
  final Uint8List enrolledImage;
  final Uint8List currentImage;
  final String name;
  final double similarity;
  final double liveness;

  /// True when this person was already marked present within the cooldown.
  final bool alreadyMarked;

  const ResultScreen({
    super.key,
    required this.enrolledImage,
    required this.currentImage,
    required this.name,
    required this.similarity,
    required this.liveness,
    this.alreadyMarked = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  static const _autoDismiss = Duration(seconds: 12);

  bool get _matched =>
      widget.name != 'Unknown' && widget.similarity > SettingsService.matchThreshold;
  bool get _isReal => widget.liveness >= SettingsService.spoofThreshold;
  bool get _verified => _matched && _isReal;

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..forward();
  Timer? _timer;
  final DateTime _at = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer(_autoDismiss, () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Color get _color => _verified
      ? AppColors.success
      : !_isReal
          ? AppColors.danger
          : AppColors.warning;

  IconData get _icon => _verified
      ? Icons.check_rounded
      : !_isReal
          ? Icons.gpp_bad_rounded
          : Icons.question_mark_rounded;

  String get _title => _verified
      ? 'Verified'
      : !_isReal
          ? 'Spoof blocked'
          : 'Not recognised';

  String get _subtitle => _verified
      ? (widget.alreadyMarked ? 'Already marked recently' : 'Attendance recorded')
      : !_isReal
          ? 'Liveness check failed'
          : 'No enrolled face matched';

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    final fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: fade,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(Fmt.dateTime(_at),
                      style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
                  const SizedBox(width: 12),
                ]),
                const SizedBox(height: 8),

                // ── Status hero ─────────────────────────────────────────
                Center(
                  child: ScaleTransition(
                    scale: pop,
                    child: Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _color.withValues(alpha: 0.14),
                        border: Border.all(color: _color, width: 3),
                        boxShadow: [
                          BoxShadow(
                              color: _color.withValues(alpha: 0.45),
                              blurRadius: 44,
                              spreadRadius: 2),
                        ],
                      ),
                      child: Icon(_icon, size: 62, color: _color),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(_title,
                      style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w900, color: _color)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(_subtitle,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 14)),
                ),
                if (_verified) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Text(widget.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Face comparison ─────────────────────────────────────
                FadeSlideIn(
                  index: 1,
                  child: GlassCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _face('Registered', widget.enrolledImage, _matched),
                      Icon(Icons.compare_arrows_rounded,
                          size: 30,
                          color: _matched ? AppColors.success : AppColors.textFaint),
                      _face('Captured', widget.currentImage, true),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Gauges ──────────────────────────────────────────────
                FadeSlideIn(
                  index: 2,
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      Column(children: [
                        RingGauge(
                          value: widget.similarity,
                          color: _matched ? AppColors.success : AppColors.warning,
                          label: 'match',
                        ),
                        const SizedBox(height: 8),
                        Text('needs > ${(SettingsService.matchThreshold * 100).round()}%',
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 11)),
                      ]),
                      Column(children: [
                        RingGauge(
                          value: widget.liveness,
                          color: _isReal ? AppColors.success : AppColors.danger,
                          label: 'liveness',
                        ),
                        const SizedBox(height: 8),
                        Text('needs ≥ ${(SettingsService.spoofThreshold * 100).round()}%',
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 11)),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                if (_verified)
                  FadeSlideIn(
                    index: 3,
                    child: Center(
                      child: StatusPill(
                        widget.alreadyMarked ? 'ALREADY MARKED' : 'ATTENDANCE RECORDED',
                        widget.alreadyMarked ? AppColors.warning : AppColors.success,
                        icon: widget.alreadyMarked
                            ? Icons.history_toggle_off_rounded
                            : Icons.event_available_rounded,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),

                GradientButton(
                  label: 'Done',
                  icon: Icons.check_circle_outline_rounded,
                  gradient: _verified ? AppColors.brandGradient : AppColors.dangerGradient,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(height: 12),

                // auto-dismiss countdown
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1, end: 0),
                    duration: _autoDismiss,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 3,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation(_color.withValues(alpha: 0.7)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text('Closing automatically',
                      style: TextStyle(color: AppColors.textFaint, fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(String label, Uint8List bytes, bool ok) => Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: ok ? AppColors.brandGradient : null,
            color: ok ? null : Colors.white12,
          ),
          child: ClipOval(
            child: Image.memory(bytes,
                width: 96, height: 96, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
      ]);
}
