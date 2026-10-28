// lib/recognition_screen.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'liveness_challenge.dart';
import 'models/attendance_log.dart';
import 'services/attendance_repository.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/face_recognition_service.dart';
import 'services/liveness_service.dart';
import 'screens/result_screen.dart';
import 'services/passive_liveness_service.dart';
import 'core/theme.dart';
import 'widgets/ui.dart';


// ─────────────────────────────────────────────────────────────────────────────
// MatchResult
// ─────────────────────────────────────────────────────────────────────────────
class MatchResult {
  final String name;
  final double score;
  final Uint8List croppedImage;
  final int? faceId;
  MatchResult(this.name, this.score, this.croppedImage, {this.faceId});
}

// ─────────────────────────────────────────────────────────────────────────────
// RecognitionCandidate - stores recognition result with face quality
// ─────────────────────────────────────────────────────────────────────────────
class RecognitionCandidate {
  final MatchResult? match;
  final double livenessScore;
  final double passiveScore;
  final double faceQuality;
  final img.Image cropped;

  /// JPEG is encoded lazily: most candidates never become the best one.
  late final Uint8List croppedFace = Uint8List.fromList(img.encodeJpg(cropped));
  final List<double> embedding;
  final DateTime timestamp;

  RecognitionCandidate({
    required this.match,
    required this.livenessScore,
    required this.passiveScore,
    required this.faceQuality,
    required this.cropped,
    required this.embedding,
    required this.timestamp,
  });

  // Composite score for ranking candidates
  // double get compositeScore {
  //   if (match == null) return 0.0;
  //   // Weight: 50% match score, 30% face quality, 20% liveness
  //   return (match.score * 0.5) + (faceQuality * 0.3) + (livenessScore * 0.2);
  // }

  double get fusedLiveness => (livenessScore + passiveScore) / 2.0;

  /// Composite score: 50% match, 25% face quality, 15% TFLite liveness, 10% passive
  double get compositeScore {
    final m = match;
    if (m == null) return 0.0;
    return (m.score * 0.50) +
        (faceQuality * 0.25) +
        (livenessScore * 0.15) +
        (passiveScore * 0.10);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RecognitionScreen
// ─────────────────────────────────────────────────────────────────────────────
class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen>
    with TickerProviderStateMixin {

  // ── Services ─────────────────────────────────────────────────────────────
  CameraController? _cam;
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: false,
      enableClassification: true,
      enableContours: false,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.1,
    ),
  );
  final LivenessService _liveness = LivenessService();
  final FaceRecognitionService _faceRec = FaceRecognitionService();
  final PassiveLivenessService _passive = PassiveLivenessService();
  List<FaceRecord> _cachedFaces = [];
  bool _disposed = false;
  bool _ready = false;

  // ── Stream state ──────────────────────────────────────────────────────────
  bool _processing = false;
  bool _livenessComplete = false;
  bool _navigated = false;

  // ── Face state ────────────────────────────────────────────────────────────
  bool _facePresent = false;
  bool _faceAligned = false;

  // ── Camera info ───────────────────────────────────────────────────────────
  int _sensorDeg = 90;
  bool _isFront = true;

  // ── Liveness steps ────────────────────────────────────────────────────────
  final List<LivenessStep> _steps = [
    LivenessStep.blink,
    LivenessStep.smile,
    LivenessStep.turnLeft,
    LivenessStep.turnRight,
  ];
  int _stepIdx = 0;
  List<bool> _stepDone = [false, false, false, false];

  List<int> _latestYuvBytes = [];

  int _gestureCount = 0;
  /// A blink lasts ~150 ms, so one closed-eye frame (after seeing open eyes)
  /// is enough; other gestures need 2 consecutive confirmations.
  int get _gestureNeeded =>
      (_stepIdx < _steps.length && _steps[_stepIdx] == LivenessStep.blink) ? 1 : 2;
  bool _sawEyesOpen = false;
  bool _awaitNeutral = false;
  int _neutralCount = 0;
  static const int _neutralNeeded = 2;

  bool _modelLivenessFailed = false;
  double _latestLivenessScore = 0.85;
  int _lowLivenessCount = 0;                    // ← ADD THIS
  static const int _lowLivenessNeeded = 3;      // ← ADD THIS (need 3 consecutive bad frames)

  // ── PARALLEL background recognition with quality tracking ─────────────────
  // Store multiple candidates during liveness, pick the best one at the end
  final List<RecognitionCandidate> _candidates = [];
  static const int _maxCandidates = 10;  // Keep last 10 good candidates
  bool _bgRunning = false;
  int _bgSkip = 0;
  static const int _bgInterval = 8;  // heavy work (embedding/liveness) every 8th aligned frame

  // Best candidate found so far
  RecognitionCandidate? _bestCandidate;

  // ── Post-liveness state ───────────────────────────────────────────────────
  bool _finalizingRecognition = false;
  bool _recognitionComplete = false;

  // ── Debug ─────────────────────────────────────────────────────────────────
  bool _dbg = false;
  double _dbgL = -1, _dbgR = -1, _dbgS = -1, _dbgY = 0;
  int _dbgNonZero = 0;
  double _dbgPassiveScore = -1;
  String _dbgMsg = "init";

  late AnimationController _pulse;
  late AnimationController _loadingAnim;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _loadingAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _init();
  }

  Future<void> _init() async {
    debugPrint('[RecognitionScreen] _init() — starting');

    await _liveness.init();
    await _passive.init();
    await _faceRec.init();
    _cachedFaces = await DatabaseService.getFaces();
    debugPrint('[RecognitionScreen] ${_cachedFaces.length} registered face(s)');

    if (_disposed) return;
    setState(() => _ready = true);
    await _startCamera();
  }

  Future<void> _startCamera() async {
    debugPrint('[RecognitionScreen] _startCamera()');
    final cameras = await availableCameras();
    CameraDescription cam;
    try {
      cam = cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front);
      _isFront = true;
    } catch (_) {
      cam = cameras.first;
      _isFront = false;
    }
    _sensorDeg = cam.sensorOrientation;
    debugPrint('[RecognitionScreen] sensor=$_sensorDeg  front=$_isFront');

    _cam = CameraController(
      cam,
      ResolutionPreset.medium,        // 480p: 3x fewer pixels → much faster stream
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _cam!.initialize();
    debugPrint('[RecognitionScreen] preview=${_cam!.value.previewSize}');

    if (!mounted) {
      await _cam?.dispose();
      return;
    }
    setState(() {});
    _startStream();
  }

  // ─── Stream ───────────────────────────────────────────────────────────────
  void _startStream() {
    debugPrint('[RecognitionScreen] _startStream()');
    _cam?.startImageStream((CameraImage frame) async {
      if (_processing || _navigated || !_ready) return;
      _processing = true;

      try {

        final bytes = _frameBytes(frame);
        _latestYuvBytes = bytes;

        final inputImage = _toInputImage(frame, bytes);
        final faces = await _detector.processImage(inputImage);

        if (!mounted) {
          _processing = false;
          return;
        }

        if (faces.isEmpty) {
          if (mounted) {
            setState(() {
              _facePresent = false;
              _faceAligned = false;
              _gestureCount = 0;
              _awaitNeutral = false;
              _dbgMsg = 'no face';
            });
          }
          _processing = false;
          return;
        }

        final face = faces.first;
        final aligned = _isAligned(face, _uprightW(frame), _uprightH(frame));

        if (mounted) {
          setState(() {
            _facePresent = true;
            _faceAligned = aligned;
            _dbgL = face.leftEyeOpenProbability ?? -1;
            _dbgR = face.rightEyeOpenProbability ?? -1;
            _dbgS = face.smilingProbability ?? -1;
            _dbgY = face.headEulerAngleY ?? 0;
            _dbgMsg = aligned ? 'aligned' : 'not aligned';
          });
        }

        if (!aligned) {
          _processing = false;
          return;
        }

        // ── Liveness steps (runs on every aligned frame) ──────────────────
        if (!_livenessComplete) {
          _doStep(face);
        }

        // ── PARALLEL background recognition with quality scoring ──────────
        // Only run if not already finalizing
        if (!_finalizingRecognition && !_livenessComplete) {
          _bgSkip++;
          if (_bgSkip >= _bgInterval) {
            _bgSkip = 0;
            // Fire and forget - don't await
            _bgRecognitionWithQuality(frame, face);
          }
        }

        // ── Liveness just completed ───────────────────────────────────────
        if (_stepIdx >= _steps.length && !_livenessComplete && !_finalizingRecognition) {
          _livenessComplete = true;
          debugPrint('[RecognitionScreen] ✅ Liveness complete!');
          debugPrint('[RecognitionScreen] 📊 Collected ${_candidates.length} candidates during liveness');

          if (_modelLivenessFailed) {
            debugPrint('[RecognitionScreen] 🚫 Model detected spoof - rejecting');
            _showSpoofRejectionDialog();
            _processing = false;
            return;
          }

          // Start finalizing - use the best candidate we already have
          _finalizeWithBestCandidate(frame, face);
        }
      } catch (e, st) {
        debugPrint('[RecognitionScreen] stream error: $e\n$st');
        if (mounted) setState(() => _dbgMsg = 'err: $e');
      }

      _processing = false;
    });
  }

  // ─── Face Quality Scoring ─────────────────────────────────────────────────
  /// Scores face quality from 0 to 1 based on multiple factors
  double _evaluateFaceQuality(Face face) {
    double score = 1.0;

    // Penalize head rotation (yaw) - we want straight face
    final yaw = (face.headEulerAngleY ?? 0).abs();
    if (yaw > 20) score *= 0.3;      // Heavy penalty for side face
    else if (yaw > 12) score *= 0.6;
    else if (yaw > 8) score *= 0.8;

    // Penalize pitch (looking up/down)
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (pitch > 20) score *= 0.4;
    else if (pitch > 12) score *= 0.7;
    else if (pitch > 8) score *= 0.85;

    // Penalize roll (tilted head)
    final roll = (face.headEulerAngleZ ?? 0).abs();
    if (roll > 15) score *= 0.5;
    else if (roll > 8) score *= 0.8;

    // Prefer eyes open
    final leftEye = face.leftEyeOpenProbability ?? 0.5;
    final rightEye = face.rightEyeOpenProbability ?? 0.5;
    final eyeScore = (leftEye + rightEye) / 2;
    if (eyeScore < 0.4) score *= 0.5;
    else if (eyeScore < 0.6) score *= 0.8;

    // Prefer neutral expression (not extreme smile)
    final smile = face.smilingProbability ?? 0.5;
    if (smile > 0.7) score *= 0.7;
    else if (smile > 0.5) score *= 0.9;

    return score.clamp(0.0, 1.0);
  }

  // ─── Background Recognition with Quality Tracking ─────────────────────────
  Future<void> _bgRecognitionWithQuality(CameraImage frame, Face face) async {
    if (_bgRunning) return;
    _bgRunning = true;

    try {
      final faceQuality = _evaluateFaceQuality(face);
      if (faceQuality < 0.4) {
        _bgRunning = false;
        return;
      }

      final cropped = _cropFace(frame, face);

      // ── TFLite liveness (existing) ────────────────────────────────────
      final tfliteLive = _liveness.predict(cropped);

      // ── Passive anti-spoofing (NEW) ───────────────────────────────────
      double passiveLive = 0.85; // safe default
      try {
        passiveLive = await _passive.predict(
          yuvBytes: _latestYuvBytes,
          previewWidth: frame.width,
          previewHeight: frame.height,
          sensorDeg: _sensorDeg,
          face: face,
        );
      } catch (e) {
        debugPrint('[RecognitionScreen] passive predict error: $e');
      }
      // ─────────────────────────────────────────────────────────────────

      // Fused score
      final fusedLive = (tfliteLive + passiveLive) / 2.0;

// Only flag spoof if BOTH models are low AND it happens 3 times in a row
      final spoofT = SettingsService.spoofThreshold;
      if (tfliteLive < spoofT && passiveLive < spoofT) {
        _lowLivenessCount++;
        if (_lowLivenessCount >= _lowLivenessNeeded && !_modelLivenessFailed) {
          debugPrint('[RecognitionScreen] ⚠️ SPOOF detected after $_lowLivenessCount consecutive low frames '
              '(tflite=${tfliteLive.toStringAsFixed(2)} '
              'passive=${passiveLive.toStringAsFixed(2)} '
              'fused=${fusedLive.toStringAsFixed(2)})');
          if (mounted) {
            setState(() {
              _modelLivenessFailed = true;
              _latestLivenessScore = fusedLive;
            });
          }
        }
      } else {
        _lowLivenessCount = 0; // reset on good frame
      }

      final emb = _faceRec.getEmbedding(cropped);
      final match = await _match(emb);

      final candidate = RecognitionCandidate(
        match: match,
        livenessScore: tfliteLive,
        passiveScore: passiveLive,        // ← NEW field
        faceQuality: faceQuality,
        cropped: cropped,
        embedding: emb,
        timestamp: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _candidates.add(candidate);
          if (_candidates.length > _maxCandidates) {
            _candidates.removeAt(0);
          }
          if (_bestCandidate == null ||
              candidate.compositeScore > _bestCandidate!.compositeScore) {
            _bestCandidate = candidate;
          }
          _dbgNonZero = emb.where((e) => e != 0).length;
          _latestLivenessScore = fusedLive;
          _dbgPassiveScore = passiveLive;     // ← NEW: for debug overlay
        });
      }

      debugPrint('[RecognitionScreen] 📸 Candidate #${_candidates.length}: '
          'match=${match?.name ?? "none"} '
          'tflite=${tfliteLive.toStringAsFixed(3)} '
          'passive=${passiveLive.toStringAsFixed(3)} '
          'fused=${fusedLive.toStringAsFixed(3)} '
          'quality=${faceQuality.toStringAsFixed(3)} '
          'composite=${candidate.compositeScore.toStringAsFixed(3)}');

    } catch (e, st) {
      debugPrint('[RecognitionScreen] _bgRecognitionWithQuality error: $e\n$st');
    }

    _bgRunning = false;
  }

  // ─── Finalize with Best Candidate ─────────────────────────────────────────
  Future<void> _finalizeWithBestCandidate(CameraImage currentFrame, Face currentFace) async {
    if (_finalizingRecognition || _navigated) return;

    setState(() {
      _finalizingRecognition = true;
    });

    debugPrint('[RecognitionScreen] 🎯 Finalizing - selecting best candidate...');

    // If we don't have a good candidate yet, capture one more with current frame
    if (_bestCandidate == null || _bestCandidate!.faceQuality < 0.5) {
      debugPrint('[RecognitionScreen] No good candidate yet, capturing final frame...');

      try {
        final cropped = _cropFace(currentFrame, currentFace);
        final live = _liveness.predict(cropped);
        final emb = _faceRec.getEmbedding(cropped);
        final match = await _match(emb);
        final faceQuality = _evaluateFaceQuality(currentFace);

        final finalCandidate = RecognitionCandidate(
          match: match,
          livenessScore: live,
          passiveScore: 0.85,   // ← ADD: fallback, no frame available at this point
          faceQuality: faceQuality,
          cropped: cropped,
          embedding: emb,
          timestamp: DateTime.now(),
        );

        _bestCandidate = finalCandidate;
        debugPrint('[RecognitionScreen] Final capture: quality=$faceQuality match=${match?.name}');
      } catch (e) {
        debugPrint('[RecognitionScreen] Final capture error: $e');
      }
    }

    // Navigate with the best candidate
    await _navigateWithCandidate(_bestCandidate);
  }

  // ─── Navigate with Candidate ──────────────────────────────────────────────
  Future<void> _navigateWithCandidate(RecognitionCandidate? candidate) async {
    if (_navigated) return;
    _navigated = true;

    debugPrint('[RecognitionScreen] 🚀 Navigating with candidate: '
        'match=${candidate?.match?.name ?? "Unknown"} '
        'score=${candidate?.match?.score.toStringAsFixed(3) ?? "0"} '
        'quality=${candidate?.faceQuality.toStringAsFixed(3)} '
        'live=${candidate?.livenessScore.toStringAsFixed(3)}');

    try {
      await _cam?.stopImageStream();
    } catch (_) {}

    final alreadyMarked = await _recordAttempt(candidate);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          enrolledImage: candidate?.match?.croppedImage ?? _grey(),
          currentImage: candidate?.croppedFace ?? _grey(),
          name: candidate?.match?.name ?? 'Unknown',
          similarity: candidate?.match?.score ?? 0.0,
          liveness: candidate?.fusedLiveness ?? 0.85,
          alreadyMarked: alreadyMarked,
        ),
      ),
    );

    _reset();
  }

  /// Persists the outcome. Returns true when the person had already been
  /// marked present inside the cooldown window (no new row written).
  Future<bool> _recordAttempt(RecognitionCandidate? c) async {
    try {
      final m = c?.match;
      if (m != null) {
        final r = await AttendanceRepository.recordPresent(
          faceId: m.faceId,
          name: m.name,
          similarity: m.score,
          liveness: c!.fusedLiveness,
        );
        return !r.newlyRecorded;
      }
      if (SettingsService.logFailedAttempts) {
        await AttendanceRepository.record(AttendanceLog(
          name: 'Unknown',
          timestamp: DateTime.now(),
          similarity: 0,
          liveness: c?.fusedLiveness ?? 0,
          status: AttendanceStatus.unknown,
        ));
      }
    } catch (e) {
      debugPrint('[RecognitionScreen] could not record attendance: $e');
    }
    return false;
  }

  Future<void> _recordSpoof() async {
    if (!SettingsService.logFailedAttempts) return;
    try {
      await AttendanceRepository.record(AttendanceLog(
        name: 'Unknown',
        timestamp: DateTime.now(),
        similarity: 0,
        liveness: _latestLivenessScore,
        status: AttendanceStatus.spoof,
      ));
    } catch (e) {
      debugPrint('[RecognitionScreen] could not record spoof: $e');
    }
  }

  void _showSpoofRejectionDialog() {
    if (_navigated) return;
    _navigated = true;
    _recordSpoof();

    debugPrint('[RecognitionScreen] _showSpoofRejectionDialog()');

    _cam?.stopImageStream();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12121C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B3B)),
            SizedBox(width: 10),
            Text('Spoof Detected', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Our system detected a potential spoofing attempt.\n\n'
                  'Please use your real face and ensure good lighting.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B3B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFF3B3B), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Liveness score: ${(_latestLivenessScore * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Color(0xFFFF3B3B), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _reset();
            },
            child: const Text('Try Again', style: TextStyle(color: Color(0xFF3DFFA2))),
          ),
        ],
      ),
    );
  }

  // ─── Liveness step logic ──────────────────────────────────────────────────
  void _doStep(Face face) {
    if (_awaitNeutral) {
      if (_isNeutral(_steps[_stepIdx], face)) {
        _neutralCount++;
        if (_neutralCount >= _neutralNeeded) {
          _awaitNeutral = false;
          _neutralCount = 0;
          _gestureCount = 0;
          debugPrint('[RecognitionScreen] neutral confirmed for step $_stepIdx');
        }
      } else {
        _neutralCount = 0;
      }
      return;
    }

    if (_gesture(_steps[_stepIdx], face)) {
      _gestureCount++;
      debugPrint('[RecognitionScreen] step ${_stepIdx + 1} gesture '
          '${'▓' * _gestureCount}/$_gestureNeeded');

      if (_gestureCount >= _gestureNeeded) {
        if (mounted) {
          setState(() {
            _stepDone[_stepIdx] = true;
            _stepIdx++;
            _sawEyesOpen = false;
            _gestureCount = 0;
            _awaitNeutral = _stepIdx < _steps.length;
            _neutralCount = 0;
          });
        }
        HapticFeedback.lightImpact();
      }
    } else {
      if (_gestureCount > 0) _gestureCount--;
    }
  }

  bool _gesture(LivenessStep step, Face face) {
    switch (step) {
      case LivenessStep.blink:
        final l = face.leftEyeOpenProbability;
        final r = face.rightEyeOpenProbability;
        if (l == null || r == null) return false;
        final avg = (l + r) / 2;
        if (avg > 0.60) _sawEyesOpen = true;
        return _sawEyesOpen && avg < 0.50;
      case LivenessStep.smile:
        final s = face.smilingProbability;
        if (s == null) return false;
        return s > 0.55;
      case LivenessStep.turnLeft:
        final y = face.headEulerAngleY;
        if (y == null) return false;
        return y < -15;
      case LivenessStep.turnRight:
        final y = face.headEulerAngleY;
        if (y == null) return false;
        return y > 15;
    }
  }

  bool _isNeutral(LivenessStep step, Face face) {
    switch (step) {
      case LivenessStep.blink:
        final l = face.leftEyeOpenProbability;
        final r = face.rightEyeOpenProbability;
        if (l == null || r == null) return false;
        return l > 0.65 && r > 0.65;
      case LivenessStep.smile:
        final s = face.smilingProbability;
        if (s == null) return false;
        return s < 0.35;
      case LivenessStep.turnLeft:
      case LivenessStep.turnRight:
        final y = face.headEulerAngleY;
        if (y == null) return false;
        return y.abs() < 8;
    }
  }

  // ML Kit boxes are in the *upright* frame, so use upright dimensions.
  bool _isUpright90(CameraImage f) => _sensorDeg == 90 || _sensorDeg == 270;
  int _uprightW(CameraImage f) => _isUpright90(f) ? f.height : f.width;
  int _uprightH(CameraImage f) => _isUpright90(f) ? f.width : f.height;

  bool _isAligned(Face face, int imgW, int imgH) {
    final box = face.boundingBox;
    final cx = box.center.dx / imgW;
    final cy = box.center.dy / imgH;
    final fw = box.width / imgW;
    final fh = box.height / imgH;
    return cx > 0.1 && cx < 0.9 &&
        cy > 0.05 && cy < 0.95 &&
        fw > 0.12 && fh > 0.10;
  }

  // ─── Face matching ────────────────────────────────────────────────────────
  Future<MatchResult?> _match(List<double> emb) async {
    final nonZero = emb.where((e) => e != 0.0).length;
    if (nonZero < 10) return null;

    if (_cachedFaces.isEmpty) return null;

    String bestName = 'Unknown';
    double bestScore = 0;
    Uint8List? bestImg;
    int? bestId;

    for (final row in _cachedFaces) {
      final saved = row.embedding; // cached parse
      if (saved.length != emb.length) continue;

      final score = _faceRec.cosineSimilarity(emb, saved);
      if (score > bestScore) {
        bestScore = score;
        bestName = row.name;
        bestImg = row.imageBytes;
        bestId = row.id;
      }
    }

    if (bestScore > SettingsService.matchThreshold && bestImg != null) {
      return MatchResult(bestName, bestScore, bestImg, faceId: bestId);
    }
    return null;
  }

  // ─── Image pipeline ───────────────────────────────────────────────────────
  /// NV21 arrives as ONE plane, so no copy is needed; only multi-plane
  /// formats are concatenated.
  Uint8List _frameBytes(CameraImage frame) {
    if (frame.planes.length == 1) return frame.planes.first.bytes;
    final wb = WriteBuffer();
    for (final p in frame.planes) {
      wb.putUint8List(p.bytes);
    }
    return wb.done().buffer.asUint8List();
  }

  InputImage _toInputImage(CameraImage frame, Uint8List bytes) {
    final rotation = InputImageRotationValue.fromRawValue(_sensorDeg) ??
        InputImageRotation.rotation90deg;
    final format = InputImageFormatValue.fromRawValue(frame.format.raw) ??
        InputImageFormat.nv21;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
  }

  /// Converts ONLY the sensor-space rectangle [x0,x1)×[y0,y1) to RGB.
  /// (The old code converted the whole 1080p frame in a Dart loop for every
  /// candidate, which froze the UI isolate for hundreds of ms.)
  img.Image _yuvRegionToRgb(CameraImage frame, int x0, int y0, int x1, int y1) {
    final out = img.Image(x1 - x0, y1 - y0);

    void put(int col, int row, int yv, int uv, int vv) {
      out.setPixelRgba(
        col - x0,
        row - y0,
        (yv + 1.402 * vv).round().clamp(0, 255),
        (yv - 0.344136 * uv - 0.714136 * vv).round().clamp(0, 255),
        (yv + 1.772 * uv).round().clamp(0, 255),
        255,
      );
    }

    if (frame.planes.length >= 3) {
      final yBuf = frame.planes[0].bytes;
      final uBuf = frame.planes[1].bytes;
      final vBuf = frame.planes[2].bytes;
      final yStride = frame.planes[0].bytesPerRow;
      final uvStride = frame.planes[1].bytesPerRow;
      final uvPixelStride = frame.planes[1].bytesPerPixel ?? 1;

      for (int row = y0; row < y1; row++) {
        for (int col = x0; col < x1; col++) {
          final yi = row * yStride + col;
          final uvi = (row ~/ 2) * uvStride + (col ~/ 2) * uvPixelStride;
          if (yi >= yBuf.length || uvi >= uBuf.length || uvi >= vBuf.length) continue;
          put(col, row, yBuf[yi] & 0xFF, (uBuf[uvi] & 0xFF) - 128, (vBuf[uvi] & 0xFF) - 128);
        }
      }
    } else {
      final buf = frame.planes[0].bytes;
      final yStride = frame.planes[0].bytesPerRow;
      final uvOffset = frame.height * yStride;
      final bool isNV21 = (frame.format.raw == 17);

      for (int row = y0; row < y1; row++) {
        for (int col = x0; col < x1; col++) {
          final yi = row * yStride + col;
          final uvBase = uvOffset + (row ~/ 2) * yStride + (col & ~1);
          if (yi >= buf.length || uvBase + 1 >= buf.length) continue;
          final uRaw = isNV21 ? buf[uvBase + 1] : buf[uvBase];
          final vRaw = isNV21 ? buf[uvBase] : buf[uvBase + 1];
          put(col, row, buf[yi] & 0xFF, (uRaw & 0xFF) - 128, (vRaw & 0xFF) - 128);
        }
      }
    }
    return out;
  }

  /// Crops the (padded) face box. The box is in the upright frame, so it is
  /// mapped back to sensor space, converted, then rotated/mirrored upright.
  img.Image _cropFace(CameraImage frame, Face face) {
    final w = frame.width;
    final h = frame.height;
    final uw = _uprightW(frame);
    final uh = _uprightH(frame);
    final box = face.boundingBox;

    final padX = (box.width * 0.25).toInt();
    final padY = (box.height * 0.25).toInt();

    int u0 = (box.left.toInt() - padX).clamp(0, uw - 1);
    int v0 = (box.top.toInt() - padY).clamp(0, uh - 1);
    int u1 = (box.right.toInt() + padX).clamp(u0 + 1, uw);
    int v1 = (box.bottom.toInt() + padY).clamp(v0 + 1, uh);

    if (u1 - u0 < 10 || v1 - v0 < 10) {
      final sq = min(uw, uh);
      u0 = (uw - sq) ~/ 2;
      v0 = (uh - sq) ~/ 2;
      u1 = u0 + sq;
      v1 = v0 + sq;
    }

    int sx0, sy0, sx1, sy1;
    switch (_sensorDeg) {
      case 90:
        sx0 = v0; sx1 = v1; sy0 = h - u1; sy1 = h - u0;
        break;
      case 270:
        sx0 = w - v1; sx1 = w - v0; sy0 = u0; sy1 = u1;
        break;
      case 180:
        sx0 = w - u1; sx1 = w - u0; sy0 = h - v1; sy1 = h - v0;
        break;
      default:
        sx0 = u0; sx1 = u1; sy0 = v0; sy1 = v1;
    }
    sx0 = sx0.clamp(0, w - 1);
    sy0 = sy0.clamp(0, h - 1);
    sx1 = sx1.clamp(sx0 + 1, w);
    sy1 = sy1.clamp(sy0 + 1, h);

    var region = _yuvRegionToRgb(frame, sx0, sy0, sx1, sy1);
    if (_sensorDeg == 90 || _sensorDeg == 180 || _sensorDeg == 270) {
      region = img.copyRotate(region, _sensorDeg);
    }
    return _isFront ? img.flipHorizontal(region) : region;
  }

  Uint8List _grey() {
    final ph = img.Image(120, 120);
    img.fill(ph, img.getColor(40, 40, 50));
    return Uint8List.fromList(img.encodeJpg(ph));
  }

  void _reset() {
    debugPrint('[RecognitionScreen] _reset()');
    if (!mounted) return;
    setState(() {
      _livenessComplete = false;
      _navigated = false;
      _facePresent = false;
      _faceAligned = false;
      _stepIdx = 0;
      _sawEyesOpen = false;
      _stepDone = [false, false, false, false];
      _gestureCount = 0;
      _awaitNeutral = false;
      _neutralCount = 0;
      _bgRunning = false;
      _bgSkip = 0;
      _dbgNonZero = 0;
      _dbgMsg = 'reset';
      _modelLivenessFailed = false;
      _latestLivenessScore = 0.85;
      _lowLivenessCount = 0;
      _dbgPassiveScore = -1;
      _finalizingRecognition = false;
      _recognitionComplete = false;
      _candidates.clear();
      _bestCandidate = null;
    });
    _startStream();
  }

  @override
  void dispose() {
    _disposed = true;
    _cam?.dispose();
    _detector.close();
    _pulse.dispose();
    _loadingAnim.dispose();
    _passive.dispose();
    _liveness.dispose();
    _faceRec.dispose();
    super.dispose();
  }

  // ─── UI helpers ───────────────────────────────────────────────────────────
  String get _instruction {
    if (_finalizingRecognition) return 'Finalizing…';
    if (_stepIdx >= _steps.length) return 'Processing…';
    if (_awaitNeutral) {
      switch (_steps[_stepIdx]) {
        case LivenessStep.blink:
          return 'Open your eyes';
        case LivenessStep.smile:
          return 'Relax face';
        case LivenessStep.turnLeft:
        case LivenessStep.turnRight:
          return 'Face forward';
      }
    }
    switch (_steps[_stepIdx]) {
      case LivenessStep.blink:
        return 'Blink both eyes';
      case LivenessStep.smile:
        return 'Give a big smile';
      case LivenessStep.turnLeft:
        return 'Turn head right';
      case LivenessStep.turnRight:
        return 'Turn head left';
    }
  }

  IconData get _icon {
    if (_finalizingRecognition) return Icons.manage_search_rounded;
    if (_stepIdx >= _steps.length) return Icons.check_circle_rounded;
    switch (_steps[_stepIdx]) {
      case LivenessStep.blink:
        return Icons.visibility_off_outlined;
      case LivenessStep.smile:
        return Icons.sentiment_very_satisfied_outlined;
      case LivenessStep.turnLeft:
        return Icons.arrow_forward_rounded;
      case LivenessStep.turnRight:
        return Icons.arrow_back_rounded;
    }
  }

  Color get _ovalColor {
    if (!_facePresent) return Colors.white30;
    if (!_faceAligned) return Colors.orangeAccent;
    if (_finalizingRecognition) return const Color(0xFF5CC8FF);
    if (_stepIdx >= _steps.length) return const Color(0xFF22E58B);
    return const Color(0xFF3DFFA2);
  }

  String get _hint {
    if (!_facePresent) return 'Point camera at your face';
    if (!_faceAligned) return 'Move closer & center your face';
    if (_finalizingRecognition) return 'Almost done…';
    if (_stepIdx >= _steps.length) return 'Liveness complete ✓';
    if (_candidates.isNotEmpty) {
      return 'Face aligned ✓ (${_candidates.length} captures)';
    }
    return 'Face aligned ✓';
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  Widget _cameraFill() {
    final size = _cam!.value.previewSize!;
    // previewSize is reported in landscape; swap for portrait fill.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(_cam!),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _cam == null || !_cam!.value.isInitialized) {
      return Scaffold(
        body: AuroraBackground(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RingGauge(
                  value: 0.35,
                  color: AppColors.accent,
                  label: 'loading',
                  size: 84),
              const SizedBox(height: 18),
              const Text('Loading on-device models…',
                  style: TextStyle(color: AppColors.textDim, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Nothing leaves your phone',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            ]),
          ),
        ),
      );
    }

    final scanning = _faceAligned && !_finalizingRecognition && _stepIdx < _steps.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(fit: StackFit.expand, children: [
        _cameraFill(),
        RepaintBoundary(
          child: ScannerOverlay(color: _ovalColor, sweep: _loadingAnim, scanning: scanning),
        ),

        // ── Top bar ─────────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              _roundBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
              const Spacer(),
              GestureDetector(
                onLongPress: () => setState(() => _dbg = !_dbg),
                child: GlassCard(
                  blur: false,
                  gradient: _panelGradient,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  radius: 20,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.shield_rounded, size: 15, color: _ovalColor),
                    const SizedBox(width: 6),
                    Text(_hint,
                        style: TextStyle(
                            color: _ovalColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              const Spacer(),
              const SizedBox(width: 44),
            ]),
          ),
        ),

        // ── Debug overlay (long-press the hint pill) ─────────────────────
        if (_dbg)
          Positioned(
            top: 100,
            left: 12,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dt('L=${_dbgL.toStringAsFixed(2)} R=${_dbgR.toStringAsFixed(2)}'),
                  _dt('Smile=${_dbgS.toStringAsFixed(2)} Y=${_dbgY.toStringAsFixed(1)}°'),
                  _dt('Step=$_stepIdx G=$_gestureCount'),
                  _dt('Candidates=${_candidates.length}'),
                  _dt('Best: ${_bestCandidate?.match?.name ?? "none"}'),
                  _dt('Quality: ${_bestCandidate?.faceQuality.toStringAsFixed(3) ?? "0"}'),
                  _dt('Passive: ${_dbgPassiveScore.toStringAsFixed(2)}'),
                  _dt(_dbgMsg),
                ],
              ),
            ),
          ),

        // ── Bottom glass panel ───────────────────────────────────────────
        Positioned(
          left: 14,
          right: 14,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                blur: false,
                gradient: _panelGradient,
                radius: 28,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _stepChips(),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: _finalizingRecognition
                        ? _finalizingCard()
                        : _stepIdx >= _steps.length
                        ? _doneCard()
                        : _challengeCard(key: ValueKey('$_stepIdx$_awaitNeutral')),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _stepIdx / _steps.length),
                      duration: const Duration(milliseconds: 350),
                      builder: (_, v, __) => LinearProgressIndicator(
                        value: v,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                        minHeight: 5,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  static const _panelGradient = LinearGradient(
    colors: [Color(0xE6101827), Color(0xE60B1224)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  Widget _roundBtn(IconData icon, VoidCallback onTap) => GlassCard(
    blur: false,
    gradient: _panelGradient,
    onTap: onTap,
    radius: 22,
    padding: const EdgeInsets.all(10),
    child: Icon(icon, size: 20),
  );

  static const _stepIcons = <LivenessStep, IconData>{
    LivenessStep.blink: Icons.remove_red_eye_outlined,
    LivenessStep.smile: Icons.sentiment_satisfied_alt_rounded,
    LivenessStep.turnLeft: Icons.turn_right_rounded,
    LivenessStep.turnRight: Icons.turn_left_rounded,
  };

  Widget _stepChips() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: List.generate(_steps.length, (i) {
      final done = _stepDone[i];
      final active = i == _stepIdx && !_livenessComplete;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: active ? 62 : 52,
        height: 44,
        decoration: BoxDecoration(
          gradient: done ? AppColors.brandGradient : null,
          color: done
              ? null
              : active
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? AppColors.accent : Colors.white12,
              width: active ? 1.6 : 1),
        ),
        child: Icon(
          done ? Icons.check_rounded : _stepIcons[_steps[i]],
          size: 22,
          color: done
              ? Colors.black
              : active
              ? Colors.white
              : Colors.white38,
        ),
      );
    }),
  );

  Widget _challengeCard({Key? key}) {
    final pct = _faceAligned ? (_gestureCount / _gestureNeeded).clamp(0.0, 1.0) : 0.0;
    return Column(key: key, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Transform.scale(
            scale: _faceAligned ? 1.0 + _pulse.value * 0.08 : 1.0,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: _faceAligned ? 0.16 : 0.05),
                border: Border.all(
                    color: _faceAligned ? AppColors.accent : Colors.white24, width: 1.8),
              ),
              child: Icon(_icon,
                  color: _faceAligned ? AppColors.accent : Colors.white38, size: 26),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_instruction,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              _faceAligned
                  ? (_awaitNeutral ? 'Return to neutral…' : 'Perform the gesture')
                  : 'Align your face inside the frame',
              style: TextStyle(
                  color: _faceAligned ? AppColors.textFaint : AppColors.warning,
                  fontSize: 12.5),
            ),
          ]),
        ),
        Text('${_stepIdx + 1}/${_steps.length}',
            style: const TextStyle(
                color: AppColors.textFaint, fontWeight: FontWeight.w700)),
      ]),
      if (pct > 0) ...[
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent2),
            minHeight: 3,
          ),
        ),
      ],
    ]);
  }

  Widget _doneCard() => Row(
    key: const ValueKey('done'),
    children: [
      const Icon(Icons.verified_rounded, color: AppColors.success, size: 44),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Liveness verified',
              style: TextStyle(
                  color: AppColors.success, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('Selecting the best capture…',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        ]),
      ),
    ],
  );

  Widget _finalizingCard() => Row(
    key: const ValueKey('finalizing'),
    children: [
      const SizedBox(
        width: 44,
        height: 44,
        child: CircularProgressIndicator(strokeWidth: 3.5, color: AppColors.info),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Matching…',
              style: TextStyle(
                  color: AppColors.info, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('Best of ${_candidates.length} captures',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
        ]),
      ),
    ],
  );

  Widget _dt(String t) => Text(t,
      style: const TextStyle(
          color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'));
}