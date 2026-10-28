import '../core/csv.dart';
import '../core/formatters.dart';

enum AttendanceStatus { present, unknown, spoof }

extension AttendanceStatusX on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.unknown:
        return 'Unknown';
      case AttendanceStatus.spoof:
        return 'Spoof';
    }
  }

  static AttendanceStatus parse(String? v) => AttendanceStatus.values
      .firstWhere((s) => s.name == v, orElse: () => AttendanceStatus.unknown);
}

/// One verification attempt (successful or not). Name is denormalised so the
/// audit trail survives deletion of the enrolled face.
class AttendanceLog {
  final int? id;
  final int? faceId;
  final String name;
  final DateTime timestamp;
  final double similarity;
  final double liveness;
  final AttendanceStatus status;

  const AttendanceLog({
    this.id,
    this.faceId,
    required this.name,
    required this.timestamp,
    required this.similarity,
    required this.liveness,
    required this.status,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'face_id': faceId,
        'name': name,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'similarity': similarity,
        'liveness': liveness,
        'status': status.name,
      };

  factory AttendanceLog.fromMap(Map<String, Object?> m) => AttendanceLog(
        id: m['id'] as int?,
        faceId: m['face_id'] as int?,
        name: m['name'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
        similarity: (m['similarity'] as num).toDouble(),
        liveness: (m['liveness'] as num).toDouble(),
        status: AttendanceStatusX.parse(m['status'] as String?),
      );
}

class DailyCount {
  final DateTime day;
  final int count;
  const DailyCount(this.day, this.count);
}

/// Pure aggregation helpers (unit-tested).
class AttendanceStats {
  AttendanceStats._();

  /// Number of *present* marks per day for the last [days] days ending at
  /// [now] (oldest first, always exactly [days] entries).
  static List<DailyCount> dailyPresent(
      List<AttendanceLog> logs, DateTime now, int days) {
    final today = DateTime(now.year, now.month, now.day);
    final out = <DailyCount>[];
    for (int i = days - 1; i >= 0; i--) {
      final d = DateTime(today.year, today.month, today.day - i);
      final c = logs
          .where((l) =>
              l.status == AttendanceStatus.present &&
              Fmt.sameDay(l.timestamp, d))
          .length;
      out.add(DailyCount(d, c));
    }
    return out;
  }

  /// Distinct people marked present on the day of [now].
  static int uniquePresentToday(List<AttendanceLog> logs, DateTime now) {
    final keys = <String>{};
    for (final l in logs) {
      if (l.status == AttendanceStatus.present && Fmt.sameDay(l.timestamp, now)) {
        keys.add(l.faceId?.toString() ?? l.name);
      }
    }
    return keys.length;
  }

  static String toCsv(List<AttendanceLog> logs) => Csv.encode(
        ['timestamp', 'name', 'status', 'similarity', 'liveness'],
        logs
            .map((l) => [
                  Fmt.isoDateTime(l.timestamp),
                  l.name,
                  l.status.label,
                  l.similarity.toStringAsFixed(4),
                  l.liveness.toStringAsFixed(4),
                ])
            .toList(),
      );
}
