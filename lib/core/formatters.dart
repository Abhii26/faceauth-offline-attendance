/// Tiny date helpers (avoids pulling in `intl` for three formats).
class Fmt {
  Fmt._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String two(int n) => n.toString().padLeft(2, '0');

  static String time(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  static String date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String dateTime(DateTime d) => '${date(d)}, ${time(d)}';

  static String isoDateTime(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';

  static String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
