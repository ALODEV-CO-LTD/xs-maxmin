import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('"Ẩn số liệu" is gone: figures are never hidden, even with an old "on" saved by an earlier version', () async {
    SharedPreferences.setMockInitialValues({'xoso_mask_enabled': true});
    final m = MaskStore();
    expect(m.masked, isFalse);
    await m.load();
    expect(m.masked, isFalse);
    expect((await SharedPreferences.getInstance()).containsKey('xoso_mask_enabled'), isFalse); // the stale setting is cleared
  });
}
