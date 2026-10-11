import 'package:flutter/services.dart';

/// Android FLAG_SECURE through the 'vn.mamba/secure' MethodChannel (MainActivity.kt): blocks screenshots, screen
/// recording and hides the app in the recent-apps thumbnail. A no-op where the channel does not exist (tests, iOS).
class ScreenSecure {
  static const channel = MethodChannel('vn.mamba/secure');

  static Future<void> set(bool enabled) async {
    try {
      await channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      /* no native side */
    } on PlatformException {
      /* ignore */
    }
  }
}
