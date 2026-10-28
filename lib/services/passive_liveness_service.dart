import 'package:face_anti_spoofing_detector/face_anti_spoofing_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:typed_data';


class PassiveLivenessService {
  static const _tag = '[PassiveLiveness]';
  bool _initialized = false;

  bool get isReady => _initialized;

  Future<void> init() async {
    debugPrint('$_tag init()');
    try {
      final status = await FaceAntiSpoofingDetector.initialize();
      _initialized = true;
      debugPrint('$_tag initialize() status=$status  ✅');
    } catch (e) {
      _initialized = false;
      debugPrint('$_tag initialize() FAILED: $e — will use fallback 0.85');
    }
  }


  Future<double> predict({
    required List<int> yuvBytes,
    required int previewWidth,
    required int previewHeight,
    required int sensorDeg,
    required Face face,
    double fallback = 0.85,
  }) async {
    if (!_initialized) return fallback;

    try {
      final orientation = _orientationFromSensorDeg(sensorDeg);

      final score = await FaceAntiSpoofingDetector.detect(
        yuvBytes: Uint8List.fromList(yuvBytes),
        previewWidth: previewWidth,
        previewHeight: previewHeight,
        orientation: orientation,
        faceContour: face.boundingBox,
      );

      final result = (score ?? fallback).clamp(0.0, 1.0).toDouble();

      debugPrint('$_tag predict() → $result');

      return result;
    } catch (e) {
      debugPrint('$_tag predict() error: $e — returning fallback $fallback');
      return fallback;
    }
  }


  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await FaceAntiSpoofingDetector.destroy();
      debugPrint('$_tag destroy() ✅');
    } catch (e) {
      debugPrint('$_tag destroy() error: $e');
    }
    _initialized = false;
  }

  int _orientationFromSensorDeg(int deg) {
    switch (deg) {
      case 90:  return 7;
      case 180: return 2;
      case 270: return 3;
      default:  return 0;
    }
  }
}