import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'password_rules.dart';

String errorText(Object e) => e is ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại';

// ---------------------------------------------------------------- Register

enum RegisterStage { account, security, recoveryCode, secondPassword }

class RegisterDraft {
  RegisterDraft({this.name = '', this.username = '', this.password = '', this.confirm = '', this.second = '', this.wipe = '', this.wipeEnabled = false});
  String name, username, password, confirm, second, wipe;
  bool wipeEnabled;
}

/// Field errors of step 1 (keys: name, username, password, confirmPassword). Empty map = valid.
Map<String, String> registerAccountErrors(RegisterDraft d) {
  final e = <String, String>{};
  if (d.name.trim().isEmpty) e['name'] = 'Vui lòng nhập tên hiển thị';
  if (d.username.trim().length < 3) e['username'] = 'Tên đăng nhập phải có ít nhất 3 ký tự';
  final p = passwordProblem(d.password);
  if (p != null) e['password'] = p;
  if (d.confirm.isEmpty) {
    e['confirmPassword'] = 'Vui lòng nhập lại mật khẩu';
  } else if (d.confirm != d.password) {
    e['confirmPassword'] = 'Mật khẩu xác nhận không khớp';
  }
  return e;
}

/// Field errors of step 2 (keys: secondPassword, wipePassword).
Map<String, String> registerSecurityErrors(RegisterDraft d) {
  final e = <String, String>{};
  final s = passwordProblem(d.second);
  if (s != null) e['secondPassword'] = s;
  if (d.wipeEnabled) {
    final w = wipePasswordProblem(d.wipe, password: d.password, second: d.second);
    if (w != null) e['wipePassword'] = w;
  }
  return e;
}

/// Stage machine of /register: account -> security -> (POST /auth/register) recovery code shown once -> second
/// password re-typed (POST /auth/step2) -> signed in. Holds no password beyond the call that needs it.
class RegisterFlow extends ChangeNotifier {
  RegisterFlow({required this.api, required this.auth});
  final ApiClient api;
  final AuthStore auth;

  RegisterStage stage = RegisterStage.account;
  bool loading = false;
  String? error;

  /// Shown once; dropped on [recoveryConfirmed].
  String? recoveryCode;
  String _pendingToken = '';

  bool nextFromAccount(RegisterDraft d) {
    if (registerAccountErrors(d).isNotEmpty) return false;
    error = null;
    stage = RegisterStage.security;
    notifyListeners();
    return true;
  }

  void backToAccount() {
    error = null;
    stage = RegisterStage.account;
    notifyListeners();
  }

  Future<void> submit(RegisterDraft d) async {
    error = null;
    if (registerAccountErrors(d).isNotEmpty) {
      stage = RegisterStage.account;
      notifyListeners();
      return;
    }
    if (registerSecurityErrors(d).isNotEmpty) {
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final wipe = d.wipeEnabled ? d.wipe.trim() : '';
      final res = await api.post('/auth/register', {
        'name': d.name.trim(),
        'username': d.username.trim(),
        'password': d.password,
        'secondPassword': d.second,
        if (wipe.isNotEmpty) 'wipePassword': wipe,
      });
      final m = res is Map ? res : const {};
      if (m['stage'] == 'second_password_required' && m['pendingToken'] is String) {
        _pendingToken = m['pendingToken'] as String;
        final code = m['recoveryCode'];
        recoveryCode = code is String && code.isNotEmpty ? code : null;
        stage = recoveryCode != null ? RegisterStage.recoveryCode : RegisterStage.secondPassword;
      } else {
        error = 'Phản hồi không xác định từ máy chủ';
      }
    } catch (e) {
      error = errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void recoveryConfirmed() {
    recoveryCode = null;
    stage = RegisterStage.secondPassword;
    notifyListeners();
  }

  Future<void> submitStep2(String password) async {
    error = null;
    if (password.isEmpty) {
      error = 'Vui lòng nhập mật khẩu lớp hai vừa đặt';
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final res = await api.post('/auth/step2', {'pendingToken': _pendingToken, 'password': password});
      final m = res is Map ? res : const {};
      if (m['token'] is String) {
        await auth.login(m['token'] as String, m['role'] as String?);
      } else {
        error = m['stage'] == 'wipe_confirmation_required' ? 'Mật khẩu không khớp với mật khẩu lớp hai vừa đặt' : 'Phản hồi không xác định từ máy chủ';
      }
    } catch (e) {
      error = errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

// ----------------------------------------------------------------- Recover

enum RecoverStage { recover, helpRequest, helpSent, ticket, recoveryCode }

/// Stage machine of /recover: code recovery, or the admin-assisted flow (recovery-request -> ticket).
class RecoverFlow extends ChangeNotifier {
  RecoverFlow({required this.api});
  final ApiClient api;

  RecoverStage stage = RecoverStage.recover;
  bool loading = false;
  String? error;
  String helpMessage = '';

  /// The NEW code, shown once.
  String? newRecoveryCode;

  void go(RecoverStage s) {
    error = null;
    stage = s;
    notifyListeners();
  }

  String? _newPasswordError(String pw, String confirm) {
    if (pw.isEmpty) return 'Vui lòng nhập mật khẩu mới';
    final p = passwordProblem(pw);
    if (p != null) return p;
    if (pw != confirm) return 'Mật khẩu nhập lại không khớp';
    return null;
  }

  Future<void> _run(Future<void> Function() body) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      error = errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _fail(String msg) {
    error = msg;
    notifyListeners();
  }

  Future<void> submitRecover({required String username, required String code, required String newPassword, required String confirm}) async {
    if (username.trim().isEmpty || code.trim().isEmpty) return _fail('Vui lòng nhập tên đăng nhập và mã khôi phục');
    final pe = _newPasswordError(newPassword, confirm);
    if (pe != null) return _fail(pe);
    await _run(() async {
      final res = await api.post('/auth/recover', {'username': username.trim(), 'recoveryCode': code.trim(), 'newPassword': newPassword});
      _gotNewCode(res);
    });
  }

  Future<void> submitHelp({required String username, required String note}) async {
    if (username.trim().isEmpty) return _fail('Vui lòng nhập tên đăng nhập');
    await _run(() async {
      final res = await api.post('/auth/recovery-request', {'username': username.trim(), 'note': note.trim()});
      helpMessage = res is Map && res['message'] is String ? res['message'] as String : 'Đã ghi nhận yêu cầu.';
      stage = RecoverStage.helpSent;
    });
  }

  Future<void> submitTicket({required String username, required String ticket, required String newPassword, required String confirm}) async {
    if (username.trim().isEmpty || ticket.trim().isEmpty) return _fail('Vui lòng nhập tên đăng nhập và mã hỗ trợ');
    final pe = _newPasswordError(newPassword, confirm);
    if (pe != null) return _fail(pe);
    await _run(() async {
      final res = await api.post('/auth/recover-with-ticket', {'username': username.trim(), 'ticket': ticket.trim(), 'newPassword': newPassword});
      _gotNewCode(res);
    });
  }

  void _gotNewCode(dynamic res) {
    final code = res is Map ? res['recoveryCode'] : null;
    if (code is String && code.isNotEmpty) {
      newRecoveryCode = code;
      stage = RecoverStage.recoveryCode;
    } else {
      error = 'Phản hồi không xác định từ máy chủ';
    }
  }

  void codeConfirmed() {
    newRecoveryCode = null;
    notifyListeners();
  }
}
