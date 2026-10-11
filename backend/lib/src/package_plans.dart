import 'package:sqlite3/sqlite3.dart';

/// The four purchasable subscription tiers shown in the user mockup
/// (1/3/6/12 tháng), plus [trial] - the free 30-day period every new
/// account starts on (see [trialDurationDays]/[trialQuota] and
/// `routes/api/auth/register.dart`). `trial` is never purchasable: it is
/// only ever assigned once, at registration.
enum PackageType {
  none,
  trial,
  oneMonth,
  threeMonths,
  sixMonths,
  twelveMonths;

  String get wireValue => switch (this) {
        PackageType.none => 'none',
        PackageType.trial => 'trial',
        PackageType.oneMonth => '1m',
        PackageType.threeMonths => '3m',
        PackageType.sixMonths => '6m',
        PackageType.twelveMonths => '12m',
      };

  String get label => switch (this) {
        PackageType.none => 'Chưa đăng ký',
        PackageType.trial => 'Dùng thử 30 ngày',
        PackageType.oneMonth => '1 tháng',
        PackageType.threeMonths => '3 tháng',
        PackageType.sixMonths => '6 tháng',
        PackageType.twelveMonths => '12 tháng',
      };

  static PackageType fromWire(String value) => PackageType.values.firstWhere(
        (e) => e.wireValue == value,
        orElse: () => PackageType.none,
      );
}

/// The free trial every new account is granted at registration - see
/// `routes/api/auth/register.dart`. After [trialDurationDays] (or after
/// [trialQuota] entries are used, whichever comes first), the account is
/// gated exactly like an expired paid package until the user buys one.
const trialDurationDays = 30;
const trialQuota = 100;

/// Sentinel used as `quota` on every paid plan below - paid packages are
/// unlimited (no real cap on `data_entries`), but `data_quota_total` /
/// `data_used` in the `users` table is an existing, working accounting
/// mechanism (`routes/api/me/entries/index.dart` checks `quotaUsed >=
/// quotaTotal`), so a very large number is a minimal, low-risk way to make
/// that check practically never trigger, instead of ripping the mechanism
/// out. The trial keeps its own real [trialQuota] cap.
const unlimitedQuota = 999999999;

class PackagePlan {
  const PackagePlan({
    required this.type,
    required this.durationDays,
    required this.quota,
    required this.priceVnd,
  });

  final PackageType type;
  final int durationDays;
  final int quota;
  final int priceVnd;
}

/// Default plan catalog - [resolvedPriceVnd] is the source of truth for the
/// actual price to charge/display; it overrides these with whatever price
/// Admin has set via `/api/admin/settings` (key `package_price_<wireValue>`).
final Map<PackageType, PackagePlan> packagePlans = {
  PackageType.oneMonth: const PackagePlan(
    type: PackageType.oneMonth,
    durationDays: 30,
    quota: unlimitedQuota,
    priceVnd: 99000,
  ),
  PackageType.threeMonths: const PackagePlan(
    type: PackageType.threeMonths,
    durationDays: 90,
    quota: unlimitedQuota,
    priceVnd: 269000,
  ),
  PackageType.sixMonths: const PackagePlan(
    type: PackageType.sixMonths,
    durationDays: 180,
    quota: unlimitedQuota,
    priceVnd: 499000,
  ),
  PackageType.twelveMonths: const PackagePlan(
    type: PackageType.twelveMonths,
    durationDays: 365,
    quota: unlimitedQuota,
    priceVnd: 899000,
  ),
};

/// One purchasable package as stored in the `packages` table (Admin can add,
/// edit, hide and delete these - `routes/api/admin/packages`). The defaults in
/// [packagePlans] only seed that table on first run.
class PackageRow {
  const PackageRow({
    required this.code,
    required this.label,
    required this.durationDays,
    required this.priceVnd,
    required this.sortOrder,
    required this.active,
  });

  factory PackageRow.fromRow(Row r) => PackageRow(
        code: r['code'] as String,
        label: r['label'] as String,
        durationDays: r['duration_days'] as int,
        priceVnd: r['price_vnd'] as int,
        sortOrder: r['sort_order'] as int,
        active: (r['active'] as int) == 1,
      );

  final String code;
  final String label;
  final int durationDays;
  final int priceVnd;
  final int sortOrder;
  final bool active;

  Map<String, dynamic> toJson() => {
        'type': code,
        'label': label,
        'durationDays': durationDays,
        'quota': unlimitedQuota,
        'priceVnd': priceVnd,
        'active': active,
        'sortOrder': sortOrder,
      };
}

/// Every package, in display order; [onlyActive] = only those users may buy.
List<PackageRow> listPackages(Database db, {bool onlyActive = false}) => [
      for (final r in db.select(
        'SELECT * FROM packages ${onlyActive ? 'WHERE active = 1 ' : ''}ORDER BY sort_order, duration_days, code',
      ))
        PackageRow.fromRow(r),
    ];

PackageRow? findPackage(Database db, String code) {
  final rows = db.select('SELECT * FROM packages WHERE code = ?', [code]);
  return rows.isEmpty ? null : PackageRow.fromRow(rows.first);
}

/// Display name for a stored `package_type` value: the fixed ones (none/trial),
/// a catalog package's current label, or the raw code if it was since deleted.
String packageLabelOf(Database db, String code) {
  final fixed = PackageType.fromWire(code);
  if (fixed == PackageType.none && code != 'none') {
    return findPackage(db, code)?.label ?? code;
  }
  if (fixed == PackageType.none || fixed == PackageType.trial) return fixed.label;
  return findPackage(db, code)?.label ?? fixed.label;
}
