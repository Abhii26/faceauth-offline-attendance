import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'services/database_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'core/app_config.dart';
import 'widgets/ui.dart';
import 'services/face_recognition_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {

  static const _tag = '[RegScreen]';

  late ImagePicker _picker;
  File? _imageFile;

  late FaceDetector _detector;
  late FaceRecognitionService _faceRec;
  bool _modelReady = false;

  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    debugPrint('$_tag initState()');
    _picker = ImagePicker();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    _faceRec = FaceRecognitionService();
    _faceRec.init().then((_) {
      debugPrint('$_tag face recognition model ready');
      if (mounted) setState(() => _modelReady = true);
    });
  }

  @override
  void dispose() {
    debugPrint('$_tag dispose()');
    _detector.close();
    _shimmer.dispose();
    _faceRec.dispose();
    super.dispose();
  }

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _fromCamera() async {
    debugPrint('$_tag _fromCamera()');
    final f = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (f != null) await _process(File(f.path));
  }

  Future<void> _fromGallery() async {
    debugPrint('$_tag _fromGallery()');
    final f = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (f != null) await _process(File(f.path));
  }

  /// Crop the face with the same 30% padding used in recognition
  img.Image _cropFaceLikeRecognition(img.Image src, Face face) {
    final box = face.boundingBox;

    final padX = (box.width * 0.30).toInt();
    final padY = (box.height * 0.30).toInt();

    int x = max(0, box.left.toInt() - padX);
    int y = max(0, box.top.toInt() - padY);
    int w = box.width.toInt() + padX * 2;
    int h = box.height.toInt() + padY * 2;

    x = x.clamp(0, src.width - 1);
    y = y.clamp(0, src.height - 1);
    w = min(w, src.width - x);
    h = min(h, src.height - y);

    if (w < 20 || h < 20) {
      debugPrint('$_tag cropLikeRec: invalid box → centre fallback');
      final s = min(src.width, src.height);
      x = (src.width - s) ~/ 2;
      y = (src.height - s) ~/ 2;
      w = s;
      h = s;
    }

    debugPrint('$_tag cropLikeRec: x=$x y=$y w=$w h=$h');
    return img.copyCrop(src, x, y, w, h);
  }

  Future<void> _process(File file) async {
    debugPrint('$_tag _process() path=${file.path}');
    final bytes = await file.readAsBytes();
    final raw = img.decodeImage(bytes);
    if (raw == null) {
      debugPrint('$_tag ❌ decodeImage failed');
      return;
    }
    debugPrint('$_tag decoded: ${raw.width}x${raw.height}');

    // Fix EXIF orientation
    final oriented = img.bakeOrientation(raw);
    final fixedFile =
    await file.writeAsBytes(img.encodeJpg(oriented));

    setState(() => _imageFile = fixedFile);
    await _detectAndShow(fixedFile, oriented);
  }

  Future<void> _detectAndShow(
      File file, img.Image oriented) async {
    debugPrint(
        '$_tag _detectAndShow()  modelReady=$_modelReady');

    if (!_modelReady) {
      _snack('Model loading, please wait…');
      return;
    }

    debugPrint('$_tag running face detection…');
    final faces =
    await _detector.processImage(InputImage.fromFile(file));
    debugPrint('$_tag detected ${faces.length} face(s)');

    if (faces.isEmpty) {
      _noFaceDialog();
      return;
    }

    final box = faces.first.boundingBox;
    debugPrint('$_tag bounding box: L=${box.left.toInt()} '
        'T=${box.top.toInt()} '
        'W=${box.width.toInt()} H=${box.height.toInt()}');

    final cropped =
    _cropFaceLikeRecognition(oriented, faces.first);
    debugPrint(
        '$_tag cropped: ${cropped.width}x${cropped.height}');

    if (mounted) _showSheet(cropped);
  }

  /// Returns an existing record whose embedding is almost certainly the
  /// same person, or null.
  Future<FaceRecord?> _findDuplicate(List<double> emb) async {
    final existing = await DatabaseService.getFaces();
    FaceRecord? best;
    double bestScore = 0;
    for (final r in existing) {
      final score = _faceRec.cosineSimilarity(emb, r.embedding);
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    return bestScore >= AppConfig.duplicateFaceThreshold ? best : null;
  }

  void _noFaceDialog() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF12121C),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded,
            color: Colors.orangeAccent),
        SizedBox(width: 10),
        Text('No face found',
            style: TextStyle(
                color: Colors.white, fontSize: 18)),
      ]),
      content: const Text(
        'No face detected. Please use a clear, well-lit photo.',
        style:
        TextStyle(color: Colors.white60, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK',
              style:
              TextStyle(color: Color(0xFF3DFFA2))),
        ),
      ],
    ),
  );

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  // ── Register sheet ─────────────────────────────────────────────────────────
  // Only passes cropped face; original is not stored.

  void _showSheet(img.Image cropped) {
    debugPrint('$_tag _showSheet()');
    final ctrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF12121C),
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(32)),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius:
                          BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  const Text('Register Face',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Your face will be saved securely',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13)),
                  const SizedBox(height: 20),

                  // Preview of cropped face
                  Container(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF3DFFA2)
                                  .withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2)
                        ]),
                    child: ClipOval(
                      child: Image.memory(
                          Uint8List.fromList(
                              img.encodeJpg(cropped)),
                          width: 130,
                          height: 130,
                          fit: BoxFit.cover),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      textCapitalization:
                      TextCapitalization.words,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Enter full name',
                        hintStyle: const TextStyle(
                            color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF1E1E30),
                        prefixIcon: const Icon(
                            Icons.person_outline,
                            color: Colors.white38),
                        border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(16),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(16),
                            borderSide: const BorderSide(
                                color: Color(0xFF3DFFA2),
                                width: 1.5)),
                        contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF3DFFA2),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(16))),
                        onPressed: saving
                            ? null
                            : () async {
                          final name =
                          ctrl.text.trim();
                          if (name.length < 2) {
                            _snack('Please enter a valid name (min 2 characters)');
                            return;
                          }
                          debugPrint(
                              '$_tag saving face for "$name"');
                          setSheet(() => saving = true);

                          try {
                            debugPrint(
                                '$_tag computing embedding…');
                            final emb = _faceRec
                                .getEmbedding(cropped);
                            final nz = emb
                                .where((e) => e != 0)
                                .length;
                            debugPrint('$_tag embedding: '
                                'len=${emb.length}  '
                                'nonZero=$nz  '
                                'first3=${emb.take(3).map((e) => e.toStringAsFixed(4)).join(',')}');

                            if (nz == 0) {
                              debugPrint(
                                  '$_tag ❌ embedding all zeros');
                              _snack(
                                  'Model error — could not generate face embedding');
                              setSheet(
                                      () => saving = false);
                              return;
                            }

                            // Reject duplicate enrolments of the same face
                            final dup = await _findDuplicate(emb);
                            if (dup != null) {
                              _snack('This face is already registered as "${dup.name}"');
                              setSheet(() => saving = false);
                              return;
                            }

                            // Only save cropped image
                            final cropBytes =
                            Uint8List.fromList(
                                img.encodeJpg(
                                    cropped,
                                    quality: 85));

                            debugPrint(
                                '$_tag inserting into DB…');
                            final id =
                            await DatabaseService
                                .insertFace(
                              name,
                              emb,
                              cropBytes,
                              // originalImage intentionally omitted
                            );
                            debugPrint(
                                '$_tag ✅ saved id=$id');

                            if (!mounted) return;
                            Navigator.pop(ctx);
                            _success(name);
                          } catch (e, st) {
                            debugPrint(
                                '$_tag ❌ save error: $e\n$st');
                            setSheet(
                                    () => saving = false);
                            _snack('Save failed: $e');
                          }
                        },
                        child: saving
                            ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.black))
                            : const Row(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded,
                                  size: 20),
                              SizedBox(width: 8),
                              Text('Save Face',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                      FontWeight.bold)),
                            ]),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 14))),

                  const SizedBox(height: 14),
                ]),
          ),
        ),
      ),
    );
  }

  void _success(String name) {
    debugPrint('$_tag _success("$name")');
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => _SuccessDialog(name: name),
    ).then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060A14),
      body: AuroraBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              child: Row(children: [
                IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context)),
                const Expanded(
                  child: Text('Register Face',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 44),
              ]),
            ),

            if (!_modelReady)
              const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(
                      Color(0xFF3DFFA2)),
                  minHeight: 2),

            const SizedBox(height: 8),

            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: _imageFile != null
                              ? const Color(0xFF3DFFA2)
                              .withValues(alpha: 0.5)
                              : Colors.white
                              .withValues(alpha: 0.07),
                          width: 1.5),
                      color: const Color(0xFF12121C)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: _imageFile != null
                        ? Image.file(_imageFile!,
                        fit: BoxFit.cover,
                        width: double.infinity)
                        : _placeholder(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              _imageFile == null
                  ? 'Take or upload a clear photo of your face'
                  : 'Face detected — tap a button to retake',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _imageFile == null
                      ? Colors.white38
                      : Colors.white54,
                  fontSize: 13),
            ),

            const SizedBox(height: 20),

            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                    child: _Btn(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: _fromGallery,
                        secondary: _imageFile != null)),
                const SizedBox(width: 14),
                Expanded(
                    child: _Btn(
                        icon: Icons.camera_alt_outlined,
                        label: 'Camera',
                        onTap: _fromCamera)),
              ]),
            ),

            const SizedBox(height: 28),
          ]),
        ),
      ),
    );
  }

  Widget _placeholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
              Colors.white.withValues(alpha: 0.04),
              border:
              Border.all(color: Colors.white10)),
          child: const Icon(Icons.face_outlined,
              color: Colors.white24, size: 36)),
      const SizedBox(height: 14),
      const Text('No photo selected',
          style: TextStyle(
              color: Colors.white24, fontSize: 15)),
      const SizedBox(height: 4),
      const Text('Use buttons below',
          style: TextStyle(
              color: Colors.white12, fontSize: 12)),
    ],
  );
}

// ── Picker button ──────────────────────────────────────────────────────────────
class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool secondary;

  const _Btn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      decoration: BoxDecoration(
          gradient: secondary
              ? null
              : const LinearGradient(colors: [
            Color(0xFF3DFFA2),
            Color(0xFF00C853)
          ]),
          color: secondary
              ? const Color(0xFF1E1E30)
              : null,
          borderRadius: BorderRadius.circular(16),
          border: secondary
              ? Border.all(color: Colors.white12)
              : null),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: secondary
                    ? Colors.white54
                    : Colors.black,
                size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: secondary
                        ? Colors.white54
                        : Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ]),
    ),
  );
}

// ── Success dialog ─────────────────────────────────────────────────────────────
class _SuccessDialog extends StatefulWidget {
  final String name;

  const _SuccessDialog({required this.name});

  @override
  State<_SuccessDialog> createState() =>
      _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale, _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650));
    _scale =
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: 40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: const Color(0xFF12121C),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: const Color(0xFF3DFFA2)
                      .withValues(alpha: 0.5),
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF3DFFA2)
                        .withValues(alpha: 0.12),
                    blurRadius: 40,
                    spreadRadius: 4)
              ]),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0D1F15),
                        border: Border.all(
                            color: const Color(0xFF3DFFA2),
                            width: 2.5)),
                    child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF3DFFA2),
                        size: 50)),
                const SizedBox(height: 18),
                const Text('Registered!',
                    style: TextStyle(
                        color: Color(0xFF3DFFA2),
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                            height: 1.5),
                        children: [
                          TextSpan(
                              text: widget.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16)),
                          const TextSpan(
                              text: '\nadded successfully'),
                        ])),
                const SizedBox(height: 18),
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        color: const Color(0xFF3DFFA2)
                            .withValues(alpha: 0.1),
                        borderRadius:
                        BorderRadius.circular(20)),
                    child: const Text(
                        'Returning to home…',
                        style: TextStyle(
                            color: Color(0xFF3DFFA2),
                            fontSize: 12,
                            fontWeight:
                            FontWeight.w500))),
              ]),
        ),
      ),
    ),
  );
}