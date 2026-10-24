import 'dart:convert';
import 'dart:typed_data';

import '../../friends/chat_models.dart' show anonymousName, imageOnlyMessage, maxAttachmentBytes, sniffImageType;

/// Pure logic of the admin support inbox (frontend/src/views/admin/MessagesView.vue + AdminChatPane.vue).

class Conversation {
  const Conversation({
    required this.userId,
    required this.userName,
    required this.username,
    this.packageType,
    this.packageExpiresAt,
    this.awaitingReply = false,
    this.lastMessage = '',
    this.lastMessageAt,
  });
  final String userId;
  final String userName;
  final String username;
  final String? packageType;
  final String? packageExpiresAt;
  final bool awaitingReply;
  final String lastMessage;
  final String? lastMessageAt;

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        userId: '${j['userId'] ?? ''}',
        userName: (j['userName'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        packageType: j['packageType'] as String?,
        packageExpiresAt: j['packageExpiresAt'] as String?,
        awaitingReply: j['awaitingReply'] == true,
        lastMessage: (j['lastMessage'] as String?) ?? '',
        lastMessageAt: j['lastMessageAt'] as String?,
      );
}

class MsgAttachment {
  const MsgAttachment({required this.name, required this.type, required this.size, required this.isImage});
  final String name;
  final String type;
  final int size;
  final bool isImage;
  static MsgAttachment? fromJson(Object? j) {
    if (j is! Map) return null;
    return MsgAttachment(
      name: '${j['name'] ?? 'tệp'}',
      type: '${j['type'] ?? 'application/octet-stream'}',
      size: (j['size'] as num?)?.toInt() ?? 0,
      isImage: j['isImage'] == true,
    );
  }
}

class AdminMsg {
  const AdminMsg({required this.id, required this.fromAdmin, required this.content, required this.createdAt, this.attachment, this.deleted = false});
  final String id;
  final bool fromAdmin;
  final String content;
  final String createdAt;
  final MsgAttachment? attachment;

  /// Admin deleted this reply: both sides see "Tin nhắn đã bị xoá" in its place.
  final bool deleted;
  factory AdminMsg.fromJson(Map<String, dynamic> j) => AdminMsg(
        id: '${j['id'] ?? ''}',
        fromAdmin: j['sender'] == 'admin',
        content: (j['content'] as String?) ?? '',
        createdAt: (j['createdAt'] as String?) ?? '',
        attachment: MsgAttachment.fromJson(j['attachment']),
        deleted: j['deleted'] == true,
      );

  AdminMsg asDeleted() => AdminMsg(id: id, fromAdmin: fromAdmin, content: '', createdAt: createdAt, deleted: true);
}

/// Strips Vietnamese diacritics and lower-cases (MessagesView.vue noAccents).
String noAccents(String? s) => (s ?? '')
    .toLowerCase()
    .replaceAll('đ', 'd')
    .replaceAllMapped(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), (_) => 'a')
    .replaceAllMapped(RegExp(r'[èéẹẻẽêềếệểễ]'), (_) => 'e')
    .replaceAllMapped(RegExp(r'[ìíịỉĩ]'), (_) => 'i')
    .replaceAllMapped(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), (_) => 'o')
    .replaceAllMapped(RegExp(r'[ùúụủũưừứựửữ]'), (_) => 'u')
    .replaceAllMapped(RegExp(r'[ỳýỵỷỹ]'), (_) => 'y');

int awaitingCount(List<Conversation> all) => all.where((c) => c.awaitingReply).length;

/// Newest conversation first (the server already orders it; kept for safety after local edits).
List<Conversation> sortConversations(List<Conversation> all) {
  final out = [...all];
  out.sort((a, b) => (b.lastMessageAt ?? '').compareTo(a.lastMessageAt ?? ''));
  return out;
}

List<Conversation> filterConversations(List<Conversation> all, {String query = '', bool onlyAwaiting = false}) {
  final q = noAccents(query.trim());
  return [
    for (final c in all)
      if ((!onlyAwaiting || c.awaitingReply) && (q.isEmpty || noAccents(c.userName).contains(q) || noAccents(c.username).contains(q))) c,
  ];
}

/// Parses a stored instant (ISO, UTC) to local time; null when unparsable.
DateTime? parseWhen(String? iso) => (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso)?.toLocal();

String _two(int n) => n.toString().padLeft(2, '0');

String timeLabel(String? iso) {
  final d = parseWhen(iso);
  return d == null ? '' : '${_two(d.hour)}:${_two(d.minute)}';
}

/// Conversation-list time: hh:mm today, "Hôm qua", else dd/MM.
String shortTime(String? iso, [DateTime? now]) {
  final d = parseWhen(iso);
  if (d == null) return '';
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return timeLabel(iso);
  if (days == 1) return 'Hôm qua';
  return '${_two(d.day)}/${_two(d.month)}';
}

String dayLabel(String? iso, [DateTime? now]) {
  final d = parseWhen(iso);
  if (d == null) return '';
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Hôm nay';
  if (days == 1) return 'Hôm qua';
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

String expiryLabel(String? iso) {
  final d = parseWhen(iso);
  return d == null ? '' : '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// Thread entries: a day divider (String label) before the first message of each day, else an [AdminMsg].
List<Object> threadItems(List<AdminMsg> msgs, [DateTime? now]) {
  final out = <Object>[];
  String? last;
  for (final m in msgs) {
    final d = parseWhen(m.createdAt);
    final key = d == null ? '' : '${d.year}-${d.month}-${d.day}';
    if (key != last) {
      out.add(dayLabel(m.createdAt, now));
      last = key;
    }
    out.add(m);
  }
  return out;
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String initial(String name) => name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();

/// The `attachment` field of `POST /admin/messages/:userId`: `{name, type, data(base64)}`. The server ignores name and
/// type and re-derives them from the bytes, but the web sends them, so we do too. Bytes must already be scrubbed.
/// Throws [Exception] with a Vietnamese message when not a JPG/PNG/WebP, empty, or over 25 MB.
Map<String, dynamic> buildAttachmentPayload(Uint8List bytes, {String? type, int Function()? byte}) {
  if (bytes.isEmpty) throw Exception('Tệp trống');
  final t = sniffImageType(bytes);
  if (t == null || (type != null && type != t)) throw Exception(imageOnlyMessage);
  if (bytes.length > maxAttachmentBytes) throw Exception('Tệp quá lớn (tối đa 25 MB)');
  return {'name': anonymousName(t, byte), 'type': t, 'data': base64Encode(bytes)};
}

/// Body of the reply request.
Map<String, dynamic> buildReplyBody(String text, Map<String, dynamic>? attachment) => {
      'content': text.trim(),
      'attachment': ?attachment,
    };
