/// Build-time settings. Point the app at another server with
/// `flutter run --dart-define=API_BASE=http://10.0.2.2:8080` (10.0.2.2 = the host machine from the Android emulator).
class AppConfig {
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://xs.massagehomeriyadh.com');

  /// REST base, e.g. https://host/api
  static String get api => '$apiBase/api';

  /// WebSocket for calls / realtime chat: wss://host/api/ws/calls
  static String get wsCalls {
    final u = Uri.parse(apiBase);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${u.authority}/api/ws/calls';
  }
}
