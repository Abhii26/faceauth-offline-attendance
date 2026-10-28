import 'package:flutter/material.dart';

import 'attendance_screen.dart';
import 'core/app_config.dart';
import 'core/theme.dart';
import 'models/attendance_log.dart';
import 'recognition_screen.dart';
import 'registered_faces_screen.dart';
import 'registration_screen.dart';
import 'services/attendance_repository.dart';
import 'services/database_service.dart';
import 'settings_screen.dart';
import 'widgets/ui.dart';

class _HomeStats {
  final int registered;
  final int presentToday;
  final int totalEvents;
  const _HomeStats(this.registered, this.presentToday, this.totalEvents);
}

/// Dashboard: greeting, live stats, hero scan action and feature tiles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late Future<_HomeStats> _stats = _loadStats();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<_HomeStats> _loadStats() async {
    final registered = await DatabaseService.countFaces();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final todays = await AttendanceRepository.getLogs(
        status: AttendanceStatus.present, since: startOfDay);
    final unique = AttendanceStats.uniquePresentToday(todays, today);
    final total = await AttendanceRepository.count();
    return _HomeStats(registered, unique, total);
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() => _stats = _loadStats());
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async => setState(() => _stats = _loadStats()),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                FadeSlideIn(
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, gradient: AppColors.brandGradient),
                      child: const Icon(Icons.face_retouching_natural, color: Colors.black),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_greeting,
                            style: const TextStyle(color: AppColors.textFaint, fontSize: 13)),
                        const Text(AppConfig.appName,
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ]),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Settings',
                      style: IconButton.styleFrom(backgroundColor: AppColors.surface),
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => _open(const SettingsScreen()),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),

                // ── Hero scan card ──────────────────────────────────────────
                FadeSlideIn(
                  index: 1,
                  child: GlassCard(
                    onTap: () => _open(const RecognitionScreen()),
                    radius: 28,
                    padding: const EdgeInsets.all(22),
                    borderColor: AppColors.accent.withValues(alpha: 0.35),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.18),
                        AppColors.accent2.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const StatusPill('LIVENESS PROTECTED', AppColors.accent,
                              icon: Icons.shield_rounded),
                          const SizedBox(height: 14),
                          const Text('Mark\nAttendance',
                              style: TextStyle(
                                  fontSize: 30, height: 1.05, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          const Text('Blink, smile, turn — we verify it\'s really you.',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                                gradient: AppColors.brandGradient,
                                borderRadius: BorderRadius.circular(14)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Start scan',
                                  style: TextStyle(
                                      color: Colors.black, fontWeight: FontWeight.w800)),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 18),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        height: 110,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => CustomPaint(
                            painter: _PulsePainter(_pulse.value),
                            child: const Center(
                              child: Icon(Icons.face_retouching_natural,
                                  size: 52, color: AppColors.accent),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Stats ───────────────────────────────────────────────────
                FutureBuilder<_HomeStats>(
                  future: _stats,
                  builder: (context, snap) {
                    final s = snap.data;
                    return FadeSlideIn(
                      index: 2,
                      child: Row(children: [
                        _StatTile(Icons.people_alt_rounded, 'Registered', s?.registered,
                            AppColors.info),
                        const SizedBox(width: 10),
                        _StatTile(Icons.how_to_reg_rounded, 'Present today', s?.presentToday,
                            AppColors.accent),
                        const SizedBox(width: 10),
                        _StatTile(Icons.bolt_rounded, 'Total scans', s?.totalEvents,
                            AppColors.violet),
                      ]),
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text('Quick actions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                FadeSlideIn(
                  index: 3,
                  child: Row(children: [
                    _Tile(Icons.person_add_alt_1_rounded, 'Register', 'Enrol a face',
                        AppColors.accent2, () => _open(const RegistrationScreen())),
                    const SizedBox(width: 12),
                    _Tile(Icons.insights_rounded, 'Analytics', 'Logs & export',
                        AppColors.violet, () => _open(const AttendanceScreen())),
                  ]),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  index: 4,
                  child: Row(children: [
                    _Tile(Icons.groups_rounded, 'People', 'Manage faces', AppColors.info,
                        () => _open(const RegisteredFacesScreen())),
                    const SizedBox(width: 12),
                    _Tile(Icons.settings_suggest_rounded, 'Settings', 'Tune & diagnose',
                        AppColors.warning, () => _open(const SettingsScreen())),
                  ]),
                ),
                const SizedBox(height: 26),
                const Center(
                  child: Text('100% on-device • no data leaves your phone',
                      style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double t;
  _PulsePainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    for (int i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      canvas.drawCircle(
        c,
        s.width * (0.28 + 0.24 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.accent.withValues(alpha: (1 - p) * 0.55),
      );
    }
    canvas.drawCircle(c, s.width * 0.3,
        Paint()..color = AppColors.accent.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t;
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? value;
  final Color color;
  const _StatTile(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          radius: 20,
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            value == null
                ? const Text('–', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))
                : CountUp(value!,
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
          ]),
        ),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _Tile(this.icon, this.title, this.subtitle, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassCard(
          onTap: onTap,
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ]),
        ),
      );
}
