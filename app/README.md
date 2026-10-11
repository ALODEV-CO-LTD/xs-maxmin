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
