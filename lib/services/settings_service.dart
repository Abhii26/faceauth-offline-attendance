import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';

/// User-tunable recognition settings, persisted in SharedPreferences.
/// Values are cached in memory so hot paths (per-frame matching) never await.
class SettingsService {
  SettingsService._();

  static const _kMatch = 'match_threshold';
  static const _kSpoof = 'spoof_threshold';
  static const _kCooldown = 'cooldown_minutes';
  static const _kLogFailed = 'log_failed_attempts';

  static SharedPreferences? _prefs;

  static double matchThreshold = AppConfig.defaultMatchThreshold;
  static double spoofThreshold = AppConfig.defaultSpoofThreshold;
  static int cooldownMinutes = AppConfig.defaultCooldownMinutes;
  static bool logFailedAttempts = true;

  static Future<void> load() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      matchThreshold = (p.getDouble(_kMatch) ?? matchThreshold)
          .clamp(AppConfig.minMatchThreshold, AppConfig.maxMatchThreshold)
          .toDouble();
      spoofThreshold = (p.getDouble(_kSpoof) ?? spoofThreshold).clamp(0.1, 0.9).toDouble();
      cooldownMinutes = (p.getInt(_kCooldown) ?? cooldownMinutes)
          .clamp(0, AppConfig.maxCooldownMinutes);
      logFailedAttempts = p.getBool(_kLogFailed) ?? logFailedAttempts;
    } catch (e) {
      debugPrint('[Settings] load failed, using defaults: $e');
    }
  }

  static Future<void> setMatchThreshold(double v) async {
    matchThreshold = v;
    await _prefs?.setDouble(_kMatch, v);
  }

  static Future<void> setSpoofThreshold(double v) async {
    spoofThreshold = v;
    await _prefs?.setDouble(_kSpoof, v);
  }

  static Future<void> setCooldownMinutes(int v) async {
    cooldownMinutes = v;
    await _prefs?.setInt(_kCooldown, v);
  }

  static Future<void> setLogFailedAttempts(bool v) async {
    logFailedAttempts = v;
    await _prefs?.setBool(_kLogFailed, v);
  }

  static Future<void> resetToDefaults() async {
    await setMatchThreshold(AppConfig.defaultMatchThreshold);
    await setSpoofThreshold(AppConfig.defaultSpoofThreshold);
    await setCooldownMinutes(AppConfig.defaultCooldownMinutes);
    await setLogFailedAttempts(true);
  }
}
