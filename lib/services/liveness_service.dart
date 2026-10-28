import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Texture-based passive anti-spoofing (TFLite). 0.0 = fake, 1.0 = real.
///
/// NOTE: if the model cannot be loaded this service *fails open* and returns
/// [fallbackScore]; check [isLoaded] (surfaced in Diagnostics) before relying
/// on it in a security-sensitive deployment.
class LivenessService {
  static const _tag = '[Liveness]';
  static const double fallbackScore = 0.85;

  Interpreter? _interpreter;
  bool _isLoaded = false;
  int _inputW = 80;
  int _inputH = 80;
  int _outputSize = 1;

  bool get isLoaded => _isLoaded;

  Future<void> init() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/liveness.tflite',
        options: InterpreterOptions()..threads = 1,
      );
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 3) {
        _inputH = inputShape[1];
        _inputW = inputShape[2];
      }
      _outputSize = _interpreter!.getOutputTensor(0).shape.last;
      _isLoaded = true;
      debugPrint('$_tag loaded in=${_inputH}x$_inputW out=$_outputSize');
    } catch (e) {
      _isLoaded = false;
      debugPrint('$_tag load failed: $e — falling back to $fallbackScore');
    }
  }

  double predict(img.Image face) {
    if (!_isLoaded || _interpreter == null) return fallbackScore;
    try {
      final resized = img.copyResize(face, width: _inputW, height: _inputH);
      final input = [
        List.generate(
          _inputH,
          (y) => List.generate(_inputW, (x) {
            final px = resized.getPixel(x, y);
            return [
              img.getRed(px) / 255.0,
              img.getGreen(px) / 255.0,
              img.getBlue(px) / 255.0,
            ];
          }),
        ),
      ];

      if (_outputSize == 1) {
        final output = [List<double>.filled(1, 0.0)];
        _interpreter!.run(input, output);
        return output[0][0].clamp(0.0, 1.0).toDouble();
      }
      final output = [List<double>.filled(_outputSize, 0.0)];
      _interpreter!.run(input, output);
      final expF = exp(output[0][0]);
      final expR = exp(output[0][1]);
      return expR / (expF + expR);
    } catch (e) {
      debugPrint('$_tag predict error: $e');
      return fallbackScore;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
