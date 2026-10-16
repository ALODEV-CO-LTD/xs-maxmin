// Báo cáo kết quả tính toán từ tin nhắn đã giải mã. Port của frontend/src/chatReport.js.
// Hàm thuần, không gọi mạng: nhận các dòng đã đọc (parseMessage), kết quả xổ số của ĐÚNG đài + ngày và cấu hình giá;
// không bao giờ tự bịa số: thiếu kết quả thì `missingResult` và không có tiền trúng.
import 'dart:convert';

import '../../core/scoring_config.dart';
import '../scoring/entry_model.dart';
import '../scoring/scoring_logic.dart';

/// Một nhóm thống kê theo thứ tự trong tài liệu; kiểu đánh không thuộc nhóm nào vẫn được cộng vào tổng và liệt kê riêng.
class ReportGroupDef {
  const ReportGroupDef(this.key, this.label, this.kinds);
  final String key;
  final String label;
  final List<String> kinds;
}

const reportGroups = [
  ReportGroupDef('lo', 'Tổng số điểm lô', ['lo', 'lo3', 'lo4']),
  ReportGroupDef('dauduoi', 'Tổng số điểm đầu đuôi', ['dau', 'duoi']),
  ReportGroupDef('cang3', 'Tổng số 3 càng', ['cang3']),
  ReportGroupDef('xien2', 'Tổng số xiên 2', ['xien2']),
  ReportGroupDef('xien3', 'Tổng số xiên 3', ['xien3']),
];

String _groupOf(String kind) {
  for (final g in reportGroups) {
    if (g.kinds.contains(kind)) return g.key;
  }
  return 'other';
}

/// `Math.round` của JavaScript (làm tròn nửa lên) rồi định dạng kiểu vi-VN: 1234567 -> "1.234.567".
String _group(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return b.toString();
}

int _jsRound(num n) => (n + 0.5).floor();

/// Số nguyên kiểu vi-VN ("-1.500").
String viInt(num n) {
  final r = _jsRound(n);
  return '${r < 0 ? '-' : ''}${_group(r.abs().toString())}';
}

/// "1.234.567đ"
String money(num n) => '${viInt(n)}đ';

/// Số thập phân tối đa 2 chữ số kiểu vi-VN, bỏ số 0 thừa: 2.5 -> "2,5", 2500 -> "2.500".
String _viDecimal(double n) {
  var s = n.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  final out = '${_group(parts[0])}${parts.length > 1 ? ',${parts[1]}' : ''}';
  return neg && out != '0' ? '-$out' : out;
}

/// "2.500 điểm"
String points(num n) => '${_viDecimal(n.toDouble())} điểm';

/// Một dòng đã đọc từ tin nhắn.
class ReportRow {
  const ReportRow({required this.type, required this.value, required this.score, this.uncertain = false});
  final String type;
  final String value;
  final String score;
  final bool uncertain;

  Map<String, dynamic> toJson() => {'type': type, 'value': value, 'score': score, 'uncertain': uncertain};
  factory ReportRow.fromJson(Map<String, dynamic> j) => ReportRow(type: '${j['type'] ?? ''}', value: '${j['value'] ?? ''}', score: '${j['score'] ?? ''}', uncertain: j['uncertain'] == true);
}

class ReportGroup {
  ReportGroup({required this.key, this.label = '', this.stake = 0, this.stakeMoney = 0, this.winPoints = 0, this.winMoney = 0, this.lots = 0, List<String>? kinds, this.rest = 0, this.price = 0}) : kinds = kinds ?? [];
  final String key;
  final String label;
  double stake;
  double stakeMoney;
  double winPoints;
  double winMoney;
  int lots;
  List<String> kinds;
  double rest;
  double price;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'stake': stake, 'stakeMoney': stakeMoney, 'winPoints': winPoints, 'winMoney': winMoney, 'lots': lots, 'kinds': kinds, 'rest': rest, 'price': price};
  factory ReportGroup.fromJson(Map<String, dynamic> j) => ReportGroup(
        key: '${j['key']}',
        label: '${j['label'] ?? ''}',
        stake: (j['stake'] as num?)?.toDouble() ?? 0,
        stakeMoney: (j['stakeMoney'] as num?)?.toDouble() ?? 0,
        winPoints: (j['winPoints'] as num?)?.toDouble() ?? 0,
        winMoney: (j['winMoney'] as num?)?.toDouble() ?? 0,
        lots: (j['lots'] as num?)?.toInt() ?? 0,
        kinds: [for (final k in (j['kinds'] as List? ?? const [])) '$k'],
        rest: (j['rest'] as num?)?.toDouble() ?? 0,
        price: (j['price'] as num?)?.toDouble() ?? 0,
      );
}

class ReportTotals {
  ReportTotals({required this.stake, required this.won, this.profit});
  final double stake;
  final double won;

  /// null = "Chưa đủ dữ liệu" (chưa có kết quả xổ số).
  final double? profit;

  Map<String, dynamic> toJson() => {'stake': stake, 'won': won, 'profit': profit};
  factory ReportTotals.fromJson(Map<String, dynamic> j) => ReportTotals(stake: (j['stake'] as num?)?.toDouble() ?? 0, won: (j['won'] as num?)?.toDouble() ?? 0, profit: (j['profit'] as num?)?.toDouble());
}

class ChatReport {
  ChatReport({required this.date, required this.station, required this.stationName, required this.missingResult, required this.groups, required this.other, required this.totals, required this.skipped, required this.count});
  final String date;
  final String station;
  final String stationName;
  final bool missingResult;
  final List<ReportGroup> groups;
  final ReportGroup other;
  final ReportTotals totals;
  final List<ReportRow> skipped;
  final int count;

  Map<String, dynamic> toJson() => {
        'date': date,
        'station': station,
        'stationName': stationName,
        'missingResult': missingResult,
        'groups': [for (final g in groups) g.toJson()],
        'other': other.toJson(),
        'totals': totals.toJson(),
        'skipped': [for (final r in skipped) r.toJson()],
        'count': count,
      };

  factory ChatReport.fromJson(Map<String, dynamic> j) => ChatReport(
        date: '${j['date'] ?? ''}',
        station: '${j['station'] ?? ''}',
        stationName: '${j['stationName'] ?? ''}',
        missingResult: j['missingResult'] == true,
        groups: [for (final g in (j['groups'] as List? ?? const [])) ReportGroup.fromJson(Map<String, dynamic>.from(g as Map))],
        other: ReportGroup.fromJson(Map<String, dynamic>.from((j['other'] as Map?) ?? {'key': 'other'})),
        totals: ReportTotals.fromJson(Map<String, dynamic>.from((j['totals'] as Map?) ?? const {})),
        skipped: [for (final r in (j['skipped'] as List? ?? const [])) ReportRow.fromJson(Map<String, dynamic>.from(r as Map))],
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// Miền của một đài theo id: 'mb' | 'mt' | 'mn' (id đài Trung bắt đầu bằng "mt").
String defaultRegionOf(String station) => station == 'mb' || station.isEmpty ? 'mb' : (station.startsWith('mt') ? 'mt' : 'mn');

/// [rows]: các dòng đã đọc; [result]: kết quả của đài (null = chưa có); [station]: id đài, vd 'mt-quangnam'.
/// [customerRegion] ('mb' | 'mn' | null) là miền của khách (cách tính "Đầu" của khách Nam/Trung trên kết quả Miền Bắc);
/// web chưa truyền giá trị này, để null thì ra đúng kết quả của web.
ChatReport buildReport({
  required List<ReportRow> rows,
  required LotteryResult? result,
  required String station,
  required String stationName,
  required String date,
  required RatesMap? accountRates,
  RatesMap? customerRates,
  String? customerRegion,
  String Function(String station)? regionOf,
}) {
  final region = (regionOf ?? defaultRegionOf)(station);
  final acc = {for (final g in [...reportGroups.map((g) => g.key), 'other']) g: ReportGroup(key: g, label: reportGroups.where((d) => d.key == g).map((d) => d.label).firstOrNull ?? '')};
  final used = rows.where((r) => !r.uncertain).toList();
  final skipped = rows.where((r) => r.uncertain).toList();
  for (final r in used) {
    final kind = r.type.isEmpty ? 'de' : r.type;
    final cfg = effectiveConfig(accountRates, customerRates, kind, region);
    final entry = Entry(id: '', customerName: '', entryDate: date, value: r.value, score: r.score, betType: kind, station: station);
    final d = entryDetail(entry, result, cfg, ScoreCtx(region: region, customerRegion: customerRegion));
    final stake = d.score * d.lots * (d.stakeFactor == 0 ? 1 : d.stakeFactor);
    final g = acc[_groupOf(kind)]!;
    if (!g.kinds.contains(kind)) g.kinds.add(kind);
    g.lots += d.lots;
    g.stake += stake;
    g.stakeMoney += stakeMoney(kind, cfg, stake);
    if (result != null) {
      g.winPoints += d.score * d.totalHits;
      g.winMoney += winMoney(kind, cfg, d.score, d.totalHits);
    }
  }
  final groups = [
    for (final def in reportGroups)
      () {
        final a = acc[def.key]!;
        a.rest = a.stake - a.winPoints;
        a.price = a.stake != 0 ? a.stakeMoney / a.stake : 0;
        return a;
      }(),
  ];
  final other = acc['other']!;
  final all = [...groups, other];
  final stake = all.fold<double>(0, (s, g) => s + g.stakeMoney);
  final won = all.fold<double>(0, (s, g) => s + g.winMoney);
  return ChatReport(
    date: date,
    station: station,
    stationName: stationName,
    missingResult: result == null,
    groups: groups,
    other: other,
    totals: ReportTotals(stake: stake, won: won, profit: result != null ? stake - won : null),
    skipped: skipped,
    count: used.length,
  );
}

/// Mỗi nhóm: "Tổng số điểm lô: 2.500 điểm", "Đánh 2.500 điểm × 12.600 = 31.500.000đ", "Trúng 300 điểm = 3.000.000đ".
List<String> groupLines(ReportGroup g, bool missingResult) {
  if (g.stake == 0) return ['${g.label}: 0 điểm'];
  return [
    '${g.label}: ${points(g.stake)}',
    'Đánh ${points(g.stake)} × ${viInt(g.price)} = ${money(g.stakeMoney)}',
    missingResult ? 'Trúng: chưa đủ dữ liệu' : 'Trúng ${points(g.winPoints)} = ${money(g.winMoney)} (còn ${points(g.rest)})',
  ];
}

String fmtProfit(double? n) => n == null ? 'Chưa đủ dữ liệu' : money(n);

/// Nội dung để Copy và để gửi cho khách (một nguồn duy nhất, đúng báo cáo đã tính).
String reportText(ChatReport rep) {
  final lines = <String>['BÁO CÁO KẾT QUẢ', 'Đài: ${rep.stationName}', 'Ngày: ${rep.date.split('-').reversed.join('/')}', ''];
  for (final g in rep.groups) {
    lines.addAll(groupLines(g, rep.missingResult));
  }
  if (rep.other.stake != 0) {
    lines.add('Kiểu đánh khác: đánh ${money(rep.other.stakeMoney)}${rep.missingResult ? '' : ', trúng ${money(rep.other.winMoney)}'}');
  }
  lines.add('');
  lines.add('Tổng tiền khách đánh: ${money(rep.totals.stake)}');
  lines.add('Tổng tiền khách trúng: ${rep.missingResult ? 'Chưa đủ dữ liệu' : money(rep.totals.won)}');
  lines.add('Tổng lợi nhuận: ${fmtProfit(rep.totals.profit)}');
  return lines.join('\n');
}

/// ID ổn định theo nội dung: lưu lại nhiều lần cùng một báo cáo không tạo bản ghi trùng (cùng thuật toán băm với web).
String reportId(ChatReport rep, List<String> lines) {
  final s = jsonEncode([rep.station, rep.date, lines]);
  var h = 5381;
  for (var i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return 'r${h.toRadixString(36)}';
}
