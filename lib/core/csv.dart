/// Minimal RFC-4180 style CSV writer.
class Csv {
  Csv._();

  static String escape(String v) {
    final needsQuotes =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    if (!needsQuotes) return v;
    return '"${v.replaceAll('"', '""')}"';
  }

  static String encode(List<String> header, List<List<String>> rows) {
    final sb = StringBuffer()..writeln(header.map(escape).join(','));
    for (final r in rows) {
      sb.writeln(r.map(escape).join(','));
    }
    return sb.toString();
  }
}
