import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/app_config.dart';
import '../core/similarity.dart';

/// On-device face embedding with MobileFaceNet (ente-io build).
///
///  * Input : [1, 112, 112, 3] float32, NHWC, `(pixel - 127.5) / 127.5`
///  * Output: [1, 192] embedding, L2-normalised here if the model drifts
///
/// Everything runs offline; no image ever leaves the device.
class FaceRecognitionService {
  static const _tag = '[FaceRec]';
  static const _model = 'assets/models/mobilefacenet_ente_web.tflite';
  static const _inputSz = 112;
  static const _embDim = AppConfig.embeddingDim;

  Interpreter? _interp;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> init() async {
    try {
      _interp = await Interpreter.fromAsset(
        _model,
        options: InterpreterOptions()..threads = 2,
      );
      final inShape = _interp!.getInputTensor(0).shape;
      final outShape = _interp!.getOutputTensor(0).shape;
      if (inShape.length != 4 ||
          inShape[1] != _inputSz ||
          outShape.last != _embDim) {
        debugPrint('$_tag shape mismatch: in=$inShape out=$outShape '
            '(expected [1,$_inputSz,$_inputSz,3] → [1,$_embDim])');
      }
      _loaded = true;
      debugPrint('$_tag loaded in=$inShape out=$outShape');
    } catch (e, st) {
      _loaded = false;
      debugPrint('$_tag load failed: $e\n$st');
    }
  }

  /// Returns a 192-d L2-normalised embedding, or an all-zero vector when the
  /// model is unavailable or inference fails (callers treat zeros as "no face").
  List<double> getEmbedding(img.Image face) {
    if (!_loaded || _interp == null) {
      return List.filled(_embDim, 0.0);
    }
    try {
      final resized = img.copyResize(
        face,
        width: _inputSz,
        height: _inputSz,
        interpolation: img.Interpolation.linear,
      );

      final input = [
        List.generate(
          _inputSz,
          (y) => List.generate(_inputSz, (x) {
            final px = resized.getPixel(x, y);
            return [
              (img.getRed(px) - 127.5) / 127.5,
              (img.getGreen(px) - 127.5) / 127.5,
              (img.getBlue(px) - 127.5) / 127.5,
            ];
          }),
        ),
      ];

      final output = [List<double>.filled(_embDim, 0.0)];
      _interp!.run(input, output);
      final raw = output[0];

      final n = Similarity.norm(raw);
      if (n == 0) {
        debugPrint('$_tag all-zero output — wrong or corrupt model asset?');
        return raw;
      }
      return (n - 1.0).abs() > 0.05 ? Similarity.l2Normalize(raw) : raw;
    } catch (e, st) {
      debugPrint('$_tag getEmbedding error: $e\n$st');
      return List.filled(_embDim, 0.0);
    }
  }

  /// Cosine similarity of two embeddings, in [-1, 1].
  double cosineSimilarity(List<double> a, List<double> b) =>
      Similarity.cosine(a, b);

  void dispose() {
    _interp?.close();
    _interp = null;
    _loaded = false;
  }
}
