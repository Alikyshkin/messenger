import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../models/chat.dart';
import '../models/user.dart';

/// Локальная БД в стиле Telegram/Signal: источник правды для UI, офлайн-кэш, очередь отправки.
/// На веб sqflite может быть недоступен — тогда работа идёт только через API.
class LocalDb {
  static Database? _db;
  static bool _failed = false;
  static const _dbName = 'messenger_local.db';
  static const _version = 4;

  static Future<Database?> _getDb() async {
    if (_db != null) {
      return _db;
    }
    if (_failed) {
      return null;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = join(dir.path, _dbName);
      _db = await openDatabase(
        path,
        version: _version,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE chats (
            peer_id INTEGER PRIMARY KEY,
            peer_json TEXT NOT NULL,
            last_message_id INTEGER,
            last_message_preview TEXT,
            last_message_at TEXT,
            last_message_is_mine INTEGER,
            last_message_type TEXT,
            updated_at TEXT
          )
        ''');
          await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY,
            peer_id INTEGER NOT NULL,
            sender_id INTEGER NOT NULL,
            receiver_id INTEGER NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            read_at TEXT,
            is_mine INTEGER NOT NULL,
            attachment_url TEXT,
            attachment_filename TEXT,
            message_type TEXT,
            poll_id INTEGER,
            attachment_kind TEXT,
            attachment_duration_sec INTEGER,
            sender_public_key TEXT,
            poll_json TEXT
          )
        ''');
          await db.execute(
            'CREATE INDEX idx_messages_peer ON messages(peer_id)',
          );
          await db.execute(
            'CREATE INDEX idx_messages_created ON messages(created_at)',
          );
          await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            peer_id INTEGER NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            try {
              await db.execute(
                'ALTER TABLE chats ADD COLUMN last_message_is_mine INTEGER',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE chats ADD COLUMN last_message_type TEXT',
              );
            } catch (_) {}
          }
          if (oldVersion < 3) {
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN attachment_encrypted INTEGER',
              );
            } catch (_) {}
          }
          if (oldVersion < 4) {
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN reply_to_id INTEGER',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN reply_to_content TEXT',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN reply_to_sender_name TEXT',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN is_forwarded INTEGER',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN forward_from_sender_id INTEGER',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE messages ADD COLUMN forward_from_display_name TEXT',
              );
            } catch (_) {}
          }
        },
      );
      return _db;
    } catch (e) {
      _failed = true;
      if (kDebugMode) debugPrint('LocalDb init failed: $e');
      return null;
    }
  }

  static Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  /// Очистить все данные (при выходе).
  static Future<void> clearAll() async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    await db.delete('chats');
    await db.delete('messages');
    await db.delete('outbox');
  }

  // --- Chats ---

  static Future<void> upsertChat(ChatPreview chat) async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    final peer = chat.peer;
    if (peer == null) {
      return;
    }
    final last = chat.lastMessage;
    await db.insert('chats', {
      'peer_id': peer.id,
      'peer_json': jsonEncode({
        'id': peer.id,
        'username': peer.username,
        'display_name': peer.displayName,
        'bio': peer.bio,
        'avatar_url': peer.avatarUrl,
        'public_key': peer.publicKey,
      }),
      'last_message_id': last?.id,
      'last_message_preview': last?.content,
      'last_message_at': last?.createdAt,
      'last_message_is_mine': last?.isMine == true ? 1 : 0,
      'last_message_type': last?.messageType,
      'updated_at': last?.createdAt ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<ChatPreview>> getChats() async {
    final db = await _getDb();
    if (db == null) {
      return [];
    }
    final rows = await db.query('chats', orderBy: 'updated_at DESC');
    return rows.map((r) {
      final peer = User.fromJson(
        Map<String, dynamic>.from(jsonDecode(r['peer_json'] as String)),
      );
      LastMessage? last;
      if (r['last_message_id'] != null) {
        last = LastMessage(
          id: r['last_message_id'] as int,
          content: r['last_message_preview'] as String? ?? '',
          createdAt: r['last_message_at'] as String? ?? '',
          isMine: (r['last_message_is_mine'] as int?) == 1,
          messageType: r['last_message_type'] as String? ?? 'text',
        );
      }
      return ChatPreview(peer: peer, lastMessage: last);
    }).toList();
  }

  /// Удалить чат и все сообщения с пользователем из локальной БД
  static Future<void> deleteChat(int peerId) async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    await db.delete('chats', where: 'peer_id = ?', whereArgs: [peerId]);
    await db.delete(
      'messages',
      where: 'sender_id = ? OR receiver_id = ?',
      whereArgs: [peerId, peerId],
    );
    await db.delete('outbox', where: 'peer_id = ?', whereArgs: [peerId]);
  }

  /// Удалить групповой чат из локальной БД
  static Future<void> deleteGroupChat(int groupId) async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    // Для групповых чатов удаляем только из локального кэша
    // Сообщения остаются, так как они хранятся на сервере
    // В будущем можно добавить отдельную таблицу для групповых чатов
  }

  // --- Messages ---

  static Message _messageFromRow(Map<String, dynamic> r) {
    PollData? poll;
    if (r['poll_json'] != null && (r['poll_json'] as String).isNotEmpty) {
      try {
        final p = jsonDecode(r['poll_json'] as String) as Map<String, dynamic>;
        final opts =
            (p['options'] as List<dynamic>?)?.map((e) {
              final o = e as Map<String, dynamic>;
              return PollOption(
                text: o['text'] as String,
                votes: o['votes'] as int? ?? 0,
                voted: o['voted'] as bool? ?? false,
              );
            }).toList() ??
            [];
        poll = PollData(
          id: p['id'] as int,
          question: p['question'] as String? ?? '',
          options: opts,
          multiple: p['multiple'] as bool? ?? false,
        );
      } catch (_) {}
    }
    return Message(
      id: r['id'] as int,
      senderId: r['sender_id'] as int,
      receiverId: r['receiver_id'] as int,
      content: r['content'] as String? ?? '',
      createdAt: r['created_at'] as String,
      readAt: r['read_at'] as String?,
      isMine: (r['is_mine'] as int) == 1,
      attachmentUrl: r['attachment_url'] as String?,
      attachmentFilename: r['attachment_filename'] as String?,
      messageType: r['message_type'] as String? ?? 'text',
      pollId: r['poll_id'] as int?,
      poll: poll,
      attachmentKind: r['attachment_kind'] as String? ?? 'file',
      attachmentDurationSec: r['attachment_duration_sec'] as int?,
      senderPublicKey: r['sender_public_key'] as String?,
      attachmentEncrypted: (r['attachment_encrypted'] as int?) == 1,
      replyToId: r['reply_to_id'] as int?,
      replyToContent: r['reply_to_content'] as String?,
      replyToSenderName: r['reply_to_sender_name'] as String?,
      isForwarded: (r['is_forwarded'] as int?) == 1,
      forwardFromSenderId: r['forward_from_sender_id'] as int?,
      forwardFromDisplayName: r['forward_from_display_name'] as String?,
    );
  }

  static Future<void> upsertMessage(Message m, int peerId) async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    await db.insert('messages', {
      'id': m.id,
      'peer_id': peerId,
      'sender_id': m.senderId,
      'receiver_id': m.receiverId,
      'content': m.content,
      'created_at': m.createdAt,
      'read_at': m.readAt,
      'is_mine': m.isMine ? 1 : 0,
      'attachment_url': m.attachmentUrl,
      'attachment_filename': m.attachmentFilename,
      'message_type': m.messageType,
      'poll_id': m.pollId,
      'attachment_kind': m.attachmentKind,
      'attachment_duration_sec': m.attachmentDurationSec,
      'sender_public_key': m.senderPublicKey,
      'attachment_encrypted': m.attachmentEncrypted ? 1 : 0,
      'reply_to_id': m.replyToId,
      'reply_to_content': m.replyToContent,
      'reply_to_sender_name': m.replyToSenderName,
      'is_forwarded': m.isForwarded ? 1 : 0,
      'forward_from_sender_id': m.forwardFromSenderId,
      'forward_from_display_name': m.forwardFromDisplayName,
      'poll_json': m.poll != null
          ? jsonEncode({
              'id': m.poll!.id,
              'question': m.poll!.question,
              'options': m.poll!.options
                  .map(
                    (o) => {'text': o.text, 'votes': o.votes, 'voted': o.voted},
                  )
                  .toList(),
              'multiple': m.poll!.multiple,
            })
          : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Message>> getMessages(int peerId) async {
    final db = await _getDb();
    if (db == null) {
      return [];
    }
    final rows = await db.query(
      'messages',
      where: 'peer_id = ?',
      whereArgs: [peerId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((r) => _messageFromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  static Future<void> updateChatLastMessage(int peerId, Message last) async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    final row = await db.query(
      'chats',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
    if (row.isEmpty) {
      return;
    }
    await db.update(
      'chats',
      {
        'last_message_id': last.id,
        'last_message_preview': last.content,
        'last_message_at': last.createdAt,
        'last_message_is_mine': last.isMine ? 1 : 0,
        'last_message_type': last.messageType,
        'updated_at': last.createdAt,
      },
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }

  // --- Outbox (очередь отправки при офлайне) ---

  static Future<List<OutboxItem>> getOutbox() async {
    final db = await _getDb();
    if (db == null) {
      return [];
    }
    final rows = await db.query('outbox', orderBy: 'created_at ASC');
    return rows
        .map(
          (r) => OutboxItem(
            id: r['id'] as int,
            peerId: r['peer_id'] as int,
            content: r['content'] as String,
            createdAt: r['created_at'] as String,
          ),
        )
        .toList();
  }

  static Future<int> addToOutbox(int peerId, String content) async {
    final db = await _getDb();
    if (db == null) {
      return 0;
    }
    return db.insert('outbox', {
      'peer_id': peerId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> removeFromOutbox(int id) async {
    final db = await _getDb();
    if (db == null) {
      return;
    }
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }
}

class OutboxItem {
  final int id;
  final int peerId;
  final String content;
  final String createdAt;
  OutboxItem({
    required this.id,
    required this.peerId,
    required this.content,
    required this.createdAt,
  });
}
