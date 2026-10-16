import 'package:flutter/foundation.dart';

/// Nội dung đã đối chiếu trong khung chat, chờ được đưa sang Nhập số (web: sessionStorage `entries-prefill`).
class ChatPrefill {
  const ChatPrefill({required this.text, this.customer = '', this.date = '', this.station = ''});
  final String text;

  /// Tên khách đã chọn ở màn đối chiếu.
  final String customer;

  /// YYYY-MM-DD
  final String date;

  /// 'mb' | 'mt' | 'mn' | id đài
  final String station;
}

/// Chỗ giao nhận một lần: màn đối chiếu `offer`, màn Nhập số `take` (chỉ trong bộ nhớ, không lưu đi đâu).
class ChatPrefillHub extends ChangeNotifier {
  static final ChatPrefillHub instance = ChatPrefillHub();

  ChatPrefill? _pending;
  bool get hasPending => _pending != null;

  void offer(ChatPrefill p) {
    _pending = p;
    notifyListeners();
  }

  ChatPrefill? take() {
    final p = _pending;
    _pending = null;
    return p;
  }
}
