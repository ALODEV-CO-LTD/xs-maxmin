// Các nguồn dữ liệu của luồng chat > Đối chiếu > Tính toán, tách ra để thử được không cần mạng.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../friends/chat_models.dart';
import '../friends/chat_service.dart';
import '../friends/messaging_host.dart';
import '../scoring/entry_model.dart';
import '../scoring/scoring_data.dart';
import '../scoring/scoring_logic.dart';

/// Dữ liệu của tài khoản (chạy được offline từ bản đã lưu trên máy).
abstract class ChatCalcData {
  Future<List<CustomerRec>> customers();
  Future<RatesMap> accountRates();

  /// Danh mục đài (lịch quay theo ngày); offline thì dùng bản đã lưu hoặc chỉ Miền Bắc.
  Future<void> loadStations();

  /// Kết quả xổ số của ĐÚNG đài và ngày của tài khoản, hoặc null.
  Future<LotteryResult?> result(String date, String station);
}

class ApiChatCalcData implements ChatCalcData {
  ApiChatCalcData(this.api, this.stations);
  final ApiClient api;
  final LotteryStations stations;
  @override
  Future<void> loadStations() => stations.load(api);
  @override
  Future<List<CustomerRec>> customers() => fetchCustomers(api);
  @override
  Future<RatesMap> accountRates() => fetchAccountRates(api);
  @override
  Future<LotteryResult?> result(String date, String station) => fetchLotteryResult(api, date, station);
}

/// Bộ nhớ nhỏ trên máy này (web: chat.metaGet/metaSet) cho bản sửa giải mã và báo cáo đã lưu.
abstract class ChatMeta {
  Future<String?> get(String key);
  Future<void> set(String key, String? value);
}

class MemoryChatMeta implements ChatMeta {
  final Map<String, String> data = {};
  @override
  Future<String?> get(String key) async => data[key];
  @override
  Future<void> set(String key, String? value) async => value == null ? data.remove(key) : data[key] = value;
}

class _ServiceMeta implements ChatMeta {
  _ServiceMeta(this.chat);
  final ChatService chat;
  @override
  Future<String?> get(String key) => chat.store.meta(key);
  @override
  Future<void> set(String key, String? value) => chat.store.setMeta(key, value);
}

/// Gửi văn bản cho một người bạn qua chat mã hoá đầu cuối. Trả về câu thông báo kết quả; `ok` = đã đi (chưa chắc đã tới).
abstract class ChatSender {
  Future<({bool ok, String message})> send(String friendId, String text);
}

class _ServiceSender implements ChatSender {
  _ServiceSender(this.chat);
  final ChatService chat;
  @override
  Future<({bool ok, String message})> send(String friendId, String text) async {
    try {
      final m = await chat.send(friendId, text);
      final now = (await chat.messages(friendId)).where((x) => x.id == m.id).firstOrNull;
      if (now?.status == MsgStatus.failed) {
        return (ok: false, message: 'Chưa gửi được: ${reasonText(now?.reason).replaceAll(RegExp(r'\.$'), '')}. Tin nằm trong cuộc trò chuyện, có nút Gửi lại.');
      }
      return (ok: true, message: 'Đã gửi báo cáo. Nếu bạn bè đang offline, cuộc trò chuyện sẽ báo lỗi và có nút Gửi lại.');
    } catch (e) {
      return (ok: false, message: e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Không gửi được báo cáo.');
    }
  }
}

class ChatCalcServices {
  ChatCalcServices({required this.data, required this.meta, required this.sender, required this.stations});
  final ChatCalcData data;
  final ChatMeta meta;
  final ChatSender? sender;
  final LotteryStations stations;

  /// Từ ngữ cảnh của app: API, danh mục đài, và (nếu đã sẵn sàng) chat mã hoá của tài khoản.
  factory ChatCalcServices.of(BuildContext context) {
    final chat = MessagingScope.maybeOf(context)?.chat;
    return ChatCalcServices(
      data: ApiChatCalcData(context.read<ApiClient>(), context.read<LotteryStations>()),
      meta: chat == null ? MemoryChatMeta() : _ServiceMeta(chat),
      sender: chat == null ? null : _ServiceSender(chat),
      stations: context.read<LotteryStations>(),
    );
  }
}

List<Map<String, dynamic>> decodeIndex(String? raw) {
  if (raw == null) return [];
  try {
    final v = jsonDecode(raw);
    return v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : [];
  } catch (_) {
    return [];
  }
}
