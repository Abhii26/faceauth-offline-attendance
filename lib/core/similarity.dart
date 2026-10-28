import 'dart:math';

/// Pure vector maths used for face matching. Kept free of Flutter / TFLite
/// imports so it can be unit-tested on the Dart VM.
class Similarity {
  Similarity._();

  static double dot(List<double> a, List<double> b) {
    double s = 0;
    for (int i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static double norm(List<double> v) => sqrt(dot(v, v));

  /// Returns a unit-length copy (or the input unchanged if it is all zeros).
  static List<double> l2Normalize(List<double> v) {
    final n = norm(v);
    if (n == 0) return List<double>.from(v);
    return v.map((e) => e / n).toList();
  }

  /// Cosine similarity in [-1, 1]. Returns 0 for empty, mismatched or
  /// zero-length vectors instead of throwing.
  static double cosine(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;
    final na = norm(a);
    final nb = norm(b);
    if (na == 0 || nb == 0) return 0;
    return dot(a, b) / (na * nb);
  }
}
