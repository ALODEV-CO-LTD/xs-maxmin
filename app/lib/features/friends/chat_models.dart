import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

/// Message status as in e2ee/chat.js: sending -> sent (relayed) -> delivered (friend's ack) | failed.
class MsgStatus {
  static const sending = 'sending';
  static const sent = 'sent';
  static const delivered = 'delivered';
  static const failed = 'failed';
}

/// System lines kept in the history: `screenshot` (the friend took one), `screenshot-sent` (we did, and told them).
class SysKind {
  static const screenshot = 'screenshot';
  static const screenshotSent = 'screenshot-sent';
}

const allowedImageTypes = ['image/jpeg', 'image/png', 'image/webp'];
const imageOnlyMessage = 'Chỉ gửi được ảnh JPG, PNG hoặc WebP (không gửi GIF hay tệp khác)';
const maxAttachmentBytes = 5 * 1024 * 1024;

/// Human text for the failure reasons the relay / client can report (e2ee/chat.js REASONS).
const failReasons = {
  'offline': 'Bạn bè đang offline, tin nhắn chưa được gửi. Hãy gửi lại khi họ trực tuyến.',
  'not-friend': 'Không còn là bạn bè nên không gửi được.',
  'invalid': 'Tin nhắn không hợp lệ.',
  'no-key': 'Bạn bè chưa bật mã hoá 2 đầu (chưa mở phiên bản mới), chưa gửi được.',
  'no-socket': 'Mất kết nối tới máy chủ, thử lại sau.',
  'timeout': 'Không nhận được xác nhận, tin nhắn có thể chưa tới.',
};
String reasonText(String? reason) => failReasons[reason] ?? 'Chưa gửi được.';

class ChatAttachment {
  const ChatAttachment({required this.name, required this.type, required this.size, this.path});
  final String name;
  final String type;
  final int size;

  /// Local file with the decrypted bytes (never uploaded anywhere).
  final String? path;
  bool get isImage => type.startsWith('image/') && type != 'image/svg+xml';
}

/// A group conversation has the id `g-<random>` (the same key every per-conversation thing uses: messages, unread, pins, ...).
const groupIdPrefix = 'g-';
bool isGroupId(String id) => id.startsWith(groupIdPrefix);

/// A member of a group: the account id and the name the group was created with.
class GroupMember {
  const GroupMember(this.id, this.name);
  final String id;
  final String name;
}

/// A group chat. It lives only on the devices of its members (the server stores nothing): the creator sends the first message with
/// the group's name and members, and every group message carries them again, so a device that missed the first one still learns the group.
class ChatGroup {
  const ChatGroup({required this.id, required this.name, required this.members, required this.creatorId, required this.updatedAt});
  final String id; // g-<random>
  final String name;
  final List<GroupMember> members; // everyone, the creator included
  final String creatorId;
  final int updatedAt;

  String get convId => id;

  Map<String, dynamic> toHeader() => {
        'i': id,
        'n': name,
        'c': creatorId,
        'u': updatedAt,
        'm': [for (final m in members) [m.id, m.name]],
      };

  String toJson() => jsonEncode(toHeader());

  static ChatGroup? fromHeader(Object? h) {
    if (h is! Map) return null;
    final id = h['i'];
    final name = h['n'];
    final c = h['c'];
    final m = h['m'];
    if (id is! String || !isGroupId(id) || id.length > 64 || name is! String || c is! String || m is! List) return null;
    final members = <GroupMember>[];
    for (final x in m) {
      if (x is List && x.length >= 2 && x[0] is String && x[1] is String) members.add(GroupMember(x[0] as String, (x[1] as String).length > 80 ? (x[1] as String).substring(0, 80) : x[1] as String));
    }
    if (members.length < 2 || members.length > 50) return null;
    final u = h['u'];
    return ChatGroup(id: id, name: name.length > 60 ? name.substring(0, 60) : name, members: members, creatorId: c, updatedAt: u is num ? u.toInt() : 0);
  }

  static ChatGroup? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromHeader(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  ChatGroup copyWith({String? name, List<GroupMember>? members, int? updatedAt}) => ChatGroup(id: id, name: name ?? this.name, members: members ?? this.members, creatorId: creatorId, updatedAt: updatedAt ?? this.updatedAt);
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerId,
    required this.mine,
    required this.text,
    required this.createdAt,
    required this.status,
    this.att,
    this.sys,
    this.reason,
    this.fromId,
  });
  final String id;
  final String peerId;
  final bool mine;
  final String text;
  final int createdAt;
  final String status;
  final ChatAttachment? att;
  final String? sys;
  final String? reason;

  /// Who wrote it (account id); set on group messages, where [mine] alone does not say who spoke.
  final String? fromId;

  ChatMessage copyWith({String? status, String? reason, bool clearReason = false}) => ChatMessage(
        id: id,
        peerId: peerId,
        mine: mine,
        text: text,
        createdAt: createdAt,
        status: status ?? this.status,
        att: att,
        sys: sys,
        reason: clearReason ? null : (reason ?? this.reason),
        fromId: fromId,
      );

  /// Text for the friend-list preview (chat.js `previews`).
  String get preview => sys != null ? '📷 Chụp màn hình cuộc trò chuyện' : (text.isNotEmpty ? text : (att != null ? '[Đính kèm] ${att!.name}' : ''));
}

// ---- reply quotes (FriendsView.vue: REPLY_MARK / quoteOf / quoteText) -------------------------------------------
// A reply travels as plain text inside the encrypted message: `↪ <quote>\n<body>`. No extra field, so web and app (and
// old messages) understand each other.

const replyMark = '↪ ';

/// Splits a message into its quoted line and the real text (web `quoteOf`). No quote line => quote is empty.
({String quote, String body}) quoteOf(String? content) {
  final text = content ?? '';
  final lines = text.split('\n');
  final first = lines.first;
  if (!first.startsWith(replyMark) || lines.length < 2) return (quote: '', body: text);
  return (quote: first.substring(replyMark.length), body: lines.sublist(1).join('\n'));
}

/// Short text shown when quoting [m] (web `quoteText`): its text without quote lines, or "[Ảnh]", at most 60 characters.
String quoteText(ChatMessage m) {
  final raw = m.text.isNotEmpty ? m.text : (m.att != null ? '[Ảnh]' : '');
  var s = raw.split('\n').where((l) => !l.startsWith(replyMark)).join(' ');
  if (s.length > 60) {
    var end = 60;
    if (s.codeUnitAt(end - 1) >= 0xD800 && s.codeUnitAt(end - 1) <= 0xDBFF) end--; // do not cut a surrogate pair
    s = s.substring(0, end);
  }
  return s;
}

/// The text to send when answering [replyTo] with [content] (web `sendMessage`).
String composeReply(ChatMessage? replyTo, String content) => replyTo == null ? content : '$replyMark${quoteText(replyTo)}\n$content';

/// The last public key we saw for a friend, its fingerprint and whether it changed since we last accepted it.
class PeerRecord {
  const PeerRecord({required this.id, required this.jwk, required this.fingerprint, required this.changed});
  final String id;
  final Map<String, dynamic> jwk;
  final String fingerprint;
  final bool changed;
}

class PeerInfo {
  const PeerInfo({required this.fingerprint, required this.changed});
  final String fingerprint;
  final bool changed;
}

// ---- auto-delete (ChatRetentionPanel.vue) ------------------------------------------------------------------------

const retentionTtls = <int, String>{3600: '1 giờ', 86400: '1 ngày', 604800: '7 ngày', 2592000: '30 ngày'};

/// "Delete messages older than [ttlSeconds]" on THIS device; [scope] is `all` or `images` (only pictures).
class RetentionRule {
  const RetentionRule(this.ttlSeconds, this.scope);
  final int ttlSeconds;
  final String scope;

  String toJson() => jsonEncode({'ttlSeconds': ttlSeconds, 'scope': scope});

  static RetentionRule? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ttl = m['ttlSeconds'];
      if (ttl is! num || ttl <= 0) return null;
      return RetentionRule(ttl.toInt(), m['scope'] == 'images' ? 'images' : 'all');
    } catch (_) {
      return null;
    }
  }

  String get ttlLabel => retentionTtls[ttlSeconds] ?? '${(ttlSeconds / 3600).round()} giờ';
  String get describe => 'Tự xoá ${scope == 'images' ? 'ảnh' : 'tin nhắn'} cũ hơn $ttlLabel (trên thiết bị này)';
}

/// Messages [rule] deletes at [nowMs]: older than the cutoff; with scope `images` only pictures are removed.
List<ChatMessage> expiredMessages(Iterable<ChatMessage> messages, RetentionRule rule, int nowMs) {
  final cutoff = nowMs - rule.ttlSeconds * 1000;
  return [
    for (final m in messages)
      if (m.createdAt < cutoff && !(rule.scope == 'images' && !(m.att?.isImage ?? false))) m,
  ];
}

// ---- WebSocket frames --------------------------------------------------------------------------------------------

/// One `e2ee-msg` frame (a message is split in up to [maxParts] parts of [partChars] ciphertext characters).
const partChars = 1000000;
const maxParts = 8;

class E2eeFrame {
  E2eeFrame({required this.id, required this.from, required this.fromName, required this.iv, required this.ct, required this.part, required this.parts, this.ts});
  final String id;
  final String from;
  final String? fromName;
  final String iv;
  final String ct;
  final int part;
  final int parts;
  final int? ts;

  static E2eeFrame? tryParse(Map<String, dynamic> m) {
    final id = m['id'];
    final from = m['from'];
    final iv = m['iv'];
    final ct = m['ct'];
    final part = m['part'] ?? 0;
    final parts = m['parts'] ?? 1;
    if (id is! String || from is! String || iv is! String || ct is! String || part is! int || parts is! int) return null;
    if (parts < 1 || parts > maxParts || part < 0 || part >= parts) return null;
    return E2eeFrame(id: id, from: from, fromName: m['fromName'] as String?, iv: iv, ct: ct, part: part, parts: parts, ts: m['ts'] is int ? m['ts'] as int : null);
  }

  E2eeFrame withCt(String joined) => E2eeFrame(id: id, from: from, fromName: fromName, iv: iv, ct: joined, part: 0, parts: 1, ts: ts);
}

/// Splits ciphertext into relay frames' `ct` slices.
List<String> splitCiphertext(String ct) {
  final n = ct.isEmpty ? 1 : (ct.length + partChars - 1) ~/ partChars;
  return [for (var i = 0; i < n; i++) ct.substring(i * partChars, ((i + 1) * partChars).clamp(0, ct.length))];
}

/// Puts the parts of one message back together (chat.js `_assemble`). Returns the whole frame once complete, else null.
class PartAssembler {
  PartAssembler({this.maxAge = const Duration(seconds: 60), DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Duration maxAge;
  final DateTime Function() _now;
  final Map<String, _Partial> _open = {};

  E2eeFrame? add(E2eeFrame f) {
    if (f.parts == 1) return f;
    final cutoff = _now().subtract(maxAge);
    _open.removeWhere((_, v) => v.at.isBefore(cutoff));
    final e = _open.putIfAbsent(f.id, () => _Partial(f.parts, _now()));
    if (e.parts.length != f.parts || e.parts[f.part] != null) return null;
    e.parts[f.part] = f.ct;
    e.got++;
    if (e.got < f.parts) return null;
    _open.remove(f.id);
    return f.withCt(e.parts.join());
  }
}

class _Partial {
  _Partial(int n, this.at) : parts = List<String?>.filled(n, null);
  final List<String?> parts;
  final DateTime at;
  int got = 0;
}

/// Detects the image type from magic bytes (the picker's mime type is not trusted).
String? sniffImageType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return 'image/jpeg';
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) return 'image/png';
  if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'image/webp';
  return null;
}

String imageExt(String type) => switch (type) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };

/// `anh-<10 hex>.<ext>`: attachments are always renamed (the original name can hold a date or device).
String anonymousName(String type, [int Function()? byte]) {
  final b = byte ?? (() => DateTime.now().microsecondsSinceEpoch & 0xff);
  final hex = List.generate(5, (_) => b().toRadixString(16).padLeft(2, '0')).join();
  return 'anh-$hex.${imageExt(type)}';
}

/// Time shown at the right of a conversation row: HH:mm today, "Hôm qua", dd/MM this year, dd/MM/yy before. Empty when there is no message.
String chatListTime(int ms, DateTime now) {
  if (ms <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '${two(t.hour)}:${two(t.minute)}';
  if (diff == 1) return 'Hôm qua';
  if (t.year == now.year) return '${two(t.day)}/${two(t.month)}';
  return '${two(t.day)}/${two(t.month)}/${two(t.year % 100)}';
}

/// Avatar colour from the name (stable, a few calm colours, white letter on top).
Color avatarColor(String name) {
  const palette = [Color(0xFF4CAF7A), Color(0xFF5B8DEF), Color(0xFFE0885B), Color(0xFFB06AB3), Color(0xFF3FA7B5), Color(0xFFC9973A), Color(0xFF7A8FA6)];
  var h = 0;
  for (final u in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return palette[h % palette.length];
}
