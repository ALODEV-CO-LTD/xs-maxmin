import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';

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
    // iOS reports a screenshot (taken, even if it comes out blank) through the screen_protector plugin.
    if (Platform.isIOS) ScreenProtector.addListener(() => handle(const MethodCall('screenshot')), (_) {});
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
    if (Platform.isIOS) ScreenProtector.removeListener();
  }

  Future<void> handle(MethodCall call) async {
    if (call.method != 'screenshot' || !isForeground()) return;
    final peer = openPeer();
    if (peer == null || !canNotify(peer)) return;
    sent++;
    await notify(peer);
  }
}
