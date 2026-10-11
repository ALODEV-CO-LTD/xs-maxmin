import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/auth_flows.dart';
import 'package:mamba_app/features/account/password_rules.dart';

/// AuthStore without secure storage (not available in unit tests).
class _MemAuth extends AuthStore {
  @override
  Future<void> login(String newToken, String? newRole) async {
    token = newToken;
    role = newRole ?? 'user';
    notifyListeners();
  }
}

(ApiClient, _MemAuth, List<http.Request>) _api(Map<String, http.Response Function(http.Request)> routes) {
  final seen = <http.Request>[];
  final auth = _MemAuth();
  final api = ApiClient(auth, client: MockClient((req) async {
    seen.add(req);
    final h = routes[req.url.path.replaceFirst('/api', '')];
    return h != null ? h(req) : http.Response('{"error":"not found"}', 404);
  }));
  return (api, auth, seen);
}

http.Response _json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('password rules', () {
    test('any length >= 1 is fine, empty is not', () {
      expect(passwordProblem('a'), isNull);
      expect(passwordProblem(''), isNotNull);
    });
    test('72 bytes ok, 73 bytes too long (bytes, not characters)', () {
      expect(passwordProblem('a' * 72), isNull);
      expect(passwordProblem('a' * 73), contains('72'));
      // 'ế' is 3 bytes in UTF-8: 24 chars = 72 bytes, 25 chars = 75 bytes.
      expect(passwordProblem('ế' * 24), isNull);
      expect(passwordProblem('ế' * 25), isNotNull);
    });
    test('wipe password is optional but must differ from the others', () {
      expect(wipePasswordProblem('', password: 'p', second: 's'), isNull);
      expect(wipePasswordProblem('p', password: 'p', second: 's'), isNotNull);
      expect(wipePasswordProblem('s', password: 'p', second: 's'), isNotNull);
      expect(wipePasswordProblem(' p ', password: 'p', second: 's'), isNotNull, reason: 'the backend trims it');
      expect(wipePasswordProblem('w', password: 'p', second: 's'), isNull);
      expect(wipePasswordProblem('x' * 73, password: 'p', second: 's'), isNotNull);
    });
  });

  group('register validation', () {
    test('step 1 errors', () {
      final e = registerAccountErrors(RegisterDraft(name: ' ', username: 'ab', password: '', confirm: ''));
      expect(e.keys, containsAll(['name', 'username', 'password', 'confirmPassword']));
      expect(registerAccountErrors(RegisterDraft(name: 'A', username: 'abc', password: 'x', confirm: 'y')).keys, ['confirmPassword']);
      expect(registerAccountErrors(RegisterDraft(name: 'A', username: 'abc', password: 'x', confirm: 'x')), isEmpty);
    });
    test('step 2: second password required, wipe only checked when enabled', () {
      expect(registerSecurityErrors(RegisterDraft(password: 'p')).keys, ['secondPassword']);
      expect(registerSecurityErrors(RegisterDraft(password: 'p', second: 's', wipe: 'p')), isEmpty);
      expect(registerSecurityErrors(RegisterDraft(password: 'p', second: 's', wipe: 'p', wipeEnabled: true)).keys, ['wipePassword']);
    });
  });

  group('RegisterFlow', () {
    RegisterDraft good() => RegisterDraft(name: ' An ', username: ' an123 ', password: 'pw', confirm: 'pw', second: 'sw', wipe: '', wipeEnabled: true);

    test('account -> security -> code -> step2 -> signed in', () async {
      Map<String, dynamic>? registerBody;
      final (api, auth, _) = _api({
        '/auth/register': (r) {
          registerBody = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'stage': 'second_password_required', 'pendingToken': 'PT', 'recoveryCode': 'AAAA-BBBB'});
        },
        '/auth/step2': (r) {
          expect(jsonDecode(r.body), {'pendingToken': 'PT', 'password': 'sw'});
          return _json({'token': 'TOK', 'role': 'user'});
        },
      });
      final flow = RegisterFlow(api: api, auth: auth);
      expect(flow.nextFromAccount(RegisterDraft(name: '', username: 'x')), isFalse);
      expect(flow.stage, RegisterStage.account);
      expect(flow.nextFromAccount(good()), isTrue);
      expect(flow.stage, RegisterStage.security);
      await flow.submit(good());
      expect(registerBody, {'name': 'An', 'username': 'an123', 'password': 'pw', 'secondPassword': 'sw'}, reason: 'empty wipe password is omitted, values are trimmed');
      expect(flow.stage, RegisterStage.recoveryCode);
      expect(flow.recoveryCode, 'AAAA-BBBB');
      flow.recoveryConfirmed();
      expect(flow.stage, RegisterStage.secondPassword);
      expect(flow.recoveryCode, isNull, reason: 'shown once, then dropped');
      await flow.submitStep2('');
      expect(flow.error, isNotNull);
      expect(auth.signedIn, isFalse);
      await flow.submitStep2('sw');
      expect(auth.token, 'TOK');
      expect(flow.error, isNull);
    });

    test('wipe password is sent trimmed when enabled; no recovery code skips to verification', () async {
      Map<String, dynamic>? body;
      final (api, auth, _) = _api({
        '/auth/register': (r) {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'stage': 'second_password_required', 'pendingToken': 'PT'});
        },
      });
      final flow = RegisterFlow(api: api, auth: auth);
      await flow.submit(RegisterDraft(name: 'A', username: 'abc', password: 'p', confirm: 'p', second: 's', wipe: ' w ', wipeEnabled: true));
      expect(body!['wipePassword'], 'w');
      expect(flow.stage, RegisterStage.secondPassword);
    });

    test('server error is shown and the stage stays', () async {
      final (api, auth, _) = _api({'/auth/register': (r) => _json({'error': 'Tên đăng nhập đã được sử dụng'}, 409)});
      final flow = RegisterFlow(api: api, auth: auth);
      await flow.submit(good());
      expect(flow.error, 'Tên đăng nhập đã được sử dụng');
      expect(flow.stage, RegisterStage.account);
      expect(flow.loading, isFalse);
    });

    test('invalid input never reaches the server', () async {
      final (api, auth, seen) = _api({});
      final flow = RegisterFlow(api: api, auth: auth);
      await flow.submit(RegisterDraft(name: 'A', username: 'abc', password: 'p', confirm: 'p', second: ''));
      expect(seen, isEmpty);
    });

    test('wipe_confirmation_required at step2 is reported, not signed in', () async {
      final (api, auth, _) = _api({
        '/auth/register': (r) => _json({'stage': 'second_password_required', 'pendingToken': 'PT'}),
        '/auth/step2': (r) => _json({'stage': 'wipe_confirmation_required', 'wipeToken': 'W'}),
      });
      final flow = RegisterFlow(api: api, auth: auth);
      await flow.submit(good());
      await flow.submitStep2('zzz');
      expect(auth.signedIn, isFalse);
      expect(flow.error, contains('không khớp'));
    });
  });

  group('RecoverFlow', () {
    test('recover with code shows the NEW code once', () async {
      Map<String, dynamic>? body;
      final (api, _, _) = _api({
        '/auth/recover': (r) {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'recoveryCode': 'NEW-CODE'});
        },
      });
      final f = RecoverFlow(api: api);
      await f.submitRecover(username: ' an ', code: ' ABCD ', newPassword: 'pw', confirm: 'pw');
      expect(body, {'username': 'an', 'recoveryCode': 'ABCD', 'newPassword': 'pw'});
      expect(f.stage, RecoverStage.recoveryCode);
      expect(f.newRecoveryCode, 'NEW-CODE');
      f.codeConfirmed();
      expect(f.newRecoveryCode, isNull);
    });

    test('validation: missing fields, mismatch, too long', () async {
      final (api, _, seen) = _api({});
      final f = RecoverFlow(api: api);
      await f.submitRecover(username: '', code: 'x', newPassword: 'a', confirm: 'a');
      expect(f.error, contains('mã khôi phục'));
      await f.submitRecover(username: 'u', code: 'x', newPassword: '', confirm: '');
      expect(f.error, 'Vui lòng nhập mật khẩu mới');
      await f.submitRecover(username: 'u', code: 'x', newPassword: 'a', confirm: 'b');
      expect(f.error, 'Mật khẩu nhập lại không khớp');
      await f.submitRecover(username: 'u', code: 'x', newPassword: 'a' * 73, confirm: 'a' * 73);
      expect(f.error, contains('72'));
      expect(seen, isEmpty);
    });

    test('admin-assisted: request -> sent -> ticket -> new code', () async {
      final (api, _, _) = _api({
        '/auth/recovery-request': (r) => _json({'message': 'Đã ghi nhận'}),
        '/auth/recover-with-ticket': (r) {
          expect((jsonDecode(r.body) as Map)['ticket'], 'T-1');
          return _json({'recoveryCode': 'C2'});
        },
      });
      final f = RecoverFlow(api: api);
      f.go(RecoverStage.helpRequest);
      await f.submitHelp(username: 'an', note: ' hi ');
      expect(f.stage, RecoverStage.helpSent);
      expect(f.helpMessage, 'Đã ghi nhận');
      f.go(RecoverStage.ticket);
      await f.submitTicket(username: 'an', ticket: ' T-1 ', newPassword: 'p', confirm: 'p');
      expect(f.stage, RecoverStage.recoveryCode);
      expect(f.newRecoveryCode, 'C2');
    });

    test('server errors keep the stage', () async {
      final (api, _, _) = _api({'/auth/recover': (r) => _json({'error': 'Mã khôi phục không đúng'}, 400)});
      final f = RecoverFlow(api: api);
      await f.submitRecover(username: 'u', code: 'x', newPassword: 'p', confirm: 'p');
      expect(f.error, 'Mã khôi phục không đúng');
      expect(f.stage, RecoverStage.recover);
    });
  });
}
