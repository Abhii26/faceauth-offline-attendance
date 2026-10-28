import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/theme.dart';
import 'widgets/ui.dart';
import 'diagnostic_screen.dart';
import 'services/attendance_repository.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';

/// Recognition tuning, data management and diagnostics.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _match = SettingsService.matchThreshold;
  late double _spoof = SettingsService.spoofThreshold;
  late int _cooldown = SettingsService.cooldownMinutes;
  late bool _logFailed = SettingsService.logFailedAttempts;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(title),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Recognition'),
          _card([
            _sliderRow(
              title: 'Match threshold',
              hint: 'Higher = stricter (fewer false accepts, more rejects).',
              value: _match,
              min: AppConfig.minMatchThreshold,
              max: AppConfig.maxMatchThreshold,
              divisions: 50,
              label: _match.toStringAsFixed(2),
              onChanged: (v) => setState(() => _match = v),
              onEnd: (v) => SettingsService.setMatchThreshold(v),
            ),
            const Divider(height: 1, color: Colors.white10),
            _sliderRow(
              title: 'Spoof threshold',
              hint: 'Liveness score below this (on both models) flags a spoof.',
              value: _spoof,
              min: 0.1,
              max: 0.9,
              divisions: 40,
              label: _spoof.toStringAsFixed(2),
              onChanged: (v) => setState(() => _spoof = v),
              onEnd: (v) => SettingsService.setSpoofThreshold(v),
            ),
          ]),
          _section('Attendance'),
          _card([
            _sliderRow(
              title: 'Duplicate cooldown',
              hint: 'Minutes before the same person can be marked present again '
                  '(0 = always record).',
              value: _cooldown.toDouble(),
              min: 0,
              max: AppConfig.maxCooldownMinutes.toDouble(),
              divisions: AppConfig.maxCooldownMinutes,
              label: '$_cooldown min',
              onChanged: (v) => setState(() => _cooldown = v.round()),
              onEnd: (v) => SettingsService.setCooldownMinutes(v.round()),
            ),
            const Divider(height: 1, color: Colors.white10),
            SwitchListTile(
              value: _logFailed,
              activeColor: AppColors.accent,
              title: const Text('Log unknown & spoof attempts'),
              subtitle: const Text('Keeps an audit trail of failed verifications.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onChanged: (v) {
                setState(() => _logFailed = v);
                SettingsService.setLogFailedAttempts(v);
              },
            ),
          ]),
          _section('Data & diagnostics'),
          _card([
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined, color: AppColors.info),
              title: const Text('Run diagnostics'),
              subtitle: const Text('Check models, inference and database.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DiagnosticScreen())),
            ),
            const Divider(height: 1, color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.restart_alt, color: AppColors.warning),
              title: const Text('Reset settings to defaults'),
              onTap: () async {
                await SettingsService.resetToDefaults();
                setState(() {
                  _match = SettingsService.matchThreshold;
                  _spoof = SettingsService.spoofThreshold;
                  _cooldown = SettingsService.cooldownMinutes;
                  _logFailed = SettingsService.logFailedAttempts;
                });
                _snack('Settings reset');
              },
            ),
            const Divider(height: 1, color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
              title: const Text('Clear attendance history'),
              onTap: () async {
                if (await _confirm('Clear attendance history?',
                    'All attendance events will be permanently deleted.')) {
                  await AttendanceRepository.clear();
                  _snack('Attendance history cleared');
                }
              },
            ),
            const Divider(height: 1, color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.danger),
              title: const Text('Delete ALL data'),
              subtitle: const Text('Removes every enrolled face and all history.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () async {
                if (await _confirm('Delete all data?',
                    'Every enrolled face, embedding and attendance record will be erased. This cannot be undone.')) {
                  await DatabaseService.resetAll();
                  _snack('All data deleted');
                }
              },
            ),
          ]),
          _section('About'),
          _card([
            const ListTile(
              leading: Icon(Icons.info_outline, color: Colors.white54),
              title: Text('${AppConfig.appName} v${AppConfig.appVersion}'),
              subtitle: Text(
                  'On-device ML (MobileFaceNet + ML Kit + TFLite). No data leaves the phone.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _sliderRow({
    required String title,
    required String hint,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(label,
                style: const TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.bold)),
          ]),
          Text(hint, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.accent,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ]),
      );
}
