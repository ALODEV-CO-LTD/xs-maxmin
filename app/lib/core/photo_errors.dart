import 'package:flutter/services.dart';

/// Vietnamese sentence for a failed "take a photo / pick a photo" ([PlatformException] codes of image_picker), or null when
/// [e] is not one of those. Camera trouble is almost always a permission the person refused earlier (iPhone: the question is
/// asked only once), so the text says where to switch it back on.
String? describePhotoError(Object e) {
  if (e is! PlatformException) return null;
  switch (e.code) {
    case 'camera_access_denied':
      return 'MAMBA chưa được phép dùng camera. Vào Cài đặt của điện thoại > MAMBA > bật Camera, rồi thử lại.';
    case 'photo_access_denied':
      return 'MAMBA chưa được phép đọc ảnh. Vào Cài đặt của điện thoại > MAMBA > Ảnh, chọn cho phép, rồi thử lại.';
    case 'no_available_camera':
      return 'Thiết bị này không có camera (máy ảo không có camera thật). Hãy chọn ảnh từ thư viện.';
    case 'already_active':
      return 'Camera đang mở, hãy đóng rồi thử lại.';
  }
  return null;
}
