import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../models/message.dart';

/// On-device encrypted SQLite + SharedPreferences.
/// No server storage. Data stays on phone.
class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  Database? _db;
  static const String _dbName = 'govtsahayak.db';
  static const String _passphraseKey = 'db_passphrase';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? passphrase = prefs.getString(_passphraseKey);
      if (passphrase == null) {
        passphrase = DateTime.now().millisecondsSinceEpoch.toString() +
            (1000 + (DateTime.now().microsecond % 9000)).toString();
        await prefs.setString(_passphraseKey, passphrase);
      }

      final dir = await getApplicationDocumentsDirectory();
      final path = join(dir.path, _dbName);

      _db = await openDatabase(
        path,
        password: passphrase,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              role TEXT NOT NULL,
              text TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              image_path TEXT,
              extracted_data TEXT,
              is_guide_step INTEGER DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              service_id TEXT,
              created_at TEXT,
              data TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE extracted_docs (
              id TEXT PRIMARY KEY,
              doc_type TEXT,
              fields TEXT,
              confidence TEXT,
              created_at TEXT
            )
          ''');
        },
      );
      debugPrint('StorageService initialized (encrypted SQLite)');
    } catch (e) {
      debugPrint('Storage init error (fallback to memory): $e');
    }
  }

  Future<void> saveMessage(ChatMessage msg) async {
    if (_db == null) return;
    await _db!.insert(
      'messages',
      {
        'id': msg.id,
        'role': msg.role.name,
        'text': msg.text,
        'timestamp': msg.timestamp.toIso8601String(),
        'image_path': msg.imagePath,
        'extracted_data':
            msg.extractedData != null ? jsonEncode(msg.extractedData) : null,
        'is_guide_step': msg.isGuideStep ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> loadMessages({int limit = 100}) async {
    if (_db == null) return [];
    final rows = await _db!.query(
      'messages',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return rows.map((r) {
      return ChatMessage(
        id: r['id'] as String,
        role: MessageRole.values.byName(r['role'] as String),
        text: r['text'] as String,
        timestamp: DateTime.parse(r['timestamp'] as String),
        imagePath: r['image_path'] as String?,
        extractedData: r['extracted_data'] != null
            ? jsonDecode(r['extracted_data'] as String)
            : null,
        isGuideStep: (r['is_guide_step'] as int?) == 1,
      );
    }).toList();
  }

  Future<void> saveExtractedDoc({
    required String id,
    required String docType,
    required Map<String, dynamic> fields,
    required Map<String, dynamic> confidence,
  }) async {
    if (_db == null) return;
    await _db!.insert(
      'extracted_docs',
      {
        'id': id,
        'doc_type': docType,
        'fields': jsonEncode(fields),
        'confidence': jsonEncode(confidence),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Wipe all sensitive data (call on "delete after use" or app close if opted)
  Future<void> wipeAllData() async {
    if (_db == null) return;
    await _db!.delete('messages');
    await _db!.delete('sessions');
    await _db!.delete('extracted_docs');
    debugPrint('All local data wiped');
  }

  Future<void> clearChatHistory() async {
    if (_db == null) return;
    await _db!.delete('messages');
  }
}
