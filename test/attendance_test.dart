import 'package:face_auth/core/csv.dart';
import 'package:face_auth/models/attendance_log.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceLog _log(String name, DateTime t,
        {AttendanceStatus s = AttendanceStatus.present, int? id}) =>
    AttendanceLog(
      faceId: id,
      name: name,
      timestamp: t,
      similarity: 0.8,
      liveness: 0.9,
      status: s,
    );

void main() {
  final now = DateTime(2026, 10, 27, 15, 30);

  group('AttendanceLog map round-trip', () {
    test('preserves all fields', () {
      final l = _log('Asha', now, id: 7);
      final back = AttendanceLog.fromMap(l.toMap());
      expect(back.name, 'Asha');
      expect(back.faceId, 7);
      expect(back.timestamp, now);
      expect(back.status, AttendanceStatus.present);
      expect(back.similarity, closeTo(0.8, 1e-9));
    });

    test('unknown status string falls back to unknown', () {
      expect(AttendanceStatusX.parse('???'), AttendanceStatus.unknown);
      expect(AttendanceStatusX.parse(null), AttendanceStatus.unknown);
    });
  });

  group('AttendanceStats.dailyPresent', () {
    test('always returns exactly N days, oldest first, zero-filled', () {
      final out = AttendanceStats.dailyPresent([], now, 7);
      expect(out.length, 7);
      expect(out.every((d) => d.count == 0), isTrue);
      expect(out.last.day, DateTime(2026, 10, 27));
      expect(out.first.day, DateTime(2026, 10, 21));
    });

    test('counts only present events, per day', () {
      final logs = [
        _log('A', DateTime(2026, 10, 27, 9), id: 1),
        _log('B', DateTime(2026, 10, 27, 10), id: 2),
        _log('A', DateTime(2026, 10, 26, 9), id: 1),
        _log('X', DateTime(2026, 10, 27, 11), s: AttendanceStatus.spoof),
        _log('Y', DateTime(2026, 10, 27, 12), s: AttendanceStatus.unknown),
      ];
      final out = AttendanceStats.dailyPresent(logs, now, 7);
      expect(out.last.count, 2);
      expect(out[5].count, 1);
    });

    test('works across a month boundary', () {
      final out = AttendanceStats.dailyPresent([], DateTime(2026, 11, 2), 7);
      expect(out.first.day, DateTime(2026, 10, 27));
    });
  });

  group('AttendanceStats.uniquePresentToday', () {
    test('de-duplicates the same person', () {
      final logs = [
        _log('A', DateTime(2026, 10, 27, 9), id: 1),
        _log('A', DateTime(2026, 10, 27, 14), id: 1),
        _log('B', DateTime(2026, 10, 27, 10), id: 2),
        _log('C', DateTime(2026, 10, 26, 10), id: 3),
      ];
      expect(AttendanceStats.uniquePresentToday(logs, now), 2);
    });
  });

  group('CSV export', () {
    test('escapes commas and quotes', () {
      expect(Csv.escape('plain'), 'plain');
      expect(Csv.escape('a,b'), '"a,b"');
      expect(Csv.escape('say "hi"'), '"say ""hi"""');
    });

    test('header + one row per log', () {
      final csv = AttendanceStats.toCsv([_log('Doe, John', now)]);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2);
      expect(lines.first, 'timestamp,name,status,similarity,liveness');
      expect(lines[1], contains('"Doe, John"'));
      expect(lines[1], contains('2026-10-27 15:30:00'));
      expect(lines[1], contains('Present'));
    });
  });
}
