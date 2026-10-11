import 'package:intl/intl.dart';

final _vn = NumberFormat.decimalPattern('vi-VN');

/// 1234567 -> "1.234.567"
String formatNumber(num n) => _vn.format(n);

/// "2026-10-11" -> "11/10/2026"
String viDate(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

/// Today in Vietnam time (UTC+7) as YYYY-MM-DD, like the web app.
String todayIso() {
  final d = DateTime.now().toUtc().add(const Duration(hours: 7));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String isoOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
