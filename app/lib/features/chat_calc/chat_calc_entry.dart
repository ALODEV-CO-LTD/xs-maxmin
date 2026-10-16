// Điểm vào của luồng chat > Đối chiếu > Nhập số / Tính toán. Màn Bạn bè (chọn nhiều tin) gọi hai hàm này.
import 'package:flutter/material.dart';

import '../friends/chat_models.dart';
import 'chat_calc_services.dart';
import 'chat_decode_model.dart';
import 'chat_decode_screen.dart';

/// Màn Đối chiếu của các tin đã chọn ([messages] theo thứ tự hiển thị ban đầu): tin gốc cạnh bản giải mã sửa được, rồi
/// "Dùng cho Nhập số" hoặc "Tính toán".
Future<void> openChatDecode(BuildContext context, {required String friendId, required String friendName, required List<ChatMessage> messages}) =>
    _open(context, friendId: friendId, friendName: friendName, messages: messages, calcFirst: false);

/// Như web, "Tính toán" luôn đi qua màn Đối chiếu (cần chọn khách, ngày, đài và kiểm tra giải mã trước khi tính): màn này
/// mở sẵn ở chế độ tính toán, nút "Tính toán" là nút chính.
Future<void> openChatCalc(BuildContext context, {required String friendId, required String friendName, required List<ChatMessage> messages}) =>
    _open(context, friendId: friendId, friendName: friendName, messages: messages, calcFirst: true);

Future<void> _open(BuildContext context, {required String friendId, required String friendName, required List<ChatMessage> messages, required bool calcFirst}) {
  final services = ChatCalcServices.of(context);
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: const RouteSettings(name: chatCalcRouteName),
      builder: (_) => ChatDecodeScreen(
        services: services,
        friendId: friendId,
        friendName: friendName,
        messages: [for (final m in messages) DecodeSource(m.id, m.text)],
        calcFirst: calcFirst,
      ),
    ),
  );
}
