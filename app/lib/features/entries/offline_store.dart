// Basic offline support for Nhập số (port of frontend/src/offline.js, with shared_preferences instead of IndexedDB).
//
// - New entries (and edits) made without a network are put in a persistent queue and shown straight away flagged
//   "Chờ đồng bộ". When the network is back the queue is replayed in order.
// - Creates carry a client-chosen id (`clientId`) so a retry after a lost response can never create a duplicate.
// - An edit carries the `updatedAt` it was based on; the server answers 409 `{conflict, server}` when the row changed
//   meanwhile, and the user then chooses which version to keep.
// - Not available offline: deleting entries.
// - The last loaded entry list / customers / profile are cached per account for offline viewing.
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'entry_model.dart';

const _queueKey = 'xoso_offline_queue';
const _pageSize = 500;

/// The account id = the JWT `sub` (the queue and caches are per account).
String? userIdFromToken(String? token) {
  if (token == null || token.isEmpty) return null;
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final sub = payload is Map ? payload['sub'] : null;
    return sub == null ? null : '$sub';
  } catch (_) {
    return null;
  }
}

bool isNetworkError(Object e) => e is ApiError && e.status == 0;

class QueuedOp {
  QueuedOp({
    required this.opId,
    required this.seq,
    required this.userId,
    required this.type,
    required this.entryId,
    required this.payload,
    required this.createdAt,
    this.baseUpdatedAt,
    this.conflict = false,
  });

  final String opId;
  final int seq;
  final String? userId;

  /// 'create' or 'patch'
  final String type;
  final String entryId;
  Map<String, dynamic> payload;
  final String createdAt;
  final String? baseUpdatedAt;
  bool conflict;

  factory QueuedOp.fromJson(Map<String, dynamic> j) => QueuedOp(
        opId: j['opId'] as String,
        seq: (j['seq'] as num).toInt(),
        userId: j['userId'] as String?,
        type: j['type'] as String,
        entryId: j['entryId'] as String,
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        createdAt: (j['createdAt'] as String?) ?? '',
        baseUpdatedAt: j['baseUpdatedAt'] as String?,
        conflict: j['conflict'] == true,
      );

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'seq': seq,
        'userId': userId,
        'type': type,
        'entryId': entryId,
        'payload': payload,
        'createdAt': createdAt,
        'baseUpdatedAt': baseUpdatedAt,
        'conflict': conflict,
      };
}

/// An edit that collided with a newer server copy; waits for the user's choice.
class SyncConflict {
  SyncConflict({required this.opId, required this.entryId, required this.mine, required this.server});
  final String? opId;
  final String entryId;
  final Map<String, dynamic> mine;
  final Map<String, dynamic> server;
}

/// An operation the server refused for good (it was dropped from the queue).
class SyncFailure {
  SyncFailure(this.id, this.message);
  final String id;
  final String message;
}

class FlushResult {
  FlushResult({this.changed = false, this.offline = false, this.skipped = false, this.conflicts = const [], this.failures = const []});
  final bool changed;
  final bool offline;
  final bool skipped;
  final List<SyncConflict> conflicts;
  final List<SyncFailure> failures;
}

class LoadedEntries {
  LoadedEntries(this.entries, {this.fromCache = false, this.noCache = false});
  final List<Entry> entries;
  final bool fromCache;
  final bool noCache;
}

class SaveResult {
  SaveResult(this.entry, this.queued);
  final Entry entry;
  final bool queued;
}

class OfflineStore {
  OfflineStore({required this.api, required this.prefs, required this.userId, String Function()? newId, DateTime Function()? now})
      : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final ApiClient api;
  final SharedPreferences prefs;
  final String? userId;
  final String Function() _newId;
  final DateTime Function() _now;

  bool syncing = false;
  int _seqCounter = 0;
  Future<void> _lock = Future.value();

  static Future<OfflineStore> open(ApiClient api, AuthStore auth) async =>
      OfflineStore(api: api, prefs: await SharedPreferences.getInstance(), userId: userIdFromToken(auth.token));

  // ---- queue persistence (serialised so two callers never overwrite each other) ----------------------------------

  Future<T> _locked<T>(Future<T> Function() fn) {
    final done = Completer<T>();
    final prev = _lock;
    _lock = done.future.then((_) {}, onError: (_) {});
    prev.then((_) async {
      try {
        done.complete(await fn());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  List<QueuedOp> _readAll() {
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) QueuedOp.fromJson(Map<String, dynamic>.from(j as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<QueuedOp> all) => prefs.setString(_queueKey, jsonEncode([for (final o in all) o.toJson()]));

  List<QueuedOp> _mine(List<QueuedOp> all) => (all.where((o) => o.userId == userId).toList()..sort((a, b) => a.seq.compareTo(b.seq)));

  Future<List<QueuedOp>> ops() => _locked(() async => _mine(_readAll()));

  Future<int> pendingCount() async => (await ops()).length;

  Future<void> _put(QueuedOp op) => _locked(() async {
        final all = _readAll();
        final i = all.indexWhere((o) => o.opId == op.opId);
        if (i == -1) {
          all.add(op);
        } else {
          all[i] = op;
        }
        await _writeAll(all);
      });

  Future<void> _delete(String opId) => _locked(() async {
        final all = _readAll()..removeWhere((o) => o.opId == opId);
        await _writeAll(all);
      });

  int _nextSeq() => _now().millisecondsSinceEpoch * 1000 + (_seqCounter++ % 1000);

  // ---- cached GETs -----------------------------------------------------------------------------------------------

  /// GET with a cached fallback: the fresh answer, or the last cached one when the network is down.
  Future<dynamic> cachedGet(String path) async {
    final key = 'get:$userId:$path';
    try {
      final data = await api.get(path);
      await _kvSet(key, data);
      return data;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = _kvGet(key);
      if (cached != null) return cached;
      rethrow;
    }
  }

  dynamic _kvGet(String key) {
    final raw = prefs.getString('xoso_cache:$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _kvSet(String key, Object? value) async {
    try {
      await prefs.setString('xoso_cache:$key', jsonEncode(value));
    } catch (_) {/* cache is best-effort */}
  }

  // ---- entries ---------------------------------------------------------------------------------------------------

  /// Server list with the not-yet-synced operations laid over it, so the user sees their own offline work.
  Future<List<Entry>> overlayPending(List<Entry> list) async {
    final pendingOps = (await ops()).where((o) => !o.conflict).toList();
    var out = [...list];
    for (final op in pendingOps) {
      if (op.type == 'create') {
        if (!out.any((e) => e.id == op.entryId)) {
          out.insert(0, Entry.fromJson({...op.payload, 'id': op.entryId, 'createdAt': op.createdAt, 'updatedAt': op.createdAt}));
        }
      } else {
        out = [for (final e in out) e.id == op.entryId ? e.applying(op.payload) : e];
      }
    }
    final pendingIds = pendingOps.map((o) => o.entryId).toSet();
    return [for (final e in out) pendingIds.contains(e.id) ? e.withPending(true) : e];
  }

  /// EVERY page of `GET /me/entries` (limit/offset, `{entries, total, hasMore}`), de-duplicated by id.
  Future<List<Entry>> _fetchAllPages() async {
    final byId = <String, Entry>{};
    var offset = 0;
    for (;;) {
      final page = await api.get('/me/entries?limit=$_pageSize&offset=$offset');
      final list = (page is Map ? page['entries'] : null) as List? ?? const [];
      for (final j in list) {
        final e = Entry.fromJson(Map<String, dynamic>.from(j as Map));
        byId[e.id] = e;
      }
      offset += list.length;
      if (page is! Map || page['hasMore'] != true || list.isEmpty) break;
    }
    return byId.values.toList();
  }

  String get _entriesKey => 'entries:$userId';

  /// The COMPLETE history (all pages); offline: the cached copy. Cached in full for offline use.
  Future<LoadedEntries> loadAllEntries({bool overlay = true}) async {
    Future<List<Entry>> lay(List<Entry> l) => overlay ? overlayPending(l) : Future.value(l);
    try {
      final entries = await _fetchAllPages();
      await _kvSet(_entriesKey, [for (final e in entries) e.toJson()]);
      return LoadedEntries(await lay(entries));
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = _kvGet(_entriesKey);
      final list = cached is List ? [for (final j in cached) Entry.fromJson(Map<String, dynamic>.from(j as Map))] : <Entry>[];
      return LoadedEntries(await lay(list), fromCache: true, noCache: cached == null);
    }
  }

  Future<void> _cacheEntryLocally(Entry entry) async {
    final cached = _kvGet(_entriesKey);
    final list = cached is List ? [...cached] : <dynamic>[];
    final i = list.indexWhere((j) => j is Map && j['id'] == entry.id);
    if (i == -1) {
      list.insert(0, entry.toJson());
    } else {
      list[i] = entry.toJson();
    }
    await _kvSet(_entriesKey, list);
  }

  /// Creates an entry; with the network down it is queued instead. Other errors (quota, validation) are thrown.
  Future<SaveResult> createEntry(Map<String, dynamic> payload) async {
    final entryId = _newId();
    try {
      final res = await api.post('/me/entries', {...payload, 'clientId': entryId});
      final entry = Entry.fromJson(Map<String, dynamic>.from(res as Map));
      await _cacheEntryLocally(entry);
      return SaveResult(entry, false);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final createdAt = _now().toUtc().toIso8601String();
      await _put(QueuedOp(opId: _newId(), seq: _nextSeq(), userId: userId, type: 'create', entryId: entryId, payload: {...payload}, createdAt: createdAt));
      return SaveResult(Entry.fromJson({...payload, 'id': entryId, 'createdAt': createdAt, 'updatedAt': createdAt, 'pending': true}), true);
    }
  }

  /// Edits an entry ([changes] = fields to PATCH). Offline -> queued; a still-unsynced create just absorbs the change.
  /// A 409 conflict is thrown as [ApiError] (`data['conflict']`, `data['server']`) for the caller to handle.
  Future<SaveResult> updateEntry(Entry entry, Map<String, dynamic> changes) async {
    final all = await ops();
    final pendingCreate = all.where((o) => o.type == 'create' && o.entryId == entry.id).firstOrNull;
    if (pendingCreate != null) {
      pendingCreate.payload = {...pendingCreate.payload, ...changes};
      await _put(pendingCreate);
      return SaveResult(entry.applying(changes, pending: true), true);
    }
    final pendingPatch = all.where((o) => o.type == 'patch' && o.entryId == entry.id).firstOrNull;
    if (pendingPatch == null) {
      try {
        final res = await api.patch('/me/entries/${entry.id}', {...changes, 'baseUpdatedAt': entry.updatedAt});
        final updated = Entry.fromJson(Map<String, dynamic>.from(res as Map));
        await _cacheEntryLocally(updated);
        return SaveResult(updated, false);
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
      }
    }
    // offline (or an earlier edit is already waiting): queue / merge
    if (pendingPatch != null) {
      pendingPatch.payload = {...pendingPatch.payload, ...changes};
      await _put(pendingPatch);
    } else {
      await _put(QueuedOp(
        opId: _newId(),
        seq: _nextSeq(),
        userId: userId,
        type: 'patch',
        entryId: entry.id,
        baseUpdatedAt: entry.updatedAt,
        payload: {...changes},
        createdAt: _now().toUtc().toIso8601String(),
      ));
    }
    return SaveResult(entry.applying(changes, pending: true), true);
  }

  /// Replays the queue in order. Safe to call any time; stops at the first network error.
  Future<FlushResult> flush() async {
    if (syncing || userId == null) return FlushResult(skipped: true);
    syncing = true;
    var changed = false;
    var offline = false;
    final conflicts = <SyncConflict>[];
    final failures = <SyncFailure>[];
    try {
      for (final op in await ops()) {
        if (op.conflict) continue;
        try {
          if (op.type == 'create') {
            await api.post('/me/entries', {...op.payload, 'clientId': op.entryId});
          } else {
            await api.patch('/me/entries/${op.entryId}', {...op.payload, 'baseUpdatedAt': op.baseUpdatedAt});
          }
          await _delete(op.opId);
          changed = true;
        } on ApiError catch (err) {
          if (err.status == 0) {
            offline = true;
            break;
          }
          // 401 (session gone) / 5xx (server hiccup): keep the queue, retry later
          if (err.status == 401 || err.status >= 500) break;
          if (err.status == 409 && err.data?['conflict'] == true) {
            op.conflict = true;
            await _put(op);
            conflicts.add(SyncConflict(opId: op.opId, entryId: op.entryId, mine: op.payload, server: Map<String, dynamic>.from(err.data!['server'] as Map)));
            continue;
          }
          // Refused for good (quota, deleted entry, invalid...): drop it so it cannot block the queue, tell the user.
          await _delete(op.opId);
          changed = true;
          failures.add(SyncFailure(op.opId, 'Không đồng bộ được "${op.payload['value'] ?? ''}": ${err.message}'));
        }
      }
    } finally {
      syncing = false;
    }
    return FlushResult(changed: changed, offline: offline, conflicts: conflicts, failures: failures);
  }

  /// Operations parked as conflicts by an earlier session (so they can be offered again).
  Future<List<QueuedOp>> conflictedOps() async => (await ops()).where((o) => o.conflict).toList();

  /// The user's decision for a conflict: keep `mine` (overwrite, `force`) or the server's copy.
  Future<void> resolveConflict(SyncConflict c, {required bool keepMine}) async {
    try {
      if (keepMine) {
        final res = await api.patch('/me/entries/${c.entryId}', {...c.mine, 'force': true});
        await _cacheEntryLocally(Entry.fromJson(Map<String, dynamic>.from(res as Map)));
      } else {
        await _cacheEntryLocally(Entry.fromJson(c.server));
      }
      if (c.opId != null) await _delete(c.opId!);
    } on ApiError catch (e) {
      if (e.status == 0) throw ApiError(0, 'Đang offline, thử lại khi có mạng');
      rethrow;
    }
  }
}
