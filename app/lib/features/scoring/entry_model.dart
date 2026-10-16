/// A saved data entry (one row of "Nhập số") as `GET /me/entries` sends it.
class Entry {
  const Entry({
    required this.id,
    required this.customerName,
    required this.entryDate,
    required this.value,
    this.score,
    this.result,
    this.betType,
    this.station,
    this.note,
  });

  final String id;
  final String customerName;
  final String entryDate; // YYYY-MM-DD
  final String value;
  final String? score; // "điểm vào" (a numeric string)
  final String? result; // "điểm ra" as last stored
  final String? betType;
  final String? station;
  final String? note;

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: '${j['id']}',
        customerName: (j['customerName'] as String?) ?? '',
        entryDate: ((j['entryDate'] as String?) ?? '').length >= 10 ? (j['entryDate'] as String).substring(0, 10) : ((j['entryDate'] as String?) ?? ''),
        value: (j['value'] as String?) ?? '',
        score: j['score']?.toString(),
        result: j['result']?.toString(),
        betType: j['betType'] as String?,
        station: j['station'] as String?,
        note: j['note'] as String?,
      );

  Entry withResult(String? r) => Entry(
        id: id,
        customerName: customerName,
        entryDate: entryDate,
        value: value,
        score: score,
        result: r,
        betType: betType,
        station: station,
        note: note,
      );
}

/// A row of the customer roster (`GET /me/customers`); [scoringRates] is the customer's own payout config or null.
class CustomerRec {
  const CustomerRec({required this.id, required this.name, this.scoringRates, this.homeRegion});
  final String id;
  final String name;
  final Map<String, dynamic>? scoringRates;

  /// 'mb' | 'mn' | null: the customer's own region (how "Đầu" is scored on a Miền Bắc result).
  final String? homeRegion;

  factory CustomerRec.fromJson(Map<String, dynamic> j) => CustomerRec(
        id: '${j['id']}',
        name: (j['name'] as String?) ?? '',
        scoringRates: j['scoringRates'] is Map ? Map<String, dynamic>.from(j['scoringRates'] as Map) : null,
        homeRegion: j['homeRegion'] == 'mb' || j['homeRegion'] == 'mn' ? j['homeRegion'] as String : null,
      );
}

/// Name shown for entries without a customer.
const noCustomerName = '(Không tên)';
