import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'chat_models.dart';
import 'chat_service.dart';

const _scrubFailed = 'Không xử lý được ảnh để xoá thông tin vị trí/thiết bị. Hãy chọn ảnh khác.';
const _maxSide = 2560;

/// Re-encodes a picture so that only the pixels survive (no EXIF / GPS / device / time / colour profile), like the
/// web's canvas redraw (attachments.js `scrubImageMetadata`). The EXIF orientation is applied first. JPEG stays
/// JPEG, PNG stays PNG, WebP becomes PNG (no WebP encoder, same fallback as Safari on the web). Very large photos are
/// scaled down so the result fits the 5 MB limit. Throws an [Exception] with a Vietnamese message.
Future<OutgoingImage> scrubImage(Uint8List bytes) async {
  final type = sniffImageType(bytes);
  if (type == null) throw Exception(imageOnlyMessage);
  if (bytes.isEmpty) throw Exception('Tệp trống');
  final out = await Isolate.run(() => _scrub(bytes, type));
  if (out == null) throw Exception(_scrubFailed);
  return OutgoingImage(out.$1, out.$2);
}

(Uint8List, String)? _scrub(Uint8List bytes, String type) {
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return null;
    image = img.bakeOrientation(image);
    image.exif.clear();
    image.iccProfile = null;
    final outType = type == 'image/jpeg' ? 'image/jpeg' : 'image/png';
    var side = _maxSide;
    for (var attempt = 0; attempt < 4; attempt++) {
      var work = image;
      if (work.width > side || work.height > side) {
        work = work.width >= work.height ? img.copyResize(work, width: side) : img.copyResize(work, height: side);
      }
      final enc = outType == 'image/jpeg' ? img.encodeJpg(work, quality: attempt == 0 ? 92 : 80) : img.encodePng(work);
      if (enc.length <= maxAttachmentBytes) return (Uint8List.fromList(enc), outType);
      side = (side * 0.7).round();
    }
    return null;
  } catch (_) {
    return null;
  }
}
