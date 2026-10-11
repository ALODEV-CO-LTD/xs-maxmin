import 'package:flutter/services.dart';

/// Android FLAG_SECURE through the 'vn.mamba/secure' MethodChannel (MainActivity.kt): blocks screenshots, screen
/// recording and hides the app in the recent-apps thumbnail. A no-op where the channel does not exist (tests, iOS).
class ScreenSecure {
  static const channel = MethodChannel('vn.mamba/secure');

  /// Development only: `flutter run --dart-define=ALLOW_CAPTURE=true` keeps the screen capturable (adb screencap,
  /// screenshots for bug reports). Release builds never set it.
  static const allowCapture = bool.fromEnvironment('ALLOW_CAPTURE');

  static Future<void> set(bool enabled) async {
    if (allowCapture) enabled = false;
    try {
      await channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      /* no native side */
    } on PlatformException {
      /* ignore */
    }
  }
}
