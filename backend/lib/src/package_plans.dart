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

/// The price to actually charge/show for [type] - Admin's override from
/// `settings.package_price_<wireValue>` if one exists, else the hardcoded
/// default above. This is the single place that decision is made; every
/// caller (purchase, the public catalog, transaction amount) must go
/// through this instead of reading `packagePlans[type]!.priceVnd` directly.
int resolvedPriceVnd(Database db, PackageType type) {
  final plan = packagePlans[type]!;
  final rows = db.select(
    'SELECT value FROM settings WHERE key = ?',
    ['package_price_${type.wireValue}'],
  );
  if (rows.isEmpty) return plan.priceVnd;
  return int.tryParse(rows.first['value'] as String) ?? plan.priceVnd;
}
