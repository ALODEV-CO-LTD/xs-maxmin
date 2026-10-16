// Logic của màn Đối chiếu (web: ChatDecodeDialog.vue): mỗi tin đã chọn thành các dòng giải mã sửa được; tin gốc không bao giờ đổi.
import 'dart:convert';

import '../entries/message_parser.dart';

/// Tin đã chọn trong khung chat (chỉ cần id và nội dung).
class DecodeSource {
  const DecodeSource(this.id, this.content);
  final String id;
  final String content;
}

class DecodeLine {
  DecodeLine({required this.original, required this.decoded, required this.unknown, String? text}) : text = text ?? decoded;
  final String original;
  String decoded;
  String text;
  final bool unknown;

  /// Dòng đã được sửa tay (khác bản giải mã).
  bool get edited => text != decoded;
}

class DecodeItem {
  DecodeItem(this.id, this.original, this.lines);
  final String id;
  final String original;
  final List<DecodeLine> lines;

  /// Bản sửa lưu trên máy, hoặc null khi không có dòng nào bị sửa (xoá bản đã lưu).
  String? savedJson() => lines.any((l) => l.edited) ? jsonEncode({'original': original, 'lines': [for (final l in lines) l.text]}) : null;
}

typedef DecodeFn = List<DecodedLine> Function(String content);

DecodeFn decoderFor({required List<String> betTypes, Map<String, List<String>>? kindSymbols}) => (content) => decodeMessage(content, betTypes: betTypes, kindSymbols: kindSymbols);

/// Giải mã các tin theo thứ tự đã cho. [savedOf] trả bản sửa đã lưu của một tin (hoặc null); chỉ áp dụng khi cùng tin gốc
/// và cùng số dòng.
Future<List<DecodeItem>> buildDecodeItems(List<DecodeSource> messages, DecodeFn decode, Future<String?> Function(String id) savedOf) async {
  final items = <DecodeItem>[];
  for (final m in messages) {
    final lines = [for (final l in decode(m.content)) DecodeLine(original: l.original, decoded: l.decoded, unknown: l.unknown)];
    final raw = await savedOf(m.id);
    if (raw != null) {
      try {
        final saved = jsonDecode(raw);
        if (saved is Map && saved['original'] == m.content && saved['lines'] is List && (saved['lines'] as List).length == lines.length) {
          final t = saved['lines'] as List;
          for (var i = 0; i < lines.length; i++) {
            lines[i].text = '${t[i]}';
          }
        }
      } catch (_) {/* bản lưu hỏng: bỏ qua */}
    }
    items.add(DecodeItem(m.id, m.content, lines));
  }
  return items;
}

/// "Khôi phục": một dòng về bản giải mã.
void restoreLine(DecodeLine l) => l.text = l.decoded;

/// "Giải mã lại": chạy lại giải mã và bỏ mọi chỗ sửa.
void redecode(List<DecodeItem> items, DecodeFn decode) {
  for (final it in items) {
    final fresh = decode(it.original);
    for (var i = 0; i < it.lines.length; i++) {
      it.lines[i].decoded = i < fresh.length ? fresh[i].decoded : it.lines[i].decoded;
      it.lines[i].text = it.lines[i].decoded;
    }
  }
}

/// Các dòng không rỗng của mọi tin, nối bằng xuống dòng: nội dung chuyển sang Nhập số / Tính toán.
String joinedText(List<DecodeItem> items) => items.expand((it) => it.lines.map((l) => l.text)).where((t) => t.trim().isNotEmpty).join('\n');

bool anyEdited(List<DecodeItem> items) => items.any((it) => it.lines.any((l) => l.edited));
