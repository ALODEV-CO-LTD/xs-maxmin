// Port của frontend/tests/chatReport.test.mjs (cùng đầu vào, cùng kết quả) + số liệu đối chiếu với bản web.
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/chat_calc/chat_report.dart';

const mn = <String, dynamic>{
  'giaiTam': ['20'],
  'giaiBay': ['120'],
  'giaiSau': ['1234', '5678', '0020'],
  'giaiNam': ['9020'],
  'giaiTu': ['11111', '22222', '33333', '44444', '55555', '66666', '77720'],
  'giaiBa': ['12345', '23456'],
  'giaiNhi': ['34567'],
  'giaiNhat': ['45678'],
  'dacBiet': ['123456'],
};

ChatReport _build({required Map<String, dynamic>? result, required List<ReportRow> rows, RatesMap? rates}) => buildReport(
      rows: rows,
      result: result,
      station: 'mn-tphcm',
      stationName: 'TP.HCM',
      date: '2026-10-15',
      accountRates: rates ?? defaultRates,
    );

void main() {
  test('không có kết quả: không tính tiền trúng, lợi nhuận "chưa đủ dữ liệu"', () {
    final r = _build(result: null, rows: const [ReportRow(type: 'lo', value: '20', score: '10')]);
    expect(r.missingResult, isTrue);
    expect(r.totals.profit, isNull);
    expect(r.totals.won, 0);
    expect(reportText(r), contains('Tổng lợi nhuận: Chưa đủ dữ liệu'));
    expect(reportText(r), contains('Trúng: chưa đủ dữ liệu'));
  });

  test('có kết quả: lô 20 về 5 lần; lợi nhuận = đánh - trúng; dòng cần kiểm tra không được tính', () {
    final r = _build(result: mn, rows: const [ReportRow(type: 'lo', value: '20', score: '10'), ReportRow(type: 'lo', value: '99', score: '7', uncertain: true)]);
    final lo = r.groups[0];
    expect(lo.stake, 10);
    expect(lo.winPoints, 50);
    expect(r.skipped.length, 1);
    expect(r.totals.profit, r.totals.stake - r.totals.won);
    final t = reportText(r);
    expect(t.startsWith('BÁO CÁO KẾT QUẢ\nĐài: TP.HCM\nNgày: 15/10/2026'), isTrue);
    expect(t, contains('Tổng tiền khách đánh:'));
  });

  test('id báo cáo ổn định theo nội dung (và bằng id của bản web)', () {
    final r = _build(result: mn, rows: const []);
    expect(reportId(r, ['20lo10']), reportId(r, ['20lo10']));
    expect(reportId(r, ['20lo10']), isNot(reportId(r, ['20lo11'])));
    expect(reportId(r, ['20lo10']), 'r6brkiu');
    expect(reportId(r, ['20lo11', 'x ñ']), 'r5rj0rk');
  });

  test('cấu hình cũ (rate/tiers, không có giá tiền) vẫn ra số, không NaN', () {
    final legacy = <String, dynamic>{
      'lo': {
        'rate': 20,
        'tiers': ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'],
        'digits': 2,
      },
    };
    final r = _build(rates: legacy, result: mn, rows: const [ReportRow(type: 'lo', value: '20', score: '10')]);
    expect(r.totals.won.isFinite && r.totals.profit!.isFinite, isTrue);
    expect(r.groups[0].winPoints, 50);
  });

  group('đối chiếu với bản web (cùng đầu vào, in ra từ chatReport.js)', () {
    const rows = [
      ReportRow(type: 'lo', value: '20', score: '10'),
      ReportRow(type: 'lo', value: '99', score: '7', uncertain: true),
      ReportRow(type: 'de', value: '23', score: '5'),
      ReportRow(type: 'dau', value: '12', score: '3'),
      ReportRow(type: 'cang3', value: '720', score: '2'),
      ReportRow(type: 'xien2', value: '20 34', score: '4'),
    ];

    test('có kết quả', () {
      final r = _build(result: mn, rows: rows);
      expect(r.totals.stake, 255005);
      expect(r.totals.won, 3500000);
      expect(r.totals.profit, -3244995);
      expect(r.other.stakeMoney, 5);
      expect(r.other.kinds, ['de']);
      expect(reportText(r), '''BÁO CÁO KẾT QUẢ
Đài: TP.HCM
Ngày: 15/10/2026

Tổng số điểm lô: 10 điểm
Đánh 10 điểm × 12.600 = 126.000đ
Trúng 50 điểm = 3.500.000đ (còn -40 điểm)
Tổng số điểm đầu đuôi: 3 điểm
Đánh 3 điểm × 1.000 = 3.000đ
Trúng 0 điểm = 0đ (còn 3 điểm)
Tổng số 3 càng: 2 điểm
Đánh 2 điểm × 12.600 = 25.200đ
Trúng 0 điểm = 0đ (còn 2 điểm)
Tổng số xiên 2: 8 điểm
Đánh 8 điểm × 12.600 = 100.800đ
Trúng 4 điểm = 0đ (còn 4 điểm)
Tổng số xiên 3: 0 điểm
Kiểu đánh khác: đánh 5đ, trúng 0đ

Tổng tiền khách đánh: 255.005đ
Tổng tiền khách trúng: 3.500.000đ
Tổng lợi nhuận: -3.244.995đ''');
    });

    test('chưa có kết quả', () {
      final t = reportText(_build(result: null, rows: rows));
      expect(t, contains('Tổng số xiên 2: 8 điểm\nĐánh 8 điểm × 12.600 = 100.800đ\nTrúng: chưa đủ dữ liệu\nTổng số xiên 3: 0 điểm\nKiểu đánh khác: đánh 5đ\n'));
      expect(t, endsWith('Tổng tiền khách đánh: 255.005đ\nTổng tiền khách trúng: Chưa đủ dữ liệu\nTổng lợi nhuận: Chưa đủ dữ liệu'));
    });
  });

  test('định dạng số kiểu vi-VN', () {
    expect(money(1234567), '1.234.567đ');
    expect(money(-1500), '-1.500đ');
    expect(money(0.5), '1đ');
    expect(points(0.30000000000000004), '0,3 điểm');
    expect(points(2500), '2.500 điểm');
    expect(points(2.5), '2,5 điểm');
  });

  test('lưu rồi mở lại báo cáo (toJson/fromJson) cho cùng một văn bản', () {
    final r = _build(result: mn, rows: const [ReportRow(type: 'lo', value: '20', score: '10'), ReportRow(type: 'lo', value: '99', score: '7', uncertain: true)]);
    final back = ChatReport.fromJson(r.toJson());
    expect(reportText(back), reportText(r));
    expect(back.skipped.single.value, '99');
  });

  test('khách có miền riêng truyền vào cách tính (mặc định không đổi kết quả)', () {
    final a = _build(result: mn, rows: const [ReportRow(type: 'lo', value: '20', score: '10')]);
    final b = buildReport(rows: const [ReportRow(type: 'lo', value: '20', score: '10')], result: mn, station: 'mn-tphcm', stationName: 'TP.HCM', date: '2026-10-15', accountRates: defaultRates, customerRegion: 'mn');
    expect(reportText(b), reportText(a));
  });
}
