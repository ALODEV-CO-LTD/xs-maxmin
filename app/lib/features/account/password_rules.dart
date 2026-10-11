import 'dart:convert';

/// Password policy shared by every password (login, layer 2, wipe): any length >= 1, at most 72 UTF-8 bytes
/// (bcrypt's limit). Mirrors backend/lib/src/password_policy.dart and RegisterView.vue.
const maxPasswordBytes = 72;

/// Returns a Vietnamese error message, or null when [v] is acceptable.
String? passwordProblem(String v) {
  if (v.isEmpty) return 'Vui lòng nhập mật khẩu';
  if (utf8.encode(v).length > maxPasswordBytes) return 'Mật khẩu quá dài (tối đa $maxPasswordBytes ký tự)';
  return null;
}

/// The optional wipe password: empty is fine; otherwise it must be valid and differ from the other two.
/// The backend trims it before comparing, so the comparison is done on the trimmed value as well.
String? wipePasswordProblem(String wipe, {required String password, required String second}) {
  final w = wipe.trim();
  if (w.isEmpty) return null;
  final p = passwordProblem(w);
  if (p != null) return p;
  if (w == password || w == second) return 'Mật khẩu xoá dữ liệu phải khác 2 mật khẩu còn lại';
  return null;
}
