import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import 'chat_store.dart';

class ChatDatabase implements ChatStore {
  ChatDatabase._(this._db);

  final Database _db;

  static Future<ChatDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'faceup_agents.db');
    final database = await openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            meta TEXT NOT NULL DEFAULT '{}',
            pending INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (chat_id) REFERENCES chats (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX messages_chat_id_idx ON messages (chat_id, created_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN pending INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
    return ChatDatabase._(database);
  }

  @override
  Future<List<ChatThread>> listChats() async {
    final rows = await _db.query('chats', orderBy: 'updated_at DESC');
    return rows.map(_chatFromRow).toList();
  }

  @override
  Future<ChatThread> createChat(String id, DateTime now) async {
    await _db.insert('chats', {
      'id': id,
      'title': '',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return ChatThread(id: id, title: '', createdAt: now, updatedAt: now);
  }

  @override
  Future<void> renameChat(String id, String title, DateTime now) async {
    await _db.update(
      'chats',
      {'title': title, 'updated_at': now.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> touchChat(String id, DateTime now) async {
    await _db.update(
      'chats',
      {'updated_at': now.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteChat(String id) async {
    await _db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<ChatMessage>> messagesForChat(String chatId) async {
    final rows = await _db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC, rowid ASC',
    );
    return rows.map(ChatMessage.fromDatabase).toList();
  }

  @override
  Future<void> insertMessage(ChatMessage message) async {
    await _db.insert(
      'messages',
      message.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteMessage(String id) async {
    await _db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<ChatMessage>> pendingMessages() async {
    final rows = await _db.query(
      'messages',
      where: 'pending = 1',
      orderBy: 'created_at ASC, rowid ASC',
    );
    return rows.map(ChatMessage.fromDatabase).toList();
  }

  Future<void> deleteMessagesAfter(String chatId, DateTime createdAt) async {
    await _db.delete(
      'messages',
      where: 'chat_id = ? AND created_at >= ?',
      whereArgs: [chatId, createdAt.millisecondsSinceEpoch],
    );
  }

  Future<void> close() => _db.close();

  ChatThread _chatFromRow(Map<String, Object?> row) {
    return ChatThread(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int? ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? 0,
      ),
    );
  }
}
