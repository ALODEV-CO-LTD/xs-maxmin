import 'dart:convert';

/// Chính sách mật khẩu cho MỌI loại (đăng nhập, lớp hai, xoá dữ liệu).
/// Khách đặt gì tuỳ ý: không bắt độ dài tối thiểu, không chặn mật khẩu phổ biến
/// hay dãy số. Chỉ còn hai giới hạn kỹ thuật:
///  - không được để trống;
///  - tối đa [maxPasswordBytes] byte (UTF-8): bcrypt chỉ dùng 72 byte đầu, dài
///    hơn sẽ bị cắt ngầm nên từ chối cho rõ ràng (và tránh body quá lớn).
/// Ràng buộc "khác nhau" giữa các mật khẩu (xoá dữ liệu phải khác mật khẩu lớp hai
/// và mật khẩu đăng nhập) vẫn do từng route kiểm tra, vì chúng quyết định đăng nhập
/// bước 2 có kích hoạt xoá dữ liệu hay không.
const minPasswordLength = 1;
const maxPasswordBytes = 72;

/// Trả về thông báo lỗi tiếng Việt nếu [password] không đạt, hoặc null nếu hợp lệ.
String? validateNewPassword(String password) {
  if (password.isEmpty) return 'Vui lòng nhập mật khẩu';
  if (utf8.encode(password).length > maxPasswordBytes) {
    return 'Mật khẩu quá dài (tối đa $maxPasswordBytes ký tự)';
  }
  return null;
}
