import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/entries/message_parser.dart';

String sig(ParsedRow r) => '${r.type}:${r.value}:${r.score}';

void main() {
  group('foldText', () {
    test('lower-cases and strips Vietnamese diacritics', () {
      expect(foldText('Đề'), 'de');
      expect(foldText('LÔ'), 'lo');
      expect(foldText('Nguyễn Văn Ơn'), 'nguyen van on');
    });
    test('strips combining marks of decomposed text', () {
      expect(foldText('lô'), 'lo');
    });
  });

  group('parseMessage', () {
    test('several numbers sharing one stake', () {
      final r = parseMessage('de 12 34 56 x 10');
      expect(r.rows.map(sig), ['de:12:10', 'de:34:10', 'de:56:10']);
      expect(r.rows.every((x) => !x.uncertain), isTrue);
      expect(r.ignored, isEmpty);
    });

    test('accents, commas and "con" as the stake marker', () {
      final r = parseMessage('Lô 45,78 con 3');
      expect(r.rows.map(sig), ['lo:45:3', 'lo:78:3']);
      expect(r.rows.every((x) => !x.uncertain), isTrue);
    });

    test('a decimal stake with a comma becomes a dot, "diem" suffix is allowed', () {
      expect(parseMessage('de 12 x 2,5').rows.single.score, '2.5');
      expect(parseMessage('lo 12 x 10 diem').rows.single.score, '10');
    });

    test('equal sign and star markers', () {
      expect(parseMessage('de 12=50').rows.single.score, '50');
      expect(parseMessage('de 12*7').rows.single.score, '7');
      expect(parseMessage('de 12 × 7').rows.single.score, '7');
    });

    test('no type: the first bet type is assumed and the row is flagged', () {
      final r = parseMessage('12=50');
      expect(r.rows.single.type, 'de');
      expect(r.rows.single.uncertain, isTrue);
      expect(r.rows.single.reasons, contains('Chưa rõ hạng mục, tạm dùng mặc định'));
      expect(parseMessage('12=50', betTypes: ['lo', 'de']).rows.single.type, 'lo');
    });

    test('a line with only a hạng mục sets the type for the lines below', () {
      final r = parseMessage('lo:\n12 x 5\n34 x 6\nde\n78 x 1');
      expect(r.rows.map(sig), ['lo:12:5', 'lo:34:6', 'de:78:1']);
      expect(r.rows.every((x) => !x.uncertain), isTrue);
    });

    test('two types on one line', () {
      final r = parseMessage('de 12 x 5 lo 34 x 6');
      expect(r.rows.map(sig), ['de:12:5', 'lo:34:6']);
    });

    test('missing stake and numbers that are not 2 digits are flagged', () {
      final noScore = parseMessage('de 12 34').rows;
      expect(noScore.map((x) => x.score), ['', '']);
      expect(noScore.first.reasons, contains('Chưa có điểm'));
      final three = parseMessage('de 123 x 5').rows.single;
      expect(three.reasons, contains('Số không phải 2 chữ số'));
    });

    test('strange characters in the numbers part are flagged', () {
      final r = parseMessage('de 1a2 x 5').rows;
      expect(r.every((x) => x.reasons.contains('Có ký tự lạ trong phần số')), isTrue);
    });

    test('lines without digits are ignored and reported', () {
      final r = parseMessage('Chào anh\nde 12 x 5\n');
      expect(r.rows, hasLength(1));
      expect(r.ignored, ['Chào anh']);
    });

    test('blank input and CRLF', () {
      expect(parseMessage('').rows, isEmpty);
      expect(parseMessage(null).rows, isEmpty);
      expect(parseMessage('de 12 x 5\r\nde 34 x 6').rows, hasLength(2));
    });

    test('built-in alias dde and the bet types of the account', () {
      expect(parseMessage('dde 12 x 5').rows.single.type, 'de');
      final r = parseMessage('xien-2 12 x 5', betTypes: ['de', 'lo', 'xien-2']);
      expect(r.rows.single.type, 'xien-2');
    });

    test('template: default type, aliases and stake markers', () {
      final t = SyntaxTemplate(defaultType: 'lo', typeAliases: {'dd': 'de'}, stakeMarkers: ['@']);
      final r = parseMessage('dd 12 @ 5\n34 @ 6', template: t);
      expect(r.rows.map(sig), ['de:12:5', 'de:34:6']); // the sticky dd carries over
      final d = parseMessage('34 @ 6', template: t).rows.single;
      expect(d.type, 'lo');
      expect(d.uncertain, isFalse); // a default type means the type is not a guess
    });

    test('longer aliases win over shorter ones', () {
      final r = parseMessage('dde 12 x 5', template: SyntaxTemplate(typeAliases: {'dd': 'lo'}));
      expect(r.rows.single.type, 'de');
    });
  });

  group('template helpers', () {
    test('aliases <-> text', () {
      expect(aliasesToText({'dd': 'de', 'l': 'lo'}), 'dd=de, l=lo');
      expect(textToAliases('dd=de, l=lo; bad; x=zz', ['de', 'lo']), {'dd': 'de', 'l': 'lo'});
      expect(textToAliases('Đd = de'), {'dd': 'de'});
    });
    test('markers text', () {
      expect(textToMarkers('x, con;  = '), ['x', 'con', '=']);
    });
    test('SyntaxTemplate json round trip', () {
      final t = SyntaxTemplate.fromJson({'defaultType': 'de', 'typeAliases': {'a': 'lo'}, 'stakeMarkers': ['x']});
      expect(t.toJson(), {'defaultType': 'de', 'typeAliases': {'a': 'lo'}, 'stakeMarkers': ['x']});
      expect(SyntaxTemplate.fromJson(null).stakeMarkers, defaultStakeMarkers);
    });
  });
}
