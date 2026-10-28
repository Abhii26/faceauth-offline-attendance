import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/formatters.dart';
import 'core/theme.dart';
import 'models/attendance_log.dart';
import 'widgets/ui.dart';
import 'services/attendance_repository.dart';

/// Attendance history: 7-day trend, status filter, per-event details, CSV export.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<AttendanceLog> _logs = [];
  bool _loading = true;
  String? _error;
  AttendanceStatus? _filter; // null = all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await AttendanceRepository.getLogs(limit: 1000);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _export() async {
    if (_logs.isEmpty) {
      _snack('Nothing to export yet');
      return;
    }
    try {
      final r = await AttendanceRepository.exportCsv();
      await Clipboard.setData(ClipboardData(text: r.csv));
      _snack('Saved ${r.file.path.split('/').last} · CSV copied to clipboard');
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<AttendanceLog> get _visible => _filter == null
      ? _logs
      : _logs.where((l) => l.status == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daily = AttendanceStats.dailyPresent(_logs, now, 7);
    final uniqueToday = AttendanceStats.uniquePresentToday(_logs, now);
    final spoofs = _logs.where((l) => l.status == AttendanceStatus.spoof).length;

    return AppScaffold(
      title: 'Analytics',
      actions: [
        IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _export),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load logs\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.danger)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        _Kpi('Present today', '$uniqueToday', AppColors.accent),
                        const SizedBox(width: 12),
                        _Kpi('Events', '${_logs.length}', Colors.white),
                        const SizedBox(width: 12),
                        _Kpi('Spoof blocked', '$spoofs',
                            spoofs > 0 ? AppColors.danger : Colors.white),
                      ]),
                      const SizedBox(height: 16),
                      _TrendCard(daily: daily),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, children: [
                        _chip('All', null),
                        _chip('Present', AttendanceStatus.present),
                        _chip('Unknown', AttendanceStatus.unknown),
                        _chip('Spoof', AttendanceStatus.spoof),
                      ]),
                      const SizedBox(height: 8),
                      if (_visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text('No events yet.\nMark attendance to see them here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38)),
                          ),
                        )
                      else
                        ..._visible.map((l) => _LogTile(log: l)),
                    ],
                  ),
                ),
    );
  }

  Widget _chip(String label, AttendanceStatus? s) => ChoiceChip(
        label: Text(label),
        selected: _filter == s,
        onSelected: (_) => setState(() => _filter = s),
      );
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
      );
}

class _TrendCard extends StatelessWidget {
  final List<DailyCount> daily;
  const _TrendCard({required this.daily});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Last 7 days · present check-ins',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(painter: _BarPainter(daily)),
          ),
        ]),
      );
}

class _BarPainter extends CustomPainter {
  final List<DailyCount> data;
  _BarPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxV = data.map((d) => d.count).fold<int>(1, (a, b) => b > a ? b : a);
    const labelH = 16.0;
    final chartH = size.height - labelH - 14;
    final slot = size.width / data.length;
    final barW = slot * 0.5;

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final h = d.count == 0 ? 3.0 : (d.count / maxV) * chartH;
      final x = slot * i + (slot - barW) / 2;
      final top = 14 + chartH - h;
      final isToday = i == data.length - 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top, barW, h), const Radius.circular(5)),
        Paint()
          ..color = d.count == 0
              ? Colors.white10
              : (isToday ? AppColors.accent : AppColors.accent.withValues(alpha: 0.55)),
      );
      _text(canvas, '${d.count}', Offset(x + barW / 2, top - 13),
          Colors.white70, 10);
      _text(canvas, Fmt.weekdays[d.day.weekday - 1],
          Offset(x + barW / 2, size.height - labelH + 2), Colors.white38, 10);
    }
  }

  void _text(Canvas c, String t, Offset center, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.data != data;
}

class _LogTile extends StatelessWidget {
  final AttendanceLog log;
  const _LogTile({required this.log});

  Color get _color {
    switch (log.status) {
      case AttendanceStatus.present:
        return AppColors.success;
      case AttendanceStatus.unknown:
        return AppColors.warning;
      case AttendanceStatus.spoof:
        return AppColors.danger;
    }
  }

  IconData get _icon {
    switch (log.status) {
      case AttendanceStatus.present:
        return Icons.check_circle_outline;
      case AttendanceStatus.unknown:
        return Icons.help_outline;
      case AttendanceStatus.spoof:
        return Icons.gpp_bad_outlined;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          Icon(_icon, color: _color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(log.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(Fmt.dateTime(log.timestamp),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(log.status.label,
                style: TextStyle(
                    color: _color, fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 2),
            Text('match ${Fmt.pct(log.similarity)} · live ${Fmt.pct(log.liveness)}',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        ]),
      );
}
