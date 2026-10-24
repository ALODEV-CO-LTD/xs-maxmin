import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

/// Chat attachments (images only: JPEG, PNG, WebP) live in `direct_messages`
/// (`attachment_name/type/size/data`), so friend chat, the customer's Phản hồi
/// thread and admin replies share one implementation.
const maxAttachmentBytes = 25 * 1024 * 1024;

// Only these may be shown inline (<img>). Anything else - SVG and HTML
// included, both of which can carry script - is always served as a download.
const _inlineImageTypes = {'image/png', 'image/jpeg', 'image/gif', 'image/webp'};

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

/// Reads `{data(base64)}` (name/type are ignored) from a request body field. `null`/absent
/// means "no attachment"; anything that is not a clean JPEG/PNG/WebP, or is over 25 MB, is an error.
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
    return AttachmentParse.fail('Tệp quá lớn (tối đa 25 MB)');
  }

  // Only images are accepted (K37/K38/S09). The client is untrusted, so everything the
  // sender declares is ignored: the kind comes from the magic bytes, the picture is
  // rebuilt keeping ONLY what is needed to display it (EXIF/GPS/device/time, text,
  // comments, colour profiles, thumbnails and trailing data are all dropped), and
  // the file name is replaced by a random one (the original often holds a date or
  // device). GIFs and every other file type are refused: they can carry an author,
  // device or creation time that cannot be reliably removed. Fail closed: a file that
  // does not parse cleanly is refused, never stored as-is.
  final kind = imageKind(bytes);
  if (kind == null) {
    return AttachmentParse.fail('Chỉ gửi được ảnh JPG, PNG hoặc WebP (không gửi GIF hay tệp khác)');
  }
  final cleaned = sanitizeImage(bytes);
  if (cleaned == null) {
    return AttachmentParse.fail('Ảnh không hợp lệ hoặc bị hỏng, hãy chọn ảnh khác');
  }
  final ext = kind == 'jpeg' ? 'jpg' : kind;
  return AttachmentParse.ok(ParsedAttachment('anh-${_randomHex(5)}.$ext', 'image/$kind', cleaned));
}

String _randomHex(int bytes) {
  final rng = Random.secure();
  return List.generate(bytes, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// 'jpeg' | 'png' | 'webp' from the magic bytes, or null for anything else.
String? imageKind(Uint8List b) {
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) {
    return 'png';
  }
  if (b.length > 12 && _fourCC(b, 0) == 'RIFF' && _fourCC(b, 8) == 'WEBP') return 'webp';
  return null;
}

String _fourCC(Uint8List b, int i) => String.fromCharCodes(b.sublist(i, i + 4));

/// Rebuilds a JPEG, PNG or WebP keeping only the chunks needed to display it;
/// null when the file is not a well-formed image of one of those kinds.
Uint8List? sanitizeImage(Uint8List b) {
  try {
    return switch (imageKind(b)) {
      'jpeg' => _sanitizeJpeg(b),
      'png' => _sanitizePng(b),
      'webp' => _sanitizeWebp(b),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// JPEG: keep only the segments that describe/encode the picture (quantisation and Huffman
/// tables, frame headers, restart interval, scan headers, Adobe colour-transform flag) and the
/// entropy-coded data; drop every APPn (EXIF, XMP, ICC, JFIF thumbnails, maker notes), comments
/// and anything after the end-of-image marker.
Uint8List? _sanitizeJpeg(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var i = 2;
  var sawScan = false;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
      continue;
    }
    if (marker == 0xD9) {
      // EOI: finished; whatever follows (hidden data, MPF thumbnails) is dropped.
      if (!sawScan) return null;
      out.add(const [0xFF, 0xD9]);
      return out.toBytes();
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      if (marker == 0xD8) return null; // a second SOI
      i += 2;
      continue;
    }
    if (i + 3 >= b.length) return null;
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2 || i + 2 + len > b.length) return null;
    final isApp = marker >= 0xE0 && marker <= 0xEF;
    final isAdobe = marker == 0xEE && len >= 7 && String.fromCharCodes(b.sublist(i + 4, i + 9)) == 'Adobe';
    final keep = (!isApp && marker != 0xFE) || isAdobe;
    if (keep) out.add(Uint8List.sublistView(b, i, i + 2 + len));
    i += 2 + len;
    if (marker == 0xDA) {
      // Scan data: copy up to the next real marker (FF followed by neither 00 nor RSTn).
      sawScan = true;
      final start = i;
      while (i + 1 < b.length) {
        if (b[i] == 0xFF && b[i + 1] != 0x00 && !(b[i + 1] >= 0xD0 && b[i + 1] <= 0xD7) && b[i + 1] != 0xFF) break;
        i++;
      }
      out.add(Uint8List.sublistView(b, start, i));
    }
  }
  return null; // no EOI: truncated
}

/// PNG: keep the critical chunks, transparency and gamma/colour numbers, and the animation
/// chunks of an APNG; drop text (tEXt/zTXt/iTXt), EXIF, time, ICC profile, physical size and
/// anything else, including data after IEND.
const _pngKeep = {'IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'sBIT', 'acTL', 'fcTL', 'fdAT'};

Uint8List? _sanitizePng(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var i = 8;
  var first = true;
  var sawData = false;
  while (i + 12 <= b.length) {
    final len = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + len; // length + type + data + CRC
    if (len < 0 || end > b.length) return null;
    final type = _fourCC(b, i + 4);
    if (first && type != 'IHDR') return null;
    first = false;
    if (type == 'IDAT') sawData = true;
    if (_pngKeep.contains(type)) out.add(Uint8List.sublistView(b, i, end));
    i = end;
    if (type == 'IEND') return sawData ? out.toBytes() : null;
  }
  return null;
}

/// WebP: keep the picture chunks (VP8, VP8L, ALPH, animation ANIM/ANMF) and the VP8X header with
/// its ICC/EXIF/XMP flags cleared; drop EXIF, XMP, ICCP and unknown chunks, and rebuild the size.
const _webpKeep = {'VP8 ', 'VP8L', 'VP8X', 'ALPH', 'ANIM', 'ANMF'};

Uint8List? _sanitizeWebp(Uint8List b) {
  final riffSize = b[4] | (b[5] << 8) | (b[6] << 16) | (b[7] << 24);
  final limit = (riffSize + 8) < b.length ? riffSize + 8 : b.length;
  final body = BytesBuilder(copy: false)..add(const [0x57, 0x45, 0x42, 0x50]); // 'WEBP'
  var i = 12;
  var sawPicture = false;
  while (i + 8 <= limit) {
    final type = _fourCC(b, i);
    final size = b[i + 4] | (b[i + 5] << 8) | (b[i + 6] << 16) | (b[i + 7] << 24);
    final padded = size + (size & 1);
    if (size < 0 || i + 8 + padded > b.length) return null;
    if (_webpKeep.contains(type)) {
      final chunk = Uint8List.fromList(b.sublist(i, i + 8 + padded));
      if (type == 'VP8X') {
        if (size < 10) return null;
        chunk[8] &= ~(0x20 | 0x08 | 0x04); // ICC profile, EXIF, XMP flags
      }
      if (type == 'VP8 ' || type == 'VP8L' || type == 'ANMF') sawPicture = true;
      body.add(chunk);
    }
    i += 8 + padded;
  }
  if (!sawPicture) return null;
  final payload = body.toBytes();
  final out = BytesBuilder(copy: false)
    ..add(const [0x52, 0x49, 0x46, 0x46]) // 'RIFF'
    ..add([payload.length & 0xFF, (payload.length >> 8) & 0xFF, (payload.length >> 16) & 0xFF, (payload.length >> 24) & 0xFF])
    ..add(payload);
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
