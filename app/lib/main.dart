import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'app.dart';
import 'features/account/privacy/screen_secure.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (ScreenSecure.allowCapture) ScreenSecure.set(false); // development builds only
  runApp(const MambaApp());
  // Android sets FLAG_SECURE natively at launch; iOS needs the plugin call (also covers the login screens).
  if (Platform.isIOS) WidgetsBinding.instance.addPostFrameCallback((_) => ScreenSecure.set(true));
}
