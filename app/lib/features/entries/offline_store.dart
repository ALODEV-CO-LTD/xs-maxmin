// Basic offline support for Nhập số (port of frontend/src/offline.js, with shared_preferences instead of IndexedDB).
//
// - New entries (and edits) made without a network are put in a persistent queue and shown straight away flagged
//   "Chờ đồng bộ". When the network is back the queue is replayed in order.
// - Creates carry a client-chosen id (`clientId`) so a retry after a lost response can never create a duplicate.
// - An edit carries the `updatedAt` it was based on; the server answers 409 `{conflict, server}` when the row changed
//   meanwhile, and the user then chooses which version to keep.
// - Not available offline: deleting entries. Lottery results (Nhập kết quả) are kept on the phone first and sent later.
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

  /// Entry: 'create', 'patch', 'delete'. Customer roster: 'cust-create', 'cust-delete' ([entryId] is then the customer's id).
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
    final data = (await _cachedGetFlag(path)).$1;
    return path == '/me/customers' ? await overlayCustomers(data) : data;
  }

  /// Like [cachedGet] but also says whether the answer came from the saved copy (the network was down).
  Future<(dynamic, bool)> _cachedGetFlag(String path) async {
    final key = 'get:$userId:$path';
    try {
      final data = await api.get(path);
      await _kvSet(key, data);
      return (data, false);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final cached = _kvGet(key);
      if (cached != null) return (cached, true);
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

  // ---- lottery results (Nhập kết quả): belong to the ACCOUNT, saved on this phone first -------------------------------

  String get _resultsKey => 'xoso_results:$userId';

  /// "date|station" -> {json: the result as the server shows it, pending: true until it reached the server}.
  Map<String, Map<String, dynamic>> _localResults() {
    final raw = prefs.getString(_resultsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: Map<String, dynamic>.from(e.value as Map)};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeLocalResults(Map<String, Map<String, dynamic>> m) => _locked(() => prefs.setString(_resultsKey, jsonEncode(m)));

  static String _rk(String date, String station) => '$date|$station';

  /// Results saved on this phone that the server has not received yet.
  Future<int> pendingResultCount() async => _localResults().values.where((v) => v['pending'] == true).length;

  /// Saves a result ([body] = the POST /lottery-results body) ON THIS PHONE first, then sends it. Returns true when it
  /// is only on the phone so far (no network) and will be sent later. Validation errors from the server are thrown.
  Future<bool> saveResult(Map<String, dynamic> body) async {
    final date = body['drawDate'] as String;
    final station = (body['station'] as String?) ?? 'mb';
    final local = _localResults();
    local[_rk(date, station)] = {'json': {...body, 'updatedAt': _now().toUtc().toIso8601String()}, 'pending': true};
    await _writeLocalResults(local);
    try {
      final res = await api.post('/lottery-results', body);
      final saved = res is Map ? res['result'] : null;
      final after = _localResults();
      after[_rk(date, station)] = {'json': saved is Map ? Map<String, dynamic>.from(saved) : local[_rk(date, station)]!['json'], 'pending': false};
      await _writeLocalResults(after);
      return false;
    } catch (e) {
      if (isNetworkError(e)) return true;
      final after = _localResults()..remove(_rk(date, station));
      await _writeLocalResults(after);
      rethrow;
    }
  }

  /// Forgets the copy kept on this phone (after a delete). Returns true when it was still waiting to be sent.
  Future<bool> forgetResult(String date, String station) async {
    final local = _localResults();
    final was = local.remove(_rk(date, station));
    await _writeLocalResults(local);
    return was != null && was['pending'] == true;
  }

  /// Sends the results still waiting. Returns (sent any, offline, refused messages).
  Future<(bool, bool, List<String>)> _flushResults() async {
    var sent = false;
    final refused = <String>[];
    for (final e in _localResults().entries.where((e) => e.value['pending'] == true).toList()) {
      final body = Map<String, dynamic>.from(e.value['json'] as Map)..remove('updatedAt');
      try {
        final res = await api.post('/lottery-results', body);
        final saved = res is Map ? res['result'] : null;
        final after = _localResults();
        after[e.key] = {'json': saved is Map ? Map<String, dynamic>.from(saved) : e.value['json'], 'pending': false};
        await _writeLocalResults(after);
        sent = true;
      } on ApiError catch (err) {
        if (err.status == 0) return (sent, true, refused);
        if (err.status == 401 || err.status >= 500) return (sent, false, refused);
        final after = _localResults()..remove(e.key);
        await _writeLocalResults(after);
        refused.add('Kết quả ${e.key.replaceAll('|', ' ')}: ${err.message}');
      }
    }
    return (sent, false, refused);
  }

  /// One station's result of one day: what is saved on the phone (not yet sent, or the network is down) wins over the server.
  Future<Map<String, dynamic>?> lotteryResult(String date, String station) async {
    final mine = _localResults()[_rk(date, station)];
    if (mine != null && mine['pending'] == true) return Map<String, dynamic>.from(mine['json'] as Map);
    try {
      final (res, _) = await _cachedGetFlag('/lottery-results?date=$date&station=${Uri.encodeQueryComponent(station)}');
      final r = res is Map ? res['result'] : null;
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (e) {
      if (isNetworkError(e) && mine != null) return Map<String, dynamic>.from(mine['json'] as Map);
      rethrow;
    }
  }

  /// All stations' results of one day, keyed by station id (same rules as [lotteryResult]).
  Future<Map<String, Map<String, dynamic>>> dayResults(String date) async {
    final mine = {
      for (final e in _localResults().entries)
        if (e.key.startsWith('$date|')) e.key.substring(date.length + 1): e.value,
    };
    final out = <String, Map<String, dynamic>>{};
    var offlineNoCache = false;
    try {
      final (res, _) = await _cachedGetFlag('/lottery-results?date=$date&all=1');
      for (final r in (res is Map ? res['results'] : null) as List? ?? const []) {
        out[(r as Map)['station'] as String] = Map<String, dynamic>.from(r);
      }
    } catch (e) {
      if (!isNetworkError(e) || mine.isEmpty) rethrow;
      offlineNoCache = true;
    }
    for (final e in mine.entries) {
      if (e.value['pending'] == true || offlineNoCache) out[e.key] = Map<String, dynamic>.from(e.value['json'] as Map);
    }
    return out;
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
      } else if (op.type == 'delete') {
        out = [for (final e in out) if (e.id != op.entryId) e];
      } else if (op.type == 'patch') {
        out = [for (final e in out) e.id == op.entryId ? e.applying(op.payload) : e];
      }
    }
    final pendingIds = pendingOps.where((o) => o.type == 'create' || o.type == 'patch').map((o) => o.entryId).toSet();
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

  // ---- deleting an entry, also offline --------------------------------------------------------------------------

  /// Deletes an entry. Returns true when it was only QUEUED (offline: it disappears from every list now and is deleted on the
  /// server when the network is back), false when the server did it. An entry that never reached the server is just forgotten.
  Future<bool> deleteEntry(String id) async {
    final all = await ops();
    if (all.any((o) => o.type == 'create' && o.entryId == id)) {
      for (final o in all.where((o) => o.entryId == id)) {
        await _delete(o.opId);
      }
      return true;
    }
    if (all.any((o) => o.type == 'delete' && o.entryId == id)) return true;
    try {
      await api.delete('/me/entries/$id');
      await _dropEntryFromCache(id);
      return false;
    } catch (e) {
      if (e is ApiError && e.status == 404) {
        await _dropEntryFromCache(id);
        return false;
      }
      if (!isNetworkError(e)) rethrow;
    }
    for (final o in all.where((o) => o.entryId == id && o.type == 'patch')) {
      await _delete(o.opId); // an edit of something about to be deleted is pointless
    }
    await _put(QueuedOp(opId: _newId(), seq: _nextSeq(), userId: userId, type: 'delete', entryId: id, payload: {}, createdAt: _now().toUtc().toIso8601String()));
    return true;
  }

  Future<void> _dropEntryFromCache(String id) async {
    final cached = _kvGet(_entriesKey);
    if (cached is! List) return;
    await _kvSet(_entriesKey, [for (final j in cached) if (!(j is Map && j['id'] == id)) j]);
  }

  // ---- customers (roster) added / removed offline ---------------------------------------------------------------

  /// Queues a new customer while the network is down. Returns its JSON (a local id, `pending: true`); it shows in the lists
  /// at once (see [overlayCustomers]) and is created on the server when the network is back. A name already in the list is refused.
  Future<Map<String, dynamic>> queueCustomerCreate({required String name, String phone = '', String? defaultStation}) async {
    // the same rule as the server (backend/lib/src/phone.dart), so a phone it would refuse is not queued to be lost later
    final ph = phone.trim();
    if (ph.isNotEmpty && (ph.length > 20 || !RegExp(r'^\+?[\d\s().-]+$').hasMatch(ph) || ph.replaceAll(RegExp(r'\D'), '').length < 6)) {
      throw ApiError(400, 'Số điện thoại không hợp lệ');
    }
    final shown = await cachedGet('/me/customers').catchError((_) => <String, dynamic>{'customers': []});
    final names = [for (final c in (shown is Map ? shown['customers'] as List? : null) ?? const []) '${(c as Map)['name']}'.trim().toLowerCase()];
    if (names.contains(name.trim().toLowerCase())) throw ApiError(409, 'Tên khách hàng này đã có trong danh sách');
    final id = _newId();
    await _put(QueuedOp(
      opId: _newId(),
      seq: _nextSeq(),
      userId: userId,
      type: 'cust-create',
      entryId: id,
      payload: {'name': name.trim(), 'phone': phone.trim(), if (defaultStation != null && defaultStation != 'mb') 'defaultStation': defaultStation},
      createdAt: _now().toUtc().toIso8601String(),
    ));
    return {'id': id, 'name': name.trim(), 'phone': phone.trim(), 'defaultStation': defaultStation == 'mb' ? null : defaultStation, 'pending': true};
  }

  /// Queues removing a customer from the list while offline (a customer that was only queued is simply forgotten).
  Future<void> queueCustomerDelete(String id) async {
    final all = await ops();
    final pendingCreate = all.where((o) => o.type == 'cust-create' && o.entryId == id).firstOrNull;
    if (pendingCreate != null) {
      await _delete(pendingCreate.opId);
      return;
    }
    if (all.any((o) => o.type == 'cust-delete' && o.entryId == id)) return;
    await _put(QueuedOp(opId: _newId(), seq: _nextSeq(), userId: userId, type: 'cust-delete', entryId: id, payload: {}, createdAt: _now().toUtc().toIso8601String()));
  }

  /// `GET /me/customers` with the customers added / removed offline laid over it.
  Future<dynamic> overlayCustomers(dynamic data) async {
    if (data is! Map) return data;
    final pending = (await ops()).where((o) => !o.conflict && (o.type == 'cust-create' || o.type == 'cust-delete')).toList();
    if (pending.isEmpty) return data;
    var list = [for (final c in (data['customers'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];
    for (final op in pending) {
      if (op.type == 'cust-create') {
        final name = '${op.payload['name']}'.toLowerCase();
        if (!list.any((c) => '${c['name']}'.toLowerCase() == name)) {
          list.add({'id': op.entryId, 'name': op.payload['name'], 'phone': op.payload['phone'] ?? '', 'defaultStation': op.payload['defaultStation'], 'scoringRates': null, 'pending': true});
        }
      } else {
        list = [for (final c in list) if ('${c['id']}' != op.entryId) c];
      }
    }
    list.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    return {...data, 'customers': list};
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
          } else if (op.type == 'delete') {
            try {
              await api.delete('/me/entries/${op.entryId}');
            } on ApiError catch (e) {
              if (e.status != 404) rethrow; // already gone: the goal is reached
            }
          } else if (op.type == 'cust-create') {
            try {
              final made = Map<String, dynamic>.from(await api.post('/me/customers', {'name': op.payload['name'], 'phone': op.payload['phone'] ?? ''}) as Map);
              final station = op.payload['defaultStation'];
              if (station is String && station.isNotEmpty) await api.patch('/me/customers/${made['id']}', {'defaultStation': station});
            } on ApiError catch (e) {
              if (e.status != 409) rethrow; // the name already exists on the server: the goal is reached
            }
          } else if (op.type == 'cust-delete') {
            try {
              await api.delete('/me/customers/${op.entryId}');
            } on ApiError catch (e) {
              if (e.status != 404) rethrow;
            }
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
          failures.add(SyncFailure(op.opId, 'Không đồng bộ được "${op.payload['value'] ?? op.payload['name'] ?? (op.type == 'delete' ? 'việc xoá số liệu' : 'việc xoá khách hàng')}": ${err.message}'));
        }
      }
      if (!offline) {
        final (sent, off, refused) = await _flushResults();
        changed = changed || sent;
        offline = off;
        failures.addAll([for (final m in refused) SyncFailure('result', m)]);
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
