import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/entries/message_parser.dart';

String brief(ParsedRow r) => '${r.type}:${r.value}@${r.score}${r.uncertain ? '!' : ''}';
List<String> parse(String t) => parseMessage(t, betTypes: const ['de', 'lo']).rows.map(brief).toList();

void main() {
  test('comma between a điểm and the next group is a separator, no entry lost', () {
    expect(parse('20lo100,70lo500'), ['lo:20@100', 'lo:70@500']);
    expect(parse('20lo100,70lo500,54lo300'), ['lo:20@100', 'lo:70@500', 'lo:54@300']);
  });

  test('a decimal comma still works and number lists with commas are unchanged', () {
    expect(parse('20lo1,5'), ['lo:20@1.5']);
    expect(parse('20lo100,5'), ['lo:20@100.5']);
    expect(parse('20,30lo10'), ['xien2:20 30@10!']); // unchanged: numbers joined by a comma + lô = xiên
  });
}
