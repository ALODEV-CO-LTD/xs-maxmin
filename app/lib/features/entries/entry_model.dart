import '../../core/bet_types.dart';
import '../../core/format.dart';
import 'message_parser.dart';

/// One saved line of Nhập số (a row of `data_entries`).
class Entry {
  Entry({
    required this.id,
    required this.customerName,
    required this.entryDate,
    required this.value,
    this.score,
    this.result,
    this.betType,
    this.station,
    this.note,
    this.createdAt,
    this.updatedAt,
    this.pending = false,
  });

  final String id;
  final String customerName;
  final String entryDate;
  final String value;
  final String? score;
  final String? result;
  final String? betType;
  final String? station;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  /// Saved on this phone only, waiting for the network ("Chờ đồng bộ").
  final bool pending;

  String get type => (betType == null || betType!.isEmpty) ? 'de' : betType!;

  factory Entry.fromJson(Map<String, dynamic> j, {bool pending = false}) => Entry(
        id: '${j['id']}',
        customerName: (j['customerName'] as String?) ?? '',
        entryDate: (j['entryDate'] as String?) ?? '',
        value: (j['value'] as String?) ?? '',
        score: j['score'] as String?,
        result: j['result'] as String?,
        betType: j['betType'] as String?,
        station: j['station'] as String?,
        note: j['note'] as String?,
        createdAt: j['createdAt'] as String?,
        updatedAt: (j['updatedAt'] as String?) ?? (j['createdAt'] as String?),
        pending: pending || j['pending'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'entryDate': entryDate,
        'value': value,
        'score': score,
        'result': result,
        'betType': betType,
        'station': station,
        'note': note,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// A copy with [changes] (the PATCH body fields) applied.
  Entry applying(Map<String, dynamic> changes, {bool? pending}) {
    String? s(String k, String? old) => changes.containsKey(k) ? changes[k] as String? : old;
    return Entry(
      id: id,
      customerName: s('customerName', customerName) ?? customerName,
      entryDate: s('entryDate', entryDate) ?? entryDate,
      value: s('value', value) ?? value,
      score: s('score', score),
      result: s('result', result),
      betType: s('betType', betType),
      station: s('station', station),
      note: s('note', note),
      createdAt: createdAt,
      updatedAt: updatedAt,
      pending: pending ?? this.pending,
    );
  }

  Entry withPending(bool p) => applying(const {}, pending: p);
}

/// Points are free text: strip everything but digits / minus / dot and parse the leading number (like parseFloat),
/// so an empty or odd value counts as 0.
double toNumber(String? s) {
  if (s == null || s.isEmpty) return 0;
  final cleaned = s.replaceAll(RegExp(r'[^\d.-]'), '');
  final m = RegExp(r'^[-+]?(\d+\.?\d*|\.\d+)').firstMatch(cleaned);
  if (m == null) return 0;
  final n = double.tryParse(m.group(0)!);
  return n != null && n.isFinite ? n : 0;
}

/// Plain numbers get thousands separators, anything else is shown as typed, empty = "-".
String fmtPoints(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return '-';
  return RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t) ? formatNumber(num.parse(t)) : t;
}

class EntryTotals {
  const EntryTotals(this.vao, this.ra);
  final double vao;
  final double ra;
  double get chenhLech => vao - ra;
}

EntryTotals totalsOf(Iterable<Entry> entries) {
  double vao = 0, ra = 0;
  for (final e in entries) {
    vao += toNumber(e.score);
    ra += toNumber(e.result);
  }
  return EntryTotals(vao, ra);
}

/// The list filters of Nhập số (K17), run locally so they work offline too.
class EntryFilter {
  EntryFilter({this.q = '', this.date = '', this.type = '', this.all = false});
  String q;
  String date;
  String type;
  bool all;

  bool get active => date.isNotEmpty || type.isNotEmpty || q.trim().isNotEmpty || all;
  void clear() {
    q = '';
    date = '';
    type = '';
    all = false;
  }
}

/// [masked] = the figures are hidden, so searching must not reveal them either.
List<Entry> filterEntries(List<Entry> entries, EntryFilter f, {required String customerName, required bool masked}) {
  final q = foldText(f.q.trim());
  return [
    for (final e in entries)
      if ((f.all || (customerName.isNotEmpty && e.customerName == customerName)) &&
          (f.date.isEmpty || e.entryDate == f.date) &&
          (f.type.isEmpty || e.type == f.type) &&
          (q.isEmpty ||
              foldText([e.customerName, e.entryDate, betTypeLabel(e.type), ...(masked ? const <String?>[] : [e.value, e.score, e.result, e.note])].join(' '))
                  .contains(q)))
        e,
  ];
}

/// Tab separated table, one line per entry (port of clipboard.js entriesToText).
String entriesToText(List<Entry> entries, {bool withCustomer = false}) {
  final lines = <String>[
    [if (withCustomer) 'Khách hàng', 'Ngày', 'Hạng mục', 'Số', 'Điểm vào', 'Điểm ra', 'Ghi chú'].join('\t'),
  ];
  for (final e in entries) {
    lines.add([
      if (withCustomer) e.customerName,
      e.entryDate,
      betTypeLabel(e.type),
      e.value,
      e.score ?? '',
      e.result ?? '',
      (e.note ?? '').replaceAll(RegExp(r'\s+'), ' '),
    ].join('\t'));
  }
  return lines.join('\n');
}
