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
  // Second line of defence for image privacy (K37/K38/S09): the client
  // already redraws images through a canvas, but the client is untrusted, so
  // JPEG/PNG bytes are scrubbed of EXIF/GPS/text metadata here as well -
  // unless the sender explicitly opted to keep the original (`keepMetadata`).
  final keep = raw['keepMetadata'] == true;
  final data = keep ? bytes : stripImageMetadata(bytes);
  return AttachmentParse.ok(ParsedAttachment(name, type, data));
}

/// Removes metadata blocks from a JPEG or PNG (detected by magic bytes, not
/// by the declared type) and returns the cleaned bytes; anything else, or
/// anything that doesn't parse cleanly, is returned untouched.
///   - JPEG: drops every APPn segment except APP0 (JFIF) and APP14 (Adobe
///     colour transform, needed to decode CMYK/YCCK correctly), plus COM
///     comments - this removes EXIF, GPS, XMP, ICC and maker notes.
///   - PNG: drops tEXt/zTXt/iTXt (text), eXIf (EXIF) and tIME (timestamp).
/// Pixel data is never re-encoded, so image quality is unchanged.
Uint8List stripImageMetadata(Uint8List b) {
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) return _stripJpeg(b);
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return _stripPng(b);
  }
  return b;
}

Uint8List _stripJpeg(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var i = 2;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) return b; // malformed - keep original rather than corrupt
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    // Start of scan: the rest is entropy-coded image data up to EOI.
    if (marker == 0xDA) {
      out.add(Uint8List.sublistView(b, i));
      return out.toBytes();
    }
    // Standalone markers (no length): TEM, RSTn, SOI, EOI.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      out.add(Uint8List.sublistView(b, i, i + 2));
      i += 2;
      continue;
    }
    if (i + 3 >= b.length) return b;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return b;
    final isApp = marker >= 0xE0 && marker <= 0xEF;
    final drop = (isApp && marker != 0xE0 && marker != 0xEE) || marker == 0xFE;
    if (!drop) out.add(Uint8List.sublistView(b, i, i + 2 + len));
    i += 2 + len;
  }
  return b; // never reached a scan - not a usable JPEG, leave as-is
}

const _pngDropChunks = {'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME'};

Uint8List _stripPng(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var i = 8;
  while (i + 12 <= b.length) {
    final len = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + len; // length + type + data + CRC
    if (len < 0 || end > b.length) return b;
    final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
    if (!_pngDropChunks.contains(type)) out.add(Uint8List.sublistView(b, i, end));
    i = end;
    if (type == 'IEND') break;
  }
  return out.toBytes();
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
