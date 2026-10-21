import 'package:flutter/foundation.dart';

/// "The customer's package may have changed" (Admin decided a payment request): screens that show the package read it again.
class PackageEvents extends ChangeNotifier {
  PackageEvents._();
  static final PackageEvents instance = PackageEvents._();

  int tick = 0;

  void bump() {
    tick++;
    notifyListeners();
  }
}
