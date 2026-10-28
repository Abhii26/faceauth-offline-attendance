import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ────────────────────────────────────────────────────────────────────────────
// FaceRecord  — typed result from DB (only stores cropped face image)
// ────────────────────────────────────────────────────────────────────────────
class FaceRecord {
  final int id;
  final String name;
  final String embeddingStr; // raw "0.1,0.2,..." string
  final Uint8List imageBytes; // cropped face jpg (used everywhere)
  final DateTime? createdAt;

  FaceRecord({
    required this.id,
    required this.name,
    required this.embeddingStr,
    required this.imageBytes,
    this.createdAt,
  });

  List<double>? _embeddingCache;

  // Convenience getter: keep originalBytes pointing to same image
  Uint8List get originalBytes => imageBytes;

  /// Parsed embedding. Cached: matching runs on every camera frame and
  /// re-parsing a 192-value string each time is wasteful.
  List<double> get embedding => _embeddingCache ??= embeddingStr.isEmpty
      ? const <double>[]
      : embeddingStr
          .split(',')
          .map((e) => double.tryParse(e) ?? 0.0)
          .toList(growable: false);
}

// ────────────────────────────────────────────────────────────────────────────
// DatabaseService
// ────────────────────────────────────────────────────────────────────────────
class DatabaseService {
  static const _tag = '[DB]';
  static const _dbName = 'faces_v2.db'; // bumped name to force fresh schema
  static const _version = 2; // v2: created_at column + attendance_logs table

  static Database? _db;

  // ── Init ───────────────────────────────────────────────────────────────────

  static Future<Database> init() async {
    if (_db != null && _db!.isOpen) {
      debugPrint('$_tag already open ($_dbName)');
      return _db!;
    }

    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _dbName);
    debugPrint('$_tag opening database: $dbPath');

    _db = await openDatabase(
      dbPath,
      version: _version,
      onCreate: (db, v) async {
        debugPrint('$_tag onCreate v$v');
        await _createTable(db);
        await _createAttendanceTable(db);
      },
      onUpgrade: (db, oldV, newV) async {
        debugPrint('$_tag onUpgrade $oldV → $newV');
        if (oldV < 2) {
          await _createTable(db); // no-op if present
          final cols = await db.rawQuery('PRAGMA table_info(faces)');
          if (!cols.any((c) => c['name'] == 'created_at')) {
            await db.execute('ALTER TABLE faces ADD COLUMN created_at INTEGER');
          }
          await _createAttendanceTable(db);
        }
      },
      onOpen: (db) async {
        await _createTable(db);
        await _createAttendanceTable(db);
        final n = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM faces')) ??
            0;
        debugPrint('$_tag onOpen OK — $n registered face(s)');
        final cols =
        await db.rawQuery('PRAGMA table_info(faces)');
        debugPrint(
            '$_tag columns: ${cols.map((c) => c['name']).join(', ')}');
      },
    );

    return _db!;
  }

  static Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS faces (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        embedding   TEXT    NOT NULL,
        image_path  TEXT    NOT NULL,
        created_at  INTEGER
      )
    ''');
  }

  static Future<void> _createAttendanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance_logs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        face_id     INTEGER,
        name        TEXT    NOT NULL,
        timestamp   INTEGER NOT NULL,
        similarity  REAL    NOT NULL,
        liveness    REAL    NOT NULL,
        status      TEXT    NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attendance_ts ON attendance_logs(timestamp DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attendance_face ON attendance_logs(face_id, timestamp)');
  }

  // ── Image directory ────────────────────────────────────────────────────────

  static Future<Directory> _imageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'face_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('$_tag created image directory: ${dir.path}');
    }
    return dir;
  }

  static Future<String> _writeImage(
      Uint8List bytes, String filename) async {
    final dir = await _imageDir();
    final filePath = p.join(dir.path, filename);
    await File(filePath).writeAsBytes(bytes, flush: true);
    debugPrint('$_tag wrote image: $filePath  '
        '(${(bytes.length / 1024).toStringAsFixed(1)} KB)');
    return filePath;
  }

  // ── Insert ─────────────────────────────────────────────────────────────────
  /// Saves ONLY the cropped face image. Original image is intentionally
  /// not stored to save space and keep the DB simple.

  static Future<int> insertFace(
      String name,
      List<double> embedding,
      Uint8List croppedImage, {
        // originalImage parameter kept for API compatibility but ignored
        Uint8List? originalImage,
      }) async {
    debugPrint('$_tag insertFace() name="$name"  '
        'embLen=${embedding.length}  '
        'nonZero=${embedding.where((e) => e != 0).length}');

    final ts = DateTime.now().millisecondsSinceEpoch;
    final cropPath =
    await _writeImage(croppedImage, '${ts}_crop.jpg');

    final db = await init();
    final id = await db.insert('faces', {
      'name': name,
      'embedding': embedding.join(','),
      'image_path': cropPath,
      'created_at': ts,
    });

    debugPrint('$_tag insertFace() → id=$id  ✅');
    return id;
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  static Future<List<FaceRecord>> getFaces() async {
    debugPrint('$_tag getFaces()');
    try {
      final db = await init();
      final rows =
      await db.query('faces', orderBy: 'id DESC');
      debugPrint('$_tag query returned ${rows.length} row(s)');

      final out = <FaceRecord>[];

      for (final row in rows) {
        final id = row['id'] as int;
        final name = row['name'] as String;
        final embStr = row['embedding'] as String;
        final cropPath = row['image_path'] as String;

        Uint8List? cropBytes;
        try {
          final f = File(cropPath);
          if (await f.exists()) {
            cropBytes = await f.readAsBytes();
            debugPrint(
                '$_tag    ✅ cropFile ${cropBytes.length} bytes');
          } else {
            debugPrint(
                '$_tag    ⚠️  cropFile missing: $cropPath');
          }
        } catch (e) {
          debugPrint('$_tag    ❌ cropFile read error: $e');
        }

        if (cropBytes == null) {
          debugPrint(
              '$_tag    ⚠️  skipping id=$id — image unavailable');
          continue;
        }

        final createdMs = row['created_at'] as int?;
        out.add(FaceRecord(
          id: id,
          name: name,
          embeddingStr: embStr,
          imageBytes: cropBytes,
          createdAt: createdMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(createdMs),
        ));
      }

      debugPrint(
          '$_tag getFaces() → ${out.length} valid record(s)');
      return out;
    } catch (e, st) {
      debugPrint('$_tag getFaces() ERROR: $e\n$st');
      return [];
    }
  }

  static Future<int> countFaces() async {
    final db = await init();
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM faces')) ??
        0;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> deleteFace(int id) async {
    debugPrint('$_tag deleteFace(id=$id)');
    try {
      final db = await init();
      final rows = await db.query('faces',
          where: 'id = ?', whereArgs: [id], limit: 1);

      if (rows.isNotEmpty) {
        final path = rows.first['image_path'] as String?;
        if (path != null) {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            debugPrint('$_tag deleted file: $path');
          }
        }
      }

      final n =
      await db.delete('faces', where: 'id = ?', whereArgs: [id]);
      debugPrint('$_tag deleteFace() removed $n row(s)');
    } catch (e, st) {
      debugPrint('$_tag deleteFace() ERROR: $e\n$st');
    }
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static Future<void> forceReinit() async {
    debugPrint('$_tag forceReinit()');
    if (_db != null && _db!.isOpen) await _db!.close();
    _db = null;
    await init();
  }

  /// Debug only — wipe everything
  static Future<void> resetAll() async {
    debugPrint('$_tag ⚠️  resetAll()');
    if (_db != null && _db!.isOpen) await _db!.close();
    _db = null;
    final dbDir = await getDatabasesPath();
    await deleteDatabase(p.join(dbDir, _dbName));
    final imgDir = await _imageDir();
    if (await imgDir.exists())
      await imgDir.delete(recursive: true);
    await init();
    debugPrint('$_tag resetAll() complete');
  }
}