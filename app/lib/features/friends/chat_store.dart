import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'chat_models.dart';

/// Local, per-account chat storage (e2ee/db.js): peers (last seen key), messages, meta (unread, retention).
/// Everything stays on this device.
abstract class ChatStore {
  Future<ChatMessage?> message(String id);
  Future<void> putMessage(ChatMessage m);
  Future<void> deleteMessage(String id);
  Future<List<ChatMessage>> messagesOf(String peerId); // oldest first
  Future<Map<String, ChatMessage>> lastMessages(); // peerId -> newest
  Future<PeerRecord?> peer(String id);
  Future<void> putPeer(PeerRecord r);
  Future<String?> meta(String key);
  Future<void> setMeta(String key, String? value); // null deletes
  Future<Map<String, String>> metaWithPrefix(String prefix);

  /// Saves decrypted attachment bytes and returns the local path.
  Future<String> writeFile(String messageId, Uint8List bytes, String ext);
  Future<Uint8List?> readFile(String path);
  Future<void> close();
}

/// sqflite + files in the app's private directory.
class SqliteChatStore implements ChatStore {
  SqliteChatStore._(this._db, this._dir);
  final Database _db;
  final Directory _dir;

  static Future<SqliteChatStore> open(String userId) async {
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'mamba-e2ee-$safe.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE peers (id TEXT PRIMARY KEY, jwk TEXT NOT NULL, fingerprint TEXT NOT NULL, changed INTEGER NOT NULL)');
        await db.execute('''CREATE TABLE messages (
          id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, mine INTEGER NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL,
          status TEXT NOT NULL, reason TEXT, sys TEXT, att_name TEXT, att_type TEXT, att_size INTEGER, att_path TEXT)''');
        await db.execute('CREATE INDEX messages_peer ON messages (peer_id, created_at)');
        await db.execute('CREATE TABLE meta (id TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'chat', safe));
    await dir.create(recursive: true);
    return SqliteChatStore._(db, dir);
  }

  ChatMessage _row(Map<String, Object?> r) => ChatMessage(
        id: r['id'] as String,
        peerId: r['peer_id'] as String,
        mine: r['mine'] == 1,
        text: r['text'] as String,
        createdAt: r['created_at'] as int,
        status: r['status'] as String,
        reason: r['reason'] as String?,
        sys: r['sys'] as String?,
        att: r['att_name'] == null
            ? null
            : ChatAttachment(name: r['att_name'] as String, type: r['att_type'] as String, size: r['att_size'] as int, path: r['att_path'] as String?),
      );

  @override
  Future<ChatMessage?> message(String id) async {
    final r = await _db.query('messages', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : _row(r.first);
  }

  @override
  Future<void> putMessage(ChatMessage m) => _db.insert(
        'messages',
        {
          'id': m.id,
          'peer_id': m.peerId,
          'mine': m.mine ? 1 : 0,
          'text': m.text,
          'created_at': m.createdAt,
          'status': m.status,
          'reason': m.reason,
          'sys': m.sys,
          'att_name': m.att?.name,
          'att_type': m.att?.type,
          'att_size': m.att?.size,
          'att_path': m.att?.path,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> deleteMessage(String id) async {
    final m = await message(id);
    final path = m?.att?.path;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {/* already gone */}
    }
    await _db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<ChatMessage>> messagesOf(String peerId) async =>
      [for (final r in await _db.query('messages', where: 'peer_id = ?', whereArgs: [peerId], orderBy: 'created_at ASC')) _row(r)];

  @override
  Future<Map<String, ChatMessage>> lastMessages() async {
    final rows = await _db.rawQuery('SELECT * FROM messages m WHERE created_at = (SELECT MAX(created_at) FROM messages WHERE peer_id = m.peer_id)');
    return {for (final r in rows) r['peer_id'] as String: _row(r)};
  }

  @override
  Future<PeerRecord?> peer(String id) async {
    final r = await _db.query('peers', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return null;
    return PeerRecord(id: id, jwk: _jwkOf(r.first['jwk'] as String), fingerprint: r.first['fingerprint'] as String, changed: r.first['changed'] == 1);
  }

  @override
  Future<void> putPeer(PeerRecord r) => _db.insert(
        'peers',
        {'id': r.id, 'jwk': '${r.jwk['x']}.${r.jwk['y']}', 'fingerprint': r.fingerprint, 'changed': r.changed ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Map<String, dynamic> _jwkOf(String xy) {
    final parts = xy.split('.');
    return {'kty': 'EC', 'crv': 'P-256', 'x': parts[0], 'y': parts[1]};
  }

  @override
  Future<String?> meta(String key) async {
    final r = await _db.query('meta', where: 'id = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  @override
  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await _db.delete('meta', where: 'id = ?', whereArgs: [key]);
    } else {
      await _db.insert('meta', {'id': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<Map<String, String>> metaWithPrefix(String prefix) async {
    final rows = await _db.query('meta', where: "id LIKE ? ESCAPE '\\'", whereArgs: ['${prefix.replaceAll('%', r'\%').replaceAll('_', r'\_')}%']);
    return {for (final r in rows) r['id'] as String: r['value'] as String};
  }

  @override
  Future<String> writeFile(String messageId, Uint8List bytes, String ext) async {
    final f = File(p.join(_dir.path, '${messageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.$ext'));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() => _db.close();
}

/// In-memory store for tests.
class MemoryChatStore implements ChatStore {
  final Map<String, ChatMessage> _msgs = {};
  final Map<String, PeerRecord> _peers = {};
  final Map<String, String> _meta = {};
  final Map<String, Uint8List> files = {};

  @override
  Future<ChatMessage?> message(String id) async => _msgs[id];
  @override
  Future<void> putMessage(ChatMessage m) async => _msgs[m.id] = m;
  @override
  Future<void> deleteMessage(String id) async {
    final m = _msgs.remove(id);
    if (m?.att?.path != null) files.remove(m!.att!.path);
  }

  @override
  Future<List<ChatMessage>> messagesOf(String peerId) async => (_msgs.values.where((m) => m.peerId == peerId).toList())..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  @override
  Future<Map<String, ChatMessage>> lastMessages() async {
    final out = <String, ChatMessage>{};
    for (final m in _msgs.values) {
      final o = out[m.peerId];
      if (o == null || m.createdAt > o.createdAt) out[m.peerId] = m;
    }
    return out;
  }

  @override
  Future<PeerRecord?> peer(String id) async => _peers[id];
  @override
  Future<void> putPeer(PeerRecord r) async => _peers[r.id] = r;
  @override
  Future<String?> meta(String key) async => _meta[key];
  @override
  Future<void> setMeta(String key, String? value) async => value == null ? _meta.remove(key) : _meta[key] = value;
  @override
  Future<Map<String, String>> metaWithPrefix(String prefix) async => {for (final e in _meta.entries) if (e.key.startsWith(prefix)) e.key: e.value};
  @override
  Future<String> writeFile(String messageId, Uint8List bytes, String ext) async {
    final path = 'mem://$messageId.$ext';
    files[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List?> readFile(String path) async => files[path];
  @override
  Future<void> close() async {}
}
