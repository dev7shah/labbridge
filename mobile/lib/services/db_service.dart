import 'dart:io';
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/folder.dart';
import '../models/file_item.dart';
import '../models/transfer.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _database;
  Future<Database>? _initFuture;
  static const _uuid = Uuid();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _initFuture ??= _initDatabase();
    try {
      _database = await _initFuture!;
      return _database!;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    String path;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      path = inMemoryDatabasePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = p.join(dbPath, 'doctransit_v2.db');
    }

    return await openDatabase(
      path,
      version: 2, // Bumped to version 2 to trigger onUpgrade if needed
      onConfigure: (db) async {
        // Enable FK enforcement so ON DELETE SET NULL / CASCADE fire correctly.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        // Simple strategy for ephemeral data: drop and recreate
        await db.execute('DROP TABLE IF EXISTS transfers');
        await db.execute('DROP TABLE IF EXISTS files');
        await db.execute('DROP TABLE IF EXISTS folders');
        await _createTables(db);
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        color TEXT DEFAULT '#6C63FF',
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE files (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        local_path TEXT NOT NULL,
        size INTEGER NOT NULL,
        mime_type TEXT,
        folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
        received_at INTEGER NOT NULL,
        tags TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE transfers (
        id TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        size INTEGER NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        folder_id TEXT,
        completed_at INTEGER
      )
    ''');

    // Seed default folders
    final now = DateTime.now().millisecondsSinceEpoch;
    final sem1Id = _uuid.v4();
    final sem2Id = _uuid.v4();
    final labPracticalsId = _uuid.v4();

    await db.insert('folders', {
      'id': sem1Id,
      'name': 'Semester 1',
      'parent_id': null,
      'color': '#6C63FF',
      'sort_order': 0,
      'created_at': now,
    });

    await db.insert('folders', {
      'id': sem2Id,
      'name': 'Semester 2',
      'parent_id': null,
      'color': '#22C55E',
      'sort_order': 1,
      'created_at': now,
    });

    await db.insert('folders', {
      'id': labPracticalsId,
      'name': 'Lab Practicals',
      'parent_id': sem1Id,
      'color': '#EF4444',
      'sort_order': 0,
      'created_at': now,
    });
  }

  Future<void> init() async {
    await database;
  }

  // ─── Folders ──────────────────────────────────────────

  Future<List<Folder>> getAllFolders() async {
    final db = await database;
    final maps = await db.query('folders', orderBy: 'sort_order ASC');
    return maps.map((m) => Folder.fromMap(m)).toList();
  }

  Future<List<Folder>> getChildFolders(String? parentId) async {
    final db = await database;
    final maps = await db.query(
      'folders',
      where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?',
      whereArgs: parentId == null ? null : [parentId],
      orderBy: 'sort_order ASC',
    );
    return maps.map((m) => Folder.fromMap(m)).toList();
  }

  Future<Folder?> getFolder(String id) async {
    final db = await database;
    final maps = await db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Folder.fromMap(maps.first);
  }

  String _sanitizeFolderName(String raw) {
    var clean = raw.trim().replaceAll(RegExp(r'[\\/]+'), '');
    if (clean.isEmpty || clean == '.' || clean == '..') clean = 'Folder';
    if (clean.length > 100) clean = clean.substring(0, 100);
    return clean;
  }

  Future<void> insertFolder(Folder folder) async {
    final db = await database;
    final sanitized = folder.copyWith(name: _sanitizeFolderName(folder.name));
    await db.insert('folders', sanitized.toMap());
  }

  Future<void> updateFolder(Folder folder) async {
    final db = await database;
    final sanitized = folder.copyWith(name: _sanitizeFolderName(folder.name));
    await db.update('folders', sanitized.toMap(), where: 'id = ?', whereArgs: [folder.id]);
  }

  Future<void> deleteFolder(String id) async {
    final db = await database;
    final folder = await getFolder(id);
    final targetParentId = folder?.parentId; // null → root
    await db.transaction((txn) async {
      // Re-parent direct child folders up one level
      if (folder != null) {
        if (targetParentId != null) {
          await txn.update(
            'folders',
            {'parent_id': targetParentId},
            where: 'parent_id = ?',
            whereArgs: [id],
          );
        } else {
          // Moving to root — parent_id must be NULL, not a string
          await txn.rawUpdate(
            'UPDATE folders SET parent_id = NULL WHERE parent_id = ?',
            [id],
          );
        }
      }
      // Re-parent files contained directly in this folder to the same destination.
      // This is necessary because PRAGMA foreign_keys only fires on new connections
      // and SQLite's ON DELETE SET NULL would not retroactively fix existing orphans.
      if (targetParentId != null) {
        await txn.update(
          'files',
          {'folder_id': targetParentId},
          where: 'folder_id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.rawUpdate(
          'UPDATE files SET folder_id = NULL WHERE folder_id = ?',
          [id],
        );
      }
      await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, dynamic>>> getFolderTree() async {
    final allFolders = await getAllFolders();
    return _buildTree(allFolders, null);
  }

  List<Map<String, dynamic>> _buildTree(List<Folder> allFolders, String? parentId) {
    final children = allFolders.where((f) => f.parentId == parentId).toList();
    return children.map((folder) {
      final json = folder.toJson();
      json['children'] = _buildTree(allFolders, folder.id);
      return json;
    }).toList();
  }

  // ─── Files ────────────────────────────────────────────

  Future<List<FileItem>> getAllFiles() async {
    final db = await database;
    final maps = await db.query('files', orderBy: 'received_at DESC');
    return maps.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FileItem>> getFilesInFolder(String? folderId) async {
    final db = await database;
    final maps = await db.query(
      'files',
      where: folderId == null ? 'folder_id IS NULL' : 'folder_id = ?',
      whereArgs: folderId == null ? null : [folderId],
      orderBy: 'received_at DESC',
    );
    return maps.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FileItem>> getRecentFiles(int limit) async {
    final db = await database;
    final maps = await db.query('files', orderBy: 'received_at DESC', limit: limit);
    return maps.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<void> insertFile(FileItem file) async {
    final db = await database;
    await db.insert('files', file.toMap());
  }

  Future<void> updateFile(FileItem file) async {
    final db = await database;
    await db.update('files', file.toMap(), where: 'id = ?', whereArgs: [file.id]);
  }

  Future<void> deleteFile(String id) async {
    final db = await database;
    final maps = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final localPath = maps.first['local_path'] as String?;
      if (localPath != null && localPath.isNotEmpty) {
        try {
          final file = File(localPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getStorageUsed() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COALESCE(SUM(size), 0) as total FROM files');
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getFilesCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM files');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> getFoldersCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM folders');
    return (result.first['count'] as int?) ?? 0;
  }

  // ─── Transfers ────────────────────────────────────────

  Future<List<Transfer>> getAllTransfers() async {
    final db = await database;
    final maps = await db.query('transfers', orderBy: 'completed_at DESC');
    return maps.map((m) => Transfer.fromMap(m)).toList();
  }

  Future<void> insertTransfer(Transfer transfer) async {
    final db = await database;
    await db.insert('transfers', transfer.toMap());
  }

  Future<void> deleteTransfer(String id) async {
    final db = await database;
    await db.delete('transfers', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Danger Zone ──────────────────────────────────────

  Future<void> clearAllData() async {
    final db = await database;
    
    await db.transaction((txn) async {
      final allFiles = await txn.query('files');
      
      await txn.delete('transfers');
      await txn.delete('files');
      await txn.delete('folders');
      await _createTables(txn);
      
      // Delete physical files only after DB tables are cleared
      for (final map in allFiles) {
        final localPath = map['local_path'] as String?;
        if (localPath != null && localPath.isNotEmpty) {
          try {
            final file = File(localPath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
      try {
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          final docsDir = await getApplicationDocumentsDirectory();
          final docTransitDir = Directory(p.join(docsDir.path, 'DocTransit'));
          if (await docTransitDir.exists()) {
            await docTransitDir.delete(recursive: true);
            await docTransitDir.create();
          }
        }
      } catch (_) {}
    });
  }
}
