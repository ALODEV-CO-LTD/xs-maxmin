# MAMBA - ứng dụng Android (Flutter)

Ứng dụng khách hàng của MAMBA (nhập số, kết quả xổ số, tính điểm, khách hàng, bạn bè, cuộc gọi, tài khoản). Dùng chung API với bản web (`../backend`).

## Chạy

```bash
flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2:8080     # emulator + backend local
flutter run                                                  # máy chủ thật (https://xs.massagehomeriyadh.com)
flutter build apk --release
```

Cần Android SDK (Android Studio). `flutter doctor` phải xanh ở mục Android toolchain.

## Cấu trúc

- `lib/core`: cấu hình, API client, phiên đăng nhập, theme, định dạng, và phần dùng chung (đài/miền, cấu hình tính điểm, loại đánh).
- `lib/features/<tên>`: mỗi màn hình một thư mục.
- `lib/app.dart`: router (go_router) + providers.

## Ký bản release

Mặc định bản release ký bằng khoá debug. Để dùng khoá thật: `keytool -genkey -v -keystore ~/mamba-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mamba`, rồi copy `android/key.properties.example` thành `android/key.properties` (đã gitignore) và điền storeFile/storePassword/keyAlias/keyPassword. Giữ keystore và mật khẩu an toàn, đừng commit.

CẢNH BÁO: đổi khoá ký làm hỏng cập nhật cài đè. Máy đã cài bản ký bằng khoá debug sẽ KHÔNG cập nhật được bằng APK ký khoá khác (phải gỡ app, mất dữ liệu chat cục bộ).
