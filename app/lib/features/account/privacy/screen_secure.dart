import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';

/// Android FLAG_SECURE through the 'vn.mamba/secure' MethodChannel (MainActivity.kt): blocks screenshots, screen
/// recording and hides the app in the recent-apps thumbnail. A no-op where the channel does not exist (tests, iOS).
class ScreenSecure {
  static const channel = MethodChannel('vn.mamba/secure');

  /// Development only: `flutter run --dart-define=ALLOW_CAPTURE=true` keeps the screen capturable (adb screencap,
  /// screenshots for bug reports). Release builds never set it.
  static const allowCapture = bool.fromEnvironment('ALLOW_CAPTURE');

  /// iOS has no FLAG_SECURE. `screen_protector` renders the app inside a secure layer so screenshots and screen
  /// recordings come out blank (iOS 13+), and covers the app-switcher thumbnail with a blur.
  static Future<void> _setIos(bool enabled) async {
    try {
      if (enabled) {
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageWithBlur();
      } else {
        await ScreenProtector.preventScreenshotOff();
        await ScreenProtector.protectDataLeakageWithBlurOff();
      }
    } on MissingPluginException {
      /* no native side (tests) */
    } on PlatformException {
      /* ignore */
    }
  }

  static Future<void> set(bool enabled) async {
    if (allowCapture) enabled = false;
    if (Platform.isIOS) return _setIos(enabled);
    try {
      await channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on MissingPluginException {
      /* no native side */
    } on PlatformException {
      /* ignore */
    }
  }
}
