/// Chính sách mật khẩu đăng nhập (lớp 1). Chỉ áp dụng khi ĐẶT mật khẩu mới
/// (đăng ký, đổi mật khẩu, khôi phục) - tài khoản cũ có mật khẩu yếu vẫn đăng
/// nhập bình thường vì đăng nhập không gọi hàm này.
const minPasswordLength = 8;

/// Mật khẩu phổ biến nhất (đã so khớp không phân biệt hoa/thường).
const _common = <String>{
  '123456', '1234567', '12345678', '123456789', '1234567890', '12345', '1234',
  '123123', '123321', '111111', '000000', '121212', '654321', '666666', '888888',
  '999999', '112233', '102030', '11111111', '00000000', '12341234', '123456789a',
  'password', 'password1', 'password123', 'passw0rd', 'p@ssw0rd', 'p@ssword',
  'qwerty', 'qwerty123', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm', 'abc123',
  'abcd1234', 'abcdefgh', 'abcdef', 'iloveyou', 'admin', 'admin123', 'letmein',
  'welcome', 'monkey', 'dragon', 'football', 'login', 'master', 'sunshine',
  'matkhau', 'matkhau123', 'mat khau', 'matkhau1', 'xoso', 'xoso123', 'xosomaxmin',
  'maxmin', 'maxmin123', 'vietnam', 'anhyeuem', 'yeuem', 'iloveu',
};

/// Trả về thông báo lỗi tiếng Việt nếu [password] không đạt, hoặc null nếu hợp lệ.
String? validateNewPassword(String password) {
  if (password.length < minPasswordLength) {
    return 'Mật khẩu phải có ít nhất $minPasswordLength ký tự';
  }
  final lower = password.toLowerCase();
  if (_common.contains(lower)) {
    return 'Mật khẩu quá phổ biến, dễ bị đoán. Vui lòng chọn mật khẩu khác';
  }
  if (_isRepeatedChar(password)) {
    return 'Mật khẩu không được chỉ lặp lại một ký tự';
  }
  if (_isSequence(lower)) {
    return 'Mật khẩu không được là dãy số/chữ liên tiếp (vd 12345678, abcdefgh)';
  }
  return null;
}

bool _isRepeatedChar(String s) => s.isNotEmpty && s.runes.every((r) => r == s.runes.first);

/// True for a run that goes up (or down) by exactly 1 each step, e.g.
/// "12345678", "87654321", "abcdefgh".
bool _isSequence(String s) {
  final r = s.runes.toList();
  if (r.length < 2) return false;
  final step = r[1] - r[0];
  if (step != 1 && step != -1) return false;
  for (var i = 1; i < r.length; i++) {
    if (r[i] - r[i - 1] != step) return false;
  }
  return true;
}
