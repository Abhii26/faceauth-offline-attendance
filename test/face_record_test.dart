import 'dart:typed_data';

import 'package:face_auth/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FaceRecord rec(String emb) => FaceRecord(
        id: 1,
        name: 'T',
        embeddingStr: emb,
        imageBytes: Uint8List(0),
      );

  test('parses comma-separated embedding', () {
    expect(rec('0.1,0.2,-0.3').embedding, [0.1, 0.2, -0.3]);
  });

  test('embedding is cached (same instance on repeated access)', () {
    final r = rec('1,2,3');
    expect(identical(r.embedding, r.embedding), isTrue);
  });

  test('empty or corrupt strings never throw', () {
    expect(rec('').embedding, isEmpty);
    expect(rec('1,x,3').embedding, [1.0, 0.0, 3.0]);
  });
}
