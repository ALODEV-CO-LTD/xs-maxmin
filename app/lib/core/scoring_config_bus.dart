import 'package:flutter/foundation.dart';

import 'scoring_config.dart';

/// Tells the screens that keep their own copy of the account-wide scoring config (Khách hàng) that the default config was
/// saved in the Cấu hình tab.
class ScoringConfigBus extends ChangeNotifier {
  RatesMap? rates;
  void publish(RatesMap saved) {
    rates = saved;
    notifyListeners();
  }
}
