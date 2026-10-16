// Port of frontend/tests/messageParser.test.mjs + kindSymbols.test.mjs (same inputs / outputs).
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/entries/message_parser.dart';

const types = ['de', 'lo'];
const wide = ['de', 'lo', 'dau', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4'];
String brief(ParsedRow r) => '${r.type}:${r.value}@${r.score}${r.uncertain ? '!' : ''}';
List<String> parse(String text, [List<String> bt = types, SyntaxTemplate? tpl]) => parseMessage(text, betTypes: bt, template: tpl).rows.map(brief).toList();
List<String> decode(String text, [List<String> bt = types, SyntaxTemplate? tpl]) => decodeMessage(text, betTypes: bt, template: tpl).map((l) => l.decoded).toList();

void main() {
  test('ví dụ chính: 20lo100 70lo500 54lo300', () {
    expect(parse('20lo100 70lo500 54lo300'), ['lo:20@100', 'lo:70@500', 'lo:54@300']);
    expect(decode('20lo100 70lo500 54lo300'), ['20lô100 70lô500 54lô300']);
  });

  test('bao lô: mọi cách viết ký hiệu', () {
    for (final sym in ['lo', 'l', 'L', 'lô', 'Lô', 'LO', 'x', 'X']) {
      expect(parse('20${sym}30'), ['lo:20@30'], reason: sym);
    }
  });

  test('đầu và đuôi (đuôi trùng với Đề của tài khoản)', () {
    for (final sym in ['d', 'D', 'đ', 'dau', 'đầu', 'đâu', 'dâu']) {
      expect(parse('20${sym}10', wide), ['dau:20@10'], reason: sym);
    }
    for (final sym in ['c', 'C', 'cuoi', 'cuôi', 'cuối', 'CUOI']) {
      expect(parse('20${sym}10'), ['de:20@10'], reason: sym);
    }
    expect(parse('20c10', [...types, 'duoi']), ['duoi:20@10']);
  });

  test('20d10c20 = đầu 10 + đuôi 20', () {
    expect(parse('20d10c20', wide), ['dau:20@10', 'de:20@20']);
    expect(decode('20d10c20', wide), ['20đầu10 20đuôi20']);
  });

  test('3 càng và 4 càng theo số chữ số', () {
    expect(parse('123x100', wide), ['cang3:123@100']);
    expect(parse('5000x100', wide), ['cang4:5000@100']);
    expect(parse('5000l100', wide), ['cang4:5000@100']);
    expect(parse('5000Lo100', wide), ['cang4:5000@100']);
  });

  test('xiên', () {
    expect(parse('20x02lo10', wide), ['xien2:20 02@10!']);
    expect(parse('20.02lo10', wide), ['xien2:20 02@10!']);
    expect(parse('20.02.35x10', wide), ['xien3:20 02 35@10!']);
    expect(parse('20.02x10', types), ['de:20@10!', 'de:02@10!']);
    expect(decode('20x02lo10', wide), ['20.02xiên10']);
  });

  test('loại chưa có trong cấu hình bị đánh dấu', () {
    final r = parseMessage('20dau10', betTypes: types).rows.first;
    expect(r.type, 'dau');
    expect(r.uncertain, isTrue);
    expect(r.reasons.any((x) => x.contains('chưa có trong cấu hình')), isTrue);
    expect(parseMessage('20dau10', betTypes: wide).rows.first.uncertain, isFalse);
  });

  test('số chữ số sai bị đánh dấu', () {
    expect(parseMessage('200lo10', betTypes: wide).rows.first.type, 'cang3');
    final d = parseMessage('123d10', betTypes: wide).rows.first;
    expect(d.uncertain, isTrue);
    expect(d.reasons.any((x) => x.contains('2 chữ số')), isTrue);
  });

  test('x trần', () {
    expect(parse('20x30'), ['lo:20@30']);
    expect(parse('20x30', types, SyntaxTemplate(defaultType: 'de')), ['de:20@30']);
    expect(parse('de:\n20x30'), ['de:20@30']);
  });

  test('hồi quy định dạng cũ', () {
    expect(parse('de 12 34 56 x 10'), ['de:12@10', 'de:34@10', 'de:56@10']);
    expect(parse('lô 45,78 con 3'), ['lo:45@3', 'lo:78@3']);
    expect(parse('12=50', types, SyntaxTemplate(defaultType: 'de')), ['de:12@50']);
    expect(parse('de:\n12 x 5\n34 x 7'), ['de:12@5', 'de:34@7']);
    expect(parse('lo 20 x 30'), ['lo:20@30']);
    expect(parseMessage('xin chào anh', betTypes: types).rows, isEmpty);
  });

  test('dòng lẫn cú pháp liền và chữ khác đi đường cũ', () {
    final out = parseMessage('20lo100 abc', betTypes: types);
    expect(out.rows.every((r) => r.uncertain), isTrue);
  });

  test('ký hiệu riêng của khách (mẫu)', () {
    final tpl = SyntaxTemplate(typeAliases: {'tr': 'truot'});
    expect(parse('20tr10', ['de', 'lo', 'truot'], tpl), ['truot:20@10']);
    expect(parse('20tr10', types, tpl), ['truot:20@10!']);
  });

  test('điểm thập phân và số 0 đầu', () {
    expect(parse('02lo10.5'), ['lo:02@10.5']);
    expect(parse('02lo10,5'), ['lo:02@10.5']);
    expect(decode('02lo10,5'), ['02lô10,5']);
  });

  test('giải mã: không đổi số, giữ khoảng trắng, báo phần lạ', () {
    final line = decodeMessage('  20lo100   chào 99zz  54L300', betTypes: types).first;
    expect(line.decoded, '  20lô100   chào 99zz  54lô300');
    expect(line.changed, isTrue);
    expect(line.unknown, isTrue);
    expect(line.parts.firstWhere((p) => p.text == '99zz').status, 'unknown');
    expect(line.parts.firstWhere((p) => p.text == 'chào').status, 'plain');
  });

  test('giải mã chạy lần hai ổn định', () {
    for (final t in ['20lo100 70lo500', '20d10c20', '20x02lo10', '123x100', '5000l100', '20dau10 20cuoi10']) {
      final once = decode(t, wide).first;
      expect(decode(once, wide).first, once, reason: t);
    }
  });

  test('mỗi dòng xử lý độc lập', () {
    expect(decode('20lo100\n30d5\n99', wide), ['20lô100', '30đầu5', '99']);
  });

  test('kindSymbols: ký hiệu khách đặt trong bảng', () {
    const w = ['lo', 'dau', 'duoi', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4'];
    final rates = <String, dynamic>{...defaultRates};
    rates['lo@mn'] = {...(rates['lo@mn'] as Map), 'symbols': ['bl']};
    final ks = kindSymbolsFor(rates, null, 'mn');
    expect(ks, {'lo': ['bl']});
    final own = parseMessage('20bl100', betTypes: w, kindSymbols: ks).rows.map((r) => '${r.type}:${r.value}@${r.score}').toList();
    expect(own, ['lo:20@100']);
  });
}
