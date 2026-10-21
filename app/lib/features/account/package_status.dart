import 'me_profile.dart';

/// How the package of the signed-in customer stands.
enum PackageLevel { ok, soon, expired, none }

/// A package with this many days or fewer left is "sắp hết hạn".
const packageSoonDays = 7;

class PackageStatus {
  const PackageStatus(this.level, this.headline, this.detail);
  final PackageLevel level;

  /// "Còn 12 ngày", "Còn 5 giờ 20 phút", "Gói đã hết hạn", "Chưa có gói".
  final String headline;

  /// "Hết hạn: 02/11/2026 14:30" (empty when there is no date).
  final String detail;

  /// Needs the customer's attention (about to run out, ran out, or none).
  bool get needsAction => level != PackageLevel.ok;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// The remaining time as words: days (and hours when 7 or fewer), then hours and minutes, then minutes.
String remainingText(Duration left) {
  if (left.inDays >= 1) {
    final h = left.inHours % 24;
    return left.inDays <= packageSoonDays && h > 0 ? 'Còn ${left.inDays} ngày $h giờ' : 'Còn ${left.inDays} ngày';
  }
  if (left.inHours >= 1) {
    final m = left.inMinutes % 60;
    return m > 0 ? 'Còn ${left.inHours} giờ $m phút' : 'Còn ${left.inHours} giờ';
  }
  final m = left.inMinutes < 1 ? 1 : left.inMinutes;
  return 'Còn $m phút';
}

/// What the Tổng quan card shows for [me] at [now]. The server's `isActive` decides expired / not expired; the date only says how
/// long is left.
PackageStatus packageStatus(MeProfile? me, DateTime now) {
  final label = me?.packageLabel;
  final raw = me?.packageExpiresAt;
  final end = raw == null || raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
  String when(DateTime d) => 'Hết hạn: ${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  if (me == null || end == null) return const PackageStatus(PackageLevel.none, 'Chưa có gói', 'Đăng ký gói để nhập và tính số liệu.');
  final left = end.difference(now);
  if (!me.packageActive || left.isNegative || left == Duration.zero) {
    return PackageStatus(PackageLevel.expired, 'Gói đã hết hạn', '${label == null || label.isEmpty ? '' : '$label · '}${when(end)}');
  }
  final level = left.inDays <= packageSoonDays ? PackageLevel.soon : PackageLevel.ok;
  final name = label == null || label.isEmpty ? '' : '$label · ';
  return PackageStatus(level, remainingText(left), '$name${when(end)}');
}
