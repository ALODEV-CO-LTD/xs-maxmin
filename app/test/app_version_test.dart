import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/app_version.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/shell/update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

ApiClient _api(String body, {int status = 200, bool fail = false}) => ApiClient(
      AuthStore(),
      client: MockClient((req) async {
        if (fail) throw http.ClientException('offline');
        return http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

String _json({String latest = '', String min = '', String url = '', String notes = ''}) => jsonEncode({'latestVersion': latest, 'minVersion': min, 'downloadUrl': url, 'notes': notes});

Future<void> _pump(WidgetTester t, ApiClient api, {String current = '1.2.0'}) async {
  await t.pumpWidget(MaterialApp(home: UpdateGate(key: UniqueKey(), api: api, currentVersion: current, child: const Scaffold(body: Center(child: Text('NOI DUNG APP'))))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('compareVersions and updateNeed', () {
    expect(compareVersions('1.2.0', '1.10.0'), -1);
    expect(compareVersions('1.2.0', 'x'), isNull);
    expect(updateNeed('1.2.0', const AppVersionInfo()), UpdateNeed.none);
    expect(updateNeed('1.2.0', const AppVersionInfo(latest: '1.3.0')), UpdateNeed.optional);
    expect(updateNeed('1.2.0', const AppVersionInfo(latest: '1.3.0', min: '1.2.5')), UpdateNeed.required);
    expect(updateNeed('1.3.0', const AppVersionInfo(latest: '1.3.0', min: '1.2.5')), UpdateNeed.none);
    expect(updateNeed('2.0.0', const AppVersionInfo(latest: '1.3.0')), UpdateNeed.none);
    expect(updateNeed('1.2.0', const AppVersionInfo(latest: 'abc', min: 'zz')), UpdateNeed.none); // junk never blocks
  });

  test('validateAppVersionForm mirrors the server rules', () {
    expect(validateAppVersionForm(const AppVersionInfo()), isNull);
    expect(validateAppVersionForm(const AppVersionInfo(latest: '1.2')), isNotNull);
    expect(validateAppVersionForm(const AppVersionInfo(min: '1.0.0')), isNotNull);
    expect(validateAppVersionForm(const AppVersionInfo(latest: '1.0.0', min: '1.1.0')), isNotNull);
    expect(validateAppVersionForm(const AppVersionInfo(latest: '1.1.0', min: '1.0.0', downloadUrl: 'http://x.y/a.apk')), isNotNull);
    expect(validateAppVersionForm(const AppVersionInfo(latest: '1.1.0', min: '1.0.0', downloadUrl: 'https://x.y/a.apk')), isNull);
    expect(validateAppVersionForm(AppVersionInfo(notes: 'x' * 501)), isNotNull);
  });

  testWidgets('below the minimum: full-screen block', (t) async {
    await _pump(t, _api(_json(latest: '1.3.0', min: '1.2.5', url: 'https://example.com/MAMBA.apk', notes: 'Sửa lỗi')));
    expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
    expect(find.text('Tải bản mới'), findsOneWidget);
  });

  testWidgets('below the newest: a card that can be dismissed and is remembered', (t) async {
    await _pump(t, _api(_json(latest: '1.3.0', url: 'https://example.com/MAMBA.apk')));
    expect(find.text('Có phiên bản mới 1.3.0'), findsOneWidget);
    expect(find.text('NOI DUNG APP'), findsOneWidget); // the app stays usable
    await t.tap(find.text('Để sau'));
    await t.pumpAndSettle();
    expect(find.text('Có phiên bản mới 1.3.0'), findsNothing);
    await _pump(t, _api(_json(latest: '1.3.0', url: 'https://example.com/MAMBA.apk')));
    expect(find.text('Có phiên bản mới 1.3.0'), findsNothing); // same version: not shown again
    await _pump(t, _api(_json(latest: '1.4.0')));
    expect(find.text('Có phiên bản mới 1.4.0'), findsOneWidget); // a newer version shows again
  });

  testWidgets('up to date, offline or junk answer: nothing is shown', (t) async {
    await _pump(t, _api(_json(latest: '1.2.0', min: '1.0.0')));
    expect(find.text('NOI DUNG APP'), findsOneWidget);
    expect(find.text('Cần cập nhật ứng dụng'), findsNothing);
    await _pump(t, _api('', fail: true));
    expect(find.text('Cần cập nhật ứng dụng'), findsNothing);
    await _pump(t, _api('{}', status: 500));
    expect(find.text('Cần cập nhật ứng dụng'), findsNothing);
  });
}
