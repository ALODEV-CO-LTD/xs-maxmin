import '../../core/scoring_config.dart';

/// One row of `GET /me/customers`.
class Customer {
  Customer({required this.id, required this.name, this.phone = '', this.scoringRates, this.defaultStation, this.createdAt});

  final String id;
  String name;
  String phone;

  /// The customer's own payout overrides (null = follow the account's settings). May hold `{disabled: true}` markers.
  RatesMap? scoringRates;

  /// 'mt' / 'mn' / a station id; null = Miền Bắc.
  String? defaultStation;
  String? createdAt;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        scoringRates: j['scoringRates'] is Map ? Map<String, dynamic>.from(j['scoringRates'] as Map) : null,
        defaultStation: j['defaultStation'] is String && (j['defaultStation'] as String).isNotEmpty ? j['defaultStation'] as String : null,
        createdAt: j['createdAt'] as String?,
      );

  String get stationCode => (defaultStation == null || defaultStation!.isEmpty) ? 'mb' : defaultStation!;
}

List<Customer> parseCustomers(dynamic res) {
  final list = res is Map ? res['customers'] : null;
  if (list is! List) return [];
  return [for (final c in list) if (c is Map) Customer.fromJson(Map<String, dynamic>.from(c))];
}
