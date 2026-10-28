import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// DiagnosticScreen
/// ─────────────────
/// Paste this into your project, then open it from HomeScreen:
///
///   _AppButton(
///     label: 'Diagnose',
///     icon: Icons.bug_report,
///     onPressed: () => Navigator.push(context,
///         MaterialPageRoute(builder: (_) => const DiagnosticScreen())),
///   ),
///
/// Read every ✅ / ❌ carefully. The first ❌ tells you what to fix.
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});
  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  final List<_LogEntry> _logs = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _log(String msg, {bool ok = true, bool isHeader = false}) {
    debugPrint('[DIAG] $msg');
    if (mounted) setState(() => _logs.add(_LogEntry(msg, ok: ok, isHeader: isHeader)));
  }

  Future<void> _run() async {
    setState(() { _running = true; _logs.clear(); });

    _log('═══ 1. MODEL FILES ═══', isHeader: true);
    await _checkModels();

    _log('═══ 2. LOAD BEST MODEL ═══', isHeader: true);
    final interp = await _loadBestModel();

    _log('═══ 3. INFERENCE TEST ═══', isHeader: true);
    if (interp != null) await _testInference(interp);

    _log('═══ 4. DATABASE ═══', isHeader: true);
    await _checkDatabase();

    _log('═══ 5. IMAGE FILES ═══', isHeader: true);
    await _checkImageFiles();

    _log('═══ 6. EMBEDDING CROSS-CHECK ═══', isHeader: true);
    if (interp != null) await _crossCheck(interp);

    interp?.close();
    setState(() => _running = false);
    _log('═══ COMPLETE ═══', isHeader: true);
  }

  // ── 1. Check which model files exist ──────────────────────────────────────

  Future<void> _checkModels() async {
    const candidates = [
      'assets/models/face_recognition.tflite',
      'assets/models/face_model_float32.tflite',
      'assets/models/mobilefacenet.tflite',
      'assets/models/liveness.tflite',
    ];
    for (final name in candidates) {
      try {
        final it = await Interpreter.fromAsset(name,
            options: InterpreterOptions()..threads = 1);
        final ins  = it.getInputTensor(0).shape;
        final outs = it.getOutputTensor(0).shape;
        it.close();
        _log('✅  $name  in=$ins  out=$outs');
      } catch (e) {
        _log('❌  $name  →  NOT FOUND or FAILED\n    $e', ok: false);
      }
    }
  }

  // ── 2. Load best available model ──────────────────────────────────────────

  Future<Interpreter?> _loadBestModel() async {
    for (final name in [
      'assets/models/face_recognition.tflite',
      'assets/models/face_model_float32.tflite',
      'assets/models/mobilefacenet.tflite',
    ]) {
      try {
        final it = await Interpreter.fromAsset(name,
            options: InterpreterOptions()..threads = 2);
        _log('✅  Loaded: $name');
        _log('    input:  ${it.getInputTensor(0).shape}');
        _log('    output: ${it.getOutputTensor(0).shape}');
        return it;
      } catch (_) {}
    }
    _log('❌  No face recognition model loaded!', ok: false);
    _log('    → Check pubspec.yaml assets: section', ok: false);
    _log('    → Run: flutter clean && flutter pub get', ok: false);
    return null;
  }

  // ── 3. Run inference ───────────────────────────────────────────────────────

  Future<void> _testInference(Interpreter interp) async {
    try {
      final ins  = interp.getInputTensor(0).shape;
      final outs = interp.getOutputTensor(0).shape;
      final h = ins[1], w = ins[2], dim = outs.last;

      _log('Input [$h x $w x 3]  →  output [$dim]');

      // Build random [-1,1] input (MobileFaceNet normalization)
      final rng   = math.Random();
      final input = List.generate(1, (_) =>
          List.generate(h, (_) =>
              List.generate(w, (_) => [
                rng.nextDouble() * 2 - 1,
                rng.nextDouble() * 2 - 1,
                rng.nextDouble() * 2 - 1,
              ])));

      final output = [List<double>.filled(dim, 0.0)];
      interp.run(input, output);
      final raw = output[0];

      final nonZero = raw.where((e) => e != 0).length;
      final norm    = math.sqrt(raw.map((e) => e * e).reduce((a, b) => a + b));

      _log('nonZero: $nonZero / $dim', ok: nonZero > 10);
      _log('norm:    ${norm.toStringAsFixed(4)}', ok: norm > 0.1);
      _log('first5:  ${raw.take(5).map((e) => e.toStringAsFixed(4)).join(', ')}');

      if (nonZero == 0) {
        _log('❌  ALL ZEROS — model is corrupt or wrong file!', ok: false);
        _log('    → Re-export or re-download the model', ok: false);
      } else {
        _log('✅  Inference working');
      }
    } catch (e, st) {
      _log('❌  Inference error: $e', ok: false);
      debugPrint('[DIAG] $st');
    }
  }

  // ── 4. Check database ─────────────────────────────────────────────────────

  Future<void> _checkDatabase() async {
    final dbDir = await getDatabasesPath();
    _log('DB directory: $dbDir');

    final dir   = Directory(dbDir);
    final files = await dir.list().toList();
    final dbs   = files.where((f) => f.path.endsWith('.db')).toList();

    if (dbs.isEmpty) {
      _log('❌  No .db files found — never registered a face', ok: false);
      return;
    }

    for (final f in dbs) {
      final dbName = p.basename(f.path);
      _log('--- DB: $dbName ---', isHeader: true);
      try {
        final db = await openDatabase(f.path, readOnly: true);

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'");
        _log('Tables: ${tables.map((t) => t['name']).join(', ')}');

        if (!tables.any((t) => t['name'] == 'faces')) {
          _log('❌  No "faces" table!', ok: false);
          await db.close();
          continue;
        }

        // Column info
        final cols = await db.rawQuery('PRAGMA table_info(faces)');
        _log('Columns: ${cols.map((c) => c['name']).join(', ')}');

        final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM faces')) ?? 0;
        _log('Row count: $count', ok: count > 0);

        if (count == 0) {
          _log('❌  Table is empty — register a face first', ok: false);
          await db.close();
          continue;
        }

        // Inspect every row
        final rows = await db.query('faces');
        for (final row in rows) {
          final id     = row['id'];
          final name   = row['name'] as String? ?? '?';
          final embStr = row['embedding'] as String? ?? '';
          final parts  = embStr.isEmpty ? <String>[] : embStr.split(',');

          int nonZero = 0;
          bool parseOk = true;
          try {
            final emb = parts.map(double.parse).toList();
            nonZero = emb.where((e) => e != 0).length;
          } catch (e) {
            parseOk = false;
          }

          final embStatus = !parseOk
              ? '❌ PARSE ERROR'
              : nonZero == 0
              ? '❌ ALL ZEROS'
              : '✅ OK($nonZero/${parts.length})';

          _log('Row id=$id  name="$name"  emb=$embStatus',
              ok: parseOk && nonZero > 0);

          if (nonZero == 0 && parseOk) {
            _log('    → Face registered with broken model.', ok: false);
            _log('    → DELETE and re-register this face!', ok: false);
          }

          // Image path columns
          if (row.containsKey('image_path')) {
            final path    = row['image_path'] as String? ?? '';
            final exists  = path.isNotEmpty && await File(path).exists();
            _log('    image_path: exists=$exists  ${p.basename(path)}',
                ok: exists);
          }
          if (row.containsKey('original_image_path')) {
            final path   = row['original_image_path'] as String? ?? '';
            final exists = path.isNotEmpty && await File(path).exists();
            _log('    orig_path:  exists=$exists  ${p.basename(path)}',
                ok: exists);
          }
          if (row.containsKey('image')) {
            final blob = row['image'];
            final len  = blob is Uint8List ? blob.length : 0;
            _log('    image BLOB: $len bytes', ok: len > 100);
          }
          if (row.containsKey('original_image')) {
            final blob = row['original_image'];
            final len  = blob is Uint8List ? blob.length : 0;
            _log('    orig BLOB:  $len bytes', ok: len > 100);
          }
        }

        await db.close();
      } catch (e) {
        _log('❌  DB error: $e', ok: false);
      }
    }
  }

  // ── 5. Check image files ───────────────────────────────────────────────────

  Future<void> _checkImageFiles() async {
    try {
      final docs   = await getApplicationDocumentsDirectory();
      final imgDir = Directory(p.join(docs.path, 'face_images'));

      if (!await imgDir.exists()) {
        _log('❌  face_images/ directory missing', ok: false);
        _log('    → Faces were stored as BLOBs (old scheme)', ok: false);
        return;
      }

      final files = await imgDir.list().toList();
      _log('face_images/ has ${files.length} file(s)', ok: files.isNotEmpty);
      for (final f in files.take(8)) {
        final sz = await File(f.path).length();
        _log('  ${p.basename(f.path)}  ${(sz / 1024).toStringAsFixed(1)} KB',
            ok: sz > 500);
      }
    } catch (e) {
      _log('❌  Image file check error: $e', ok: false);
    }
  }

  // ── 6. Cross-check DB embeddings vs current model output ──────────────────

  Future<void> _crossCheck(Interpreter interp) async {
    try {
      final ins  = interp.getInputTensor(0).shape;
      final outs = interp.getOutputTensor(0).shape;
      final h = ins[1], w = ins[2], dim = outs.last;

      // Get a live embedding from a test image
      final testFace = img.Image(h, w);
      img.fill(testFace, img.getColor(150, 110, 90));
      final liveEmb = _getEmb(interp, testFace, h, w, dim);
      final liveNZ  = liveEmb.where((e) => e != 0).length;
      _log('Live embedding nonZero: $liveNZ / $dim', ok: liveNZ > 10);

      // Now load all DB rows and compare
      final dbDir = await getDatabasesPath();
      final dir   = Directory(dbDir);
      final files = await dir.list().toList();
      final dbs   = files.where((f) => f.path.endsWith('.db')).toList();

      bool foundAny = false;
      for (final f in dbs) {
        try {
          final db   = await openDatabase(f.path, readOnly: true);
          final rows = await db.query('faces');
          await db.close();
          if (rows.isEmpty) continue;

          foundAny = true;
          for (final row in rows) {
            final name   = row['name'] as String? ?? '?';
            final embStr = row['embedding'] as String? ?? '';
            if (embStr.isEmpty) { _log('"$name" has no embedding', ok: false); continue; }

            final parts = embStr.split(',');
            if (parts.length != dim) {
              _log('❌  "$name" emb length ${parts.length} ≠ model dim $dim', ok: false);
              _log('    → REGISTERED WITH DIFFERENT MODEL!', ok: false);
              _log('    → Delete and re-register', ok: false);
              continue;
            }

            final saved  = parts.map(double.parse).toList();
            final savedNZ = saved.where((e) => e != 0).length;
            if (savedNZ == 0) {
              _log('❌  "$name" saved embedding all zeros', ok: false);
              _log('    → Re-register this person', ok: false);
              continue;
            }

            // Cosine similarity
            double dot = 0;
            for (int i = 0; i < dim; i++) dot += liveEmb[i] * saved[i];
            _log('✅  "$name"  embNZ=$savedNZ  '
                'sim_vs_test=${dot.toStringAsFixed(4)}');
          }
        } catch (e) {
          _log('DB read error: $e', ok: false);
        }
      }

      if (!foundAny) {
        _log('❌  No face records found in any DB', ok: false);
        _log('    → Register a face first', ok: false);
      }
    } catch (e, st) {
      _log('❌  Cross-check error: $e', ok: false);
      debugPrint('[DIAG] $st');
    }
  }

  List<double> _getEmb(Interpreter interp, img.Image face, int h, int w, int dim) {
    final resized = img.copyResize(face, width: w, height: h);
    final input   = List.generate(1, (_) =>
        List.generate(h, (y) =>
            List.generate(w, (x) {
              final px = resized.getPixel(x, y);
              return [
                (img.getRed(px)   - 128.0) / 128.0,
                (img.getGreen(px) - 128.0) / 128.0,
                (img.getBlue(px)  - 128.0) / 128.0,
              ];
            })));
    final output  = [List<double>.filled(dim, 0.0)];
    interp.run(input, output);
    return output[0];
  }

  // ── Delete all ────────────────────────────────────────────────────────────

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12121C),
        title: const Text('Delete ALL faces?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Wipes ALL databases and image files.\nYou must re-register all faces.',
            style: TextStyle(color: Colors.white60, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE ALL',
                  style: TextStyle(color: Colors.redAccent,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (ok != true) return;

    // Wipe all known DBs
    final dbDir = await getDatabasesPath();
    for (final name in [
      'faces_app.db', 'faces_v2.db', 'faces_final.db', 'faces.db'
    ]) {
      final path = p.join(dbDir, name);
      if (await File(path).exists()) {
        await deleteDatabase(path);
        _log('Deleted DB: $name');
      }
    }

    // Wipe image files
    final docs   = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(docs.path, 'face_images'));
    if (await imgDir.exists()) {
      await imgDir.delete(recursive: true);
      _log('Deleted face_images/');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('All faces deleted. Re-register now.'),
          backgroundColor: Colors.orangeAccent));
      await _run();
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10101A),
        title: const Text('Diagnostic',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_running)
            IconButton(
                icon: const Icon(Icons.refresh, color: Colors.greenAccent),
                onPressed: _run),
        ],
      ),
      body: Column(children: [

        if (_running)
          const LinearProgressIndicator(
              backgroundColor: Color(0xFF1C1C28),
              valueColor: AlwaysStoppedAnimation(Color(0xFF3DFFA2))),

        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _logs.length,
          itemBuilder: (_, i) {
            final e = _logs[i];
            if (e.isHeader) {
              return Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 3),
                  child: Text(e.msg, style: const TextStyle(
                      color: Colors.white70, fontSize: 11,
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')));
            }
            return Text(e.msg, style: TextStyle(
                color: e.ok ? Colors.greenAccent : Colors.redAccent,
                fontSize: 10.5, fontFamily: 'monospace'));
          },
        )),

        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          color: const Color(0xFF10101A),
          child: Column(children: [
            const Text(
                'If you see ❌ ALL ZEROS → press Delete All then re-register',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: _running ? null : _deleteAll,
                    child: const Text('🗑️  Delete ALL faces & reset database'))),
          ]),
        ),
      ]),
    );
  }
}

class _LogEntry {
  final String msg;
  final bool   ok;
  final bool   isHeader;
  _LogEntry(this.msg, {this.ok = true, this.isHeader = false});
}