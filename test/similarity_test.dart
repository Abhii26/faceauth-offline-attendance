import 'package:face_auth/core/similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Similarity.cosine', () {
    test('identical vectors → 1', () {
      expect(Similarity.cosine([1, 2, 3], [1, 2, 3]), closeTo(1.0, 1e-9));
    });

    test('opposite vectors → -1', () {
      expect(Similarity.cosine([1, 0], [-1, 0]), closeTo(-1.0, 1e-9));
    });

    test('orthogonal vectors → 0', () {
      expect(Similarity.cosine([1, 0], [0, 1]), closeTo(0.0, 1e-9));
    });

    test('is scale invariant', () {
      expect(Similarity.cosine([1, 2, 3], [10, 20, 30]), closeTo(1.0, 1e-9));
    });

    test('empty, mismatched or zero vectors → 0 (never throws)', () {
      expect(Similarity.cosine([], []), 0);
      expect(Similarity.cosine([1, 2], [1, 2, 3]), 0);
      expect(Similarity.cosine([0, 0], [1, 1]), 0);
    });
  });

  group('Similarity.l2Normalize', () {
    test('produces unit length', () {
      final n = Similarity.l2Normalize([3, 4]);
      expect(Similarity.norm(n), closeTo(1.0, 1e-9));
      expect(n[0], closeTo(0.6, 1e-9));
    });

    test('zero vector stays zero', () {
      expect(Similarity.l2Normalize([0, 0, 0]), [0, 0, 0]);
    });
  });
}
