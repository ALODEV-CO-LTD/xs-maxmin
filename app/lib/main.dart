import 'package:flutter/material.dart';

import 'app.dart';
import 'features/account/privacy/screen_secure.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (ScreenSecure.allowCapture) ScreenSecure.set(false); // development builds only
  runApp(const MambaApp());
}
