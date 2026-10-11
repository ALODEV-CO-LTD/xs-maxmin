import 'package:flutter/services.dart';

/// Android 14+ can report screenshots of the app only through native code: MainActivity forwards them on this channel
/// (method `screenshot`). The web warns the friend when it detects a screenshot shortcut; the app does the same
/// with an end-to-end encrypted notice.
const screenshotChannel = MethodChannel('mamba/screenshot');

/// Listens for the native screenshot report at APP scope (the chat page is not needed to be listening) and
/// sends the notice to the friend of the conversation that is open and on screen.
class ScreenshotBridge {
  ScreenshotBridge({required this.openPeer, required this.isForeground, required this.canNotify, required this.notify, MethodChannel? channel}) : _channel = channel ?? screenshotChannel;

  /// The friend whose chat is open right now (null when none).
  final String? Function() openPeer;
  final bool Function() isForeground;

  /// False for Admin accounts: support chats are not end-to-end encrypted friend chats.
  final bool Function(String friendId) canNotify;
  final Future<void> Function(String friendId) notify;
  final MethodChannel _channel;
  bool _attached = false;
  int sent = 0;

  void attach() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler(handle);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
  }

  Future<void> handle(MethodCall call) async {
    if (call.method != 'screenshot' || !isForeground()) return;
    final peer = openPeer();
    if (peer == null || !canNotify(peer)) return;
    sent++;
    await notify(peer);
  }
}
