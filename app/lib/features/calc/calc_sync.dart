import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// What the sub-tabs of Tính toán share: the customer and day chosen in Nhập số (Tính điểm opens on them, so the person only
/// picks a customer and a day once) and "this tab was just opened" (Tính điểm then re-reads the numbers and the saved lottery
/// results, so what was entered or saved in the other tabs is calculated at once).
class CalcSync extends ChangeNotifier {
  String customer = '';
  String date = '';
  String activeTab = '';
  int activations = 0;

  /// The customer / day currently chosen in Nhập số.
  void select({required String customer, required String date}) {
    if (customer == this.customer && date == this.date) return;
    this.customer = customer;
    this.date = date;
    notifyListeners();
  }

  /// A sub-tab became the visible one.
  void tabActivated(String id) {
    activeTab = id;
    activations++;
    notifyListeners();
  }

  /// The sync of the nearest Tính toán, or null (a screen shown on its own, e.g. in tests).
  static CalcSync? maybeOf(BuildContext context) {
    try {
      return Provider.of<CalcSync>(context, listen: false);
    } catch (_) {
      return null;
    }
  }
}
