import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

/// Chat attachments (files and images) live in `direct_messages`
/// (`attachment_name/type/size/data`), so friend chat, the customer's Phản hồi
/// thread and admin replies share one implementation.
const maxAttachmentBytes = 5 * 1024 * 1024;

// Only these may be shown inline (<img>). Anything else - SVG and HTML
// included, both of which can carry script - is always served as a download.
const _inlineImageTypes = {'image/png', 'image/jpeg', 'image/gif', 'image/webp'};

final _mimePattern = RegExp(r'^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$');

class ParsedAttachment {
  ParsedAttachment(this.name, this.type, this.data);
  final String name;
  final String type;
  final Uint8List data;
}

class AttachmentParse {
  AttachmentParse.ok(ParsedAttachment this.attachment) : error = null;
  AttachmentParse.none() : attachment = null, error = null;
  AttachmentParse.fail(String this.error) : attachment = null;
  final ParsedAttachment? attachment;
  final String? error;
}

/// Reads `{name, type, data(base64)}` from a request body field. `null`/absent
/// means "no attachment"; anything malformed or over 5 MB is an error.
AttachmentParse parseAttachment(Object? raw) {
  if (raw == null) return AttachmentParse.none();
  if (raw is! Map) return AttachmentParse.fail('Tệp đính kèm không hợp lệ');

  final data64 = raw['data'];
  if (data64 is! String || data64.isEmpty) {
    return AttachmentParse.fail('Tệp đính kèm trống');
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(data64);
  } on FormatException {
    return AttachmentParse.fail('Tệp đính kèm không hợp lệ');
  }
  if (bytes.isEmpty) return AttachmentParse.fail('Tệp đính kèm trống');
  if (bytes.length > maxAttachmentBytes) {
    return AttachmentParse.fail('Tệp quá lớn (tối đa 5 MB)');
  }

  var name = (raw['name'] as String? ?? '').trim();
  // Keep only the base name, drop control characters, cap the length.
  name = name.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
  if (name.length > 200) name = name.substring(name.length - 200);
  if (name.isEmpty) name = 'tep-dinh-kem';

  var type = (raw['type'] as String? ?? '').trim().toLowerCase();
  if (type.length > 100 || !_mimePattern.hasMatch(type)) {
    type = 'application/octet-stream';
  }
  return AttachmentParse.ok(ParsedAttachment(name, type, bytes));
}

/// JSON shape returned with a message (never the bytes themselves).
Map<String, dynamic>? attachmentMeta(Row r) {
  final name = r['attachment_name'];
  if (name == null) return null;
  final type = r['attachment_type'] as String? ?? 'application/octet-stream';
  return {
    'name': name,
    'type': type,
    'size': r['attachment_size'],
    'isImage': _inlineImageTypes.contains(type),
  };
}

/// Streams the stored bytes: images inline, everything else as a download.
Response attachmentResponse(Row r) {
  final data = r['attachment_data'];
  if (r['attachment_name'] == null || data is! List<int>) {
    return Response.json(
      statusCode: 404,
      body: {'error': 'Không có tệp đính kèm'},
    );
  }
  final name = r['attachment_name'] as String;
  final type = r['attachment_type'] as String? ?? 'application/octet-stream';
  final inline = _inlineImageTypes.contains(type);
  final ascii = name.replaceAll(RegExp(r'[^\x20-\x7e]'), '_').replaceAll('"', '_');
  final encoded = Uri.encodeComponent(name);
  return Response.bytes(
    body: data,
    headers: {
      'content-type': inline ? type : 'application/octet-stream',
      'content-disposition':
          '${inline ? 'inline' : 'attachment'}; filename="$ascii"; filename*=UTF-8\'\'$encoded',
      'x-content-type-options': 'nosniff',
      'cache-control': 'private, max-age=3600',
    },
  );
}
