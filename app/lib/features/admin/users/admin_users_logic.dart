import 'dart:math';

import 'package:intl/intl.dart';

import '../../../core/admin_session.dart';

/// Rights of the signed-in admin over customer accounts (same split as backend/lib/src/permissions.dart).
class UserRights {
  const UserRights({this.view = false, this.lock = false, this.recovery = false, this.delete = false});
  final bool view, lock, recovery, delete;

  factory UserRights.of(AdminSession s) => UserRights(
        view: s.can('users.view'),
        lock: s.can('users.lock'),
        recovery: s.can('users.recovery'),
        delete: s.can('users.delete'),
      );
}

final _dt = DateFormat('dd/MM/yyyy HH:mm');
final _d = DateFormat('dd/MM/yyyy');

/// ISO instant -> "dd/MM/yyyy HH:mm" in local time, "-" when missing or unparsable.
String fmtDateTime(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  return t == null ? '-' : _dt.format(t.toLocal());
}

String fmtDate(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  return t == null ? '-' : _d.format(t.toLocal());
}

/// One customer as returned by GET /admin/users (and the detail / PATCH answers).
class Subscriber {
  const Subscriber({
    required this.id,
    required this.name,
    required this.username,
    required this.packageType,
    required this.packageLabel,
    required this.expiresAt,
    required this.active,
    required this.locked,
  });

  final String id, name, username, packageType, packageLabel;
  final String? expiresAt;
  final bool active, locked;

  factory Subscriber.fromJson(Map<String, dynamic> j) {
    final pkg = (j['package'] as Map?)?.cast<String, dynamic>() ?? const {};
    final type = '${pkg['type'] ?? ''}';
    return Subscriber(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      username: '${j['username'] ?? ''}',
      packageType: type,
      packageLabel: (pkg['label'] as String?) ?? type,
      expiresAt: pkg['expiresAt'] as String?,
      active: j['status'] == 'active',
      locked: j['accountLocked'] == true,
    );
  }
}

class UsersPage {
  const UsersPage(this.total, this.users);
  final int total;
  final List<Subscriber> users;

  factory UsersPage.fromJson(Map<String, dynamic> j) {
    final list = [for (final s in (j['subscribers'] as List? ?? const [])) Subscriber.fromJson((s as Map).cast<String, dynamic>())];
    return UsersPage((j['total'] as num?)?.toInt() ?? list.length, list);
  }
}

/// The API returns every match at once; this reveals them [pageSize] at a time ("Xem thêm").
class UsersPager {
  UsersPager({this.pageSize = 30});
  final int pageSize;
  List<Subscriber> all = const [];
  int shown = 0;

  void reset(List<Subscriber> items) {
    all = items;
    shown = min(pageSize, items.length);
  }

  List<Subscriber> get visible => all.sublist(0, shown);
  bool get hasMore => shown < all.length;
  void loadMore() => shown = min(shown + pageSize, all.length);

  void replace(Subscriber s) {
    all = [for (final x in all) x.id == s.id ? s : x];
  }

  void remove(String id) {
    all = all.where((x) => x.id != id).toList();
    if (shown > all.length) shown = all.length;
  }
}

class DeviceSession {
  const DeviceSession(this.id, this.label, this.ip, this.lastSeen);
  final String id, label;
  final String? ip, lastSeen;

  factory DeviceSession.fromJson(Map<String, dynamic> j) =>
      DeviceSession('${j['id']}', (j['deviceLabel'] as String?) ?? 'Thiết bị', j['ip'] as String?, j['lastSeen'] as String?);
}

class RecoveryRequest {
  const RecoveryRequest({
    required this.id,
    required this.username,
    required this.name,
    required this.note,
    required this.status,
    required this.ip,
    required this.createdAt,
    required this.registeredAt,
    required this.ticketExpiresAt,
    required this.accountLocked,
  });
  final String id, username, name, note, status;
  final String? ip, createdAt, registeredAt, ticketExpiresAt;
  final bool accountLocked;

  factory RecoveryRequest.fromJson(Map<String, dynamic> j) => RecoveryRequest(
        id: '${j['id']}',
        username: '${j['username'] ?? ''}',
        name: '${j['name'] ?? ''}',
        note: '${j['note'] ?? ''}',
        status: '${j['status'] ?? ''}',
        ip: j['ip'] as String?,
        createdAt: j['createdAt'] as String?,
        registeredAt: j['registeredAt'] as String?,
        ticketExpiresAt: j['ticketExpiresAt'] as String?,
        accountLocked: j['accountLocked'] == true,
      );

  static const statusLabels = {'pending': 'Chờ duyệt', 'approved': 'Đã cấp mã', 'expired': 'Mã hết hạn'};
  String get statusLabel => statusLabels[status] ?? status;
  bool get isPending => status == 'pending';
}

class RecoveryQueue {
  const RecoveryQueue(this.pending, this.requests);
  final int pending;
  final List<RecoveryRequest> requests;

  factory RecoveryQueue.fromJson(Map<String, dynamic> j) {
    final list = [for (final r in (j['requests'] as List? ?? const [])) RecoveryRequest.fromJson((r as Map).cast<String, dynamic>())];
    return RecoveryQueue((j['pending'] as num?)?.toInt() ?? 0, list);
  }
}

/// Random password that passes the server policy (8+ chars, letters and digits, no look-alikes).
String generatePassword([Random? rnd]) {
  final r = rnd ?? Random.secure();
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  const all = letters + digits;
  return String.fromCharCodes([
    for (var i = 0; i < 10; i++) (i == 3 || i == 7 ? digits : all).codeUnitAt(r.nextInt((i == 3 || i == 7 ? digits : all).length)),
  ]);
}

/// The delete confirmation is typed: it must match the account's username (case-insensitive, trimmed).
bool deleteConfirmed(String typed, String username) => typed.trim().isNotEmpty && typed.trim().toLowerCase() == username.toLowerCase();
