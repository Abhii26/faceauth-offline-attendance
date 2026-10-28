import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/attendance_log.dart';
import 'database_service.dart';
import 'settings_service.dart';

/// Result of [AttendanceRepository.recordPresent].
class PresentResult {
  /// False when the person was already marked inside the cooldown window.
  final bool newlyRecorded;
  final AttendanceLog log;
  const PresentResult(this.newlyRecorded, this.log);
}

/// Persistence for attendance / verification events.
class AttendanceRepository {
  AttendanceRepository._();

  static const _table = 'attendance_logs';

  /// Always writes a row (used for unknown / spoof attempts).
  static Future<int> record(AttendanceLog log) async {
    final db = await DatabaseService.init();
    return db.insert(_table, log.toMap());
  }

  /// Marks someone present unless they were already marked within the
  /// configured cooldown, which prevents a burst of duplicate rows when the
  /// same person verifies several times in a row.
  static Future<PresentResult> recordPresent({
    required int? faceId,
    required String name,
    required double similarity,
    required double liveness,
    DateTime? now,
  }) async {
    final db = await DatabaseService.init();
    final ts = now ?? DateTime.now();
    final log = AttendanceLog(
      faceId: faceId,
      name: name,
      timestamp: ts,
      similarity: similarity,
      liveness: liveness,
      status: AttendanceStatus.present,
    );

    final cooldownMs = SettingsService.cooldownMinutes * 60 * 1000;
    if (cooldownMs > 0) {
      final since = ts.millisecondsSinceEpoch - cooldownMs;
      final rows = await db.query(
        _table,
        where: faceId != null
            ? 'status = ? AND face_id = ? AND timestamp >= ?'
            : 'status = ? AND name = ? AND timestamp >= ?',
        whereArgs: ['present', faceId ?? name, since],
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return PresentResult(false, AttendanceLog.fromMap(rows.first));
      }
    }

    final id = await db.insert(_table, log.toMap());
    return PresentResult(
      true,
      AttendanceLog(
        id: id,
        faceId: faceId,
        name: name,
        timestamp: ts,
        similarity: similarity,
        liveness: liveness,
        status: AttendanceStatus.present,
      ),
    );
  }

  static Future<List<AttendanceLog>> getLogs({
    AttendanceStatus? status,
    DateTime? since,
    int? limit,
  }) async {
    final db = await DatabaseService.init();
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    if (since != null) {
      where.add('timestamp >= ?');
      args.add(since.millisecondsSinceEpoch);
    }
    final rows = await db.query(
      _table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(AttendanceLog.fromMap).toList();
  }

  static Future<int> count({AttendanceStatus? status}) async {
    final db = await DatabaseService.init();
    final rows = await db.rawQuery(
      status == null
          ? 'SELECT COUNT(*) FROM $_table'
          : 'SELECT COUNT(*) FROM $_table WHERE status = ?',
      status == null ? null : [status.name],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  static Future<void> clear() async {
    final db = await DatabaseService.init();
    await db.delete(_table);
  }

  /// Writes the full log to a CSV file in the app documents directory and
  /// returns it together with the CSV text.
  static Future<({File file, String csv})> exportCsv() async {
    final logs = await getLogs();
    final csv = AttendanceStats.toCsv(logs);
    final dir = await getApplicationDocumentsDirectory();
    final d = DateTime.now();
    final stamp = '${d.year}${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}_'
        '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';
    final file = File(p.join(dir.path, 'attendance_$stamp.csv'));
    await file.writeAsString(csv, flush: true);
    debugPrint('[Attendance] exported ${logs.length} rows → ${file.path}');
    return (file: file, csv: csv);
  }
}
