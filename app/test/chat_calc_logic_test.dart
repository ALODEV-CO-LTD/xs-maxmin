// Luồng chat > Đối chiếu > Nhập số / Tính toán: logic không cần màn hình.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/format.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/calc/calc_screen.dart';
import 'package:mamba_app/features/chat_calc/chat_decode_model.dart';
import 'package:mamba_app/features/chat_calc/chat_prefill.dart';
import 'package:mamba_app/features/entries/entries_controller.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scoring_fixtures.dart';

http.Response _j(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

void main() {
  final decode = decoderFor(betTypes: const ['de', 'lo']);

  group('đối chiếu giải mã', () {
    test('mỗi dòng: tin gốc, bản giải mã (không đổi số), phần chưa nhận ra được đánh dấu', () async {
      final items = await buildDecodeItems(const [DecodeSource('a', '20lo10 70lo5\nxin chào\n12 khong ro')], decode, (_) async => null);
      final lines = items.single.lines;
      expect(lines.map((l) => l.original), ['20lo10 70lo5', 'xin chào', '12 khong ro']);
      expect(lines[0].decoded, '20lô10 70lô5');
      expect(lines[1].decoded, 'xin chào'); // không phải số: giữ nguyên
      expect(lines[2].decoded, '12 khong ro');
      expect(lines[2].unknown, isTrue); // có số nhưng không nhận ra
      expect(lines[0].unknown, isFalse);
      expect(lines.every((l) => !l.edited), isTrue);
    });

    test('sửa, khôi phục, lưu: chỉ lưu khi có sửa; bản đã lưu áp dụng lại đúng tin gốc', () async {
      final saved = <String, String>{};
      final items = await buildDecodeItems(const [DecodeSource('a', '20lo10\n30lo5'), DecodeSource('b', '45lo2')], decode, (id) async => saved[id]);
      items[0].lines[0].text = '20lô100';
      expect(items[0].lines[0].edited, isTrue);
      expect(items[0].savedJson(), isNotNull);
      expect(items[1].savedJson(), isNull); // không sửa: không lưu (xoá bản cũ)
      saved['a'] = items[0].savedJson()!;

      final again = await buildDecodeItems(const [DecodeSource('a', '20lo10\n30lo5')], decode, (id) async => saved[id]);
      expect(again.single.lines[0].text, '20lô100');
      expect(again.single.lines[0].decoded, '20lô10'); // bản giải mã ban đầu vẫn còn để khôi phục
      restoreLine(again.single.lines[0]);
      expect(again.single.lines[0].text, '20lô10');
      expect(again.single.savedJson(), isNull);

      // tin gốc đổi (hoặc số dòng khác) thì bản sửa cũ không áp dụng
      final changed = await buildDecodeItems(const [DecodeSource('a', '20lo11\n30lo5')], decode, (id) async => saved[id]);
      expect(changed.single.lines[0].text, '20lô11');
      final fewer = await buildDecodeItems(const [DecodeSource('a', '20lo10')], decode, (id) async => saved[id]);
      expect(fewer.single.lines[0].text, '20lô10');
      final broken = await buildDecodeItems(const [DecodeSource('a', '20lo10')], decode, (_) async => '{không phải json');
      expect(broken.single.lines[0].text, '20lô10');
    });

    test('giải mã lại bỏ mọi chỗ sửa; nội dung chuyển đi là các dòng không rỗng theo thứ tự các tin', () async {
      final items = await buildDecodeItems(const [DecodeSource('a', '20lo10\n\n30lo5'), DecodeSource('b', '45lo2')], decode, (_) async => null);
      expect(joinedText(items), '20lô10\n30lô5\n45lô2');
      items[0].lines[0].text = 'de 20 x 7';
      items[1].lines[0].text = '   '; // dòng trống sau khi sửa bị bỏ
      expect(joinedText(items), 'de 20 x 7\n30lô5');
      expect(anyEdited(items), isTrue);
      redecode(items, decode);
      expect(anyEdited(items), isFalse);
      expect(joinedText(items), '20lô10\n30lô5\n45lô2');
    });
  });

  test('chỗ giao nhận Nhập số chỉ giao một lần', () {
    final hub = ChatPrefillHub();
    var rings = 0;
    hub.addListener(() => rings++);
    expect(hub.take(), isNull);
    hub.offer(const ChatPrefill(text: 'x', customer: 'An'));
    expect(rings, 1);
    expect(hub.take()?.customer, 'An');
    expect(hub.take(), isNull);
  });

  test('đường dẫn sang Tính điểm mang theo khách, ngày, số lượng đã thêm (mã hoá được tên có dấu)', () {
    final u = Uri.parse(calcLocation('scoring', customer: 'Anh Tú & Bạn', date: '2026-10-15', added: 3));
    expect(u.path, '/calc');
    expect(u.queryParameters['tab'], 'scoring');
    expect(u.queryParameters['customer'], 'Anh Tú & Bạn');
    expect(u.queryParameters['date'], '2026-10-15');
    expect(u.queryParameters['added'], '3');
    expect(calcLocation('entries'), isNot(contains('customer')));
  });

  test('Nhập số nhận nội dung từ chat: khách, ngày, đài theo màn đối chiếu (đài không bị khách ghi đè), chữ vào ô nhập nhanh', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthStore()..token = 't';
    final api = ApiClient(auth, client: MockClient((r) async {
      switch (r.url.path) {
        case '/api/me/customers':
          return _j({'customers': [{'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null, 'defaultStation': 'mt'}]});
        case '/api/me/scoring-settings':
          return _j({'rates': {'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2}, 'lo': {'rate': 20, 'tiers': ['dacBiet'], 'digits': 2}}});
        case '/api/me/entries':
          return _j({'entries': [], 'total': 0, 'hasMore': false});
        case '/api/me/syntax-templates':
          return _j({'templates': []});
        case '/api/me':
          return _j({'package': {'isActive': true}, 'stats': {}});
      }
      return http.Response('{}', 404);
    }));
    final store = OfflineStore(api: api, prefs: await SharedPreferences.getInstance(), userId: 'u1');
    final c = EntriesController(api: api, auth: auth, stations: testStations(), store: store);
    final init = c.init();
    // nhận nội dung trước khi tải xong: chờ tải xong rồi mới áp dụng
    final applying = c.applyChatPrefill(const ChatPrefill(text: '20lô10\n30lô5', customer: 'An', date: '2026-10-15', station: 'mn-dongnai'));
    await init;
    await applying;
    expect(c.selectedName, 'An');
    expect(c.entryDate, todayIso()); // the entry date is always today; the chat's date is not used
    expect(c.station, 'mn-dongnai'); // không phải đài mặc định 'mt' của khách
    expect(c.fromChat, isTrue);
    expect(c.takeBoxPrefill(), '20lô10\n30lô5');
    expect(c.takeBoxPrefill(), isNull);
    c.dispose();
  });

  test('Tính điểm mở sẵn đúng khách và ngày, kèm thông báo; khách không có thì giữ nguyên', () async {
    final api = ApiClient(AuthStore()..token = 't', client: MockClient((_) async => throw http.ClientException('offline')));
    final c = ScoringController(api, testStations(), today: '2026-10-16');
    c.customers = [const CustomerRec(id: 'c1', name: 'An')];
    expect(c.focusOn(customer: 'Không có', date: '2026-10-15', added: 2), isFalse);
    expect(c.selectedCustomer, '');
    expect(c.focusOn(customer: 'An', date: '2026-10-15', added: 3), isTrue);
    expect(c.selectedCustomer, 'An');
    expect(c.dateFrom, '2026-10-15');
    expect(c.dateTo, '2026-10-15');
    expect(c.notice, 'Đã thêm 3 số liệu cho An ngày 15/10/2026. Điểm ra được tính theo kết quả xổ số đã nhập.');
    c.dispose();
  });
}
