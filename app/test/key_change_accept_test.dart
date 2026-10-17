import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/e2ee_crypto.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';

class _Sock extends RealtimeSocket {
  _Sock() : super(tokenProvider: () => 't');
  @override
  bool get ready => true;
  @override
  void start() {}
  @override
  void send(Map<String, dynamic> frame) {}
}

void main() {
  test('"Đã hiểu" on a changed friend key sticks: the next refresh of the friend list does not flag it again', () async {
    final svc = ChatService(
      api: ApiClient(AuthStore(), client: MockClient((_) async => http.Response('{}', 404))),
      userId: 'me',
      store: MemoryChatStore(),
      vault: MemoryKeyVault(),
      socket: _Sock(),
    );
    final oldKey = E2eeIdentity.generate().publicJwk;
    final newKey = E2eeIdentity.generate().publicJwk;
    await svc.rememberFriends([{'id': 'f1', 'publicKey': oldKey}]);
    expect(svc.peerInfo['f1']!.changed, isFalse);

    await svc.rememberFriends([{'id': 'f1', 'publicKey': newKey}]); // the friend changed device
    expect(svc.peerInfo['f1']!.changed, isTrue);

    await svc.acceptKeyChange('f1');
    expect(svc.peerInfo['f1']!.changed, isFalse);

    await svc.rememberFriends([{'id': 'f1', 'publicKey': newKey}]); // the list is refreshed again
    expect(svc.peerInfo['f1']!.changed, isFalse, reason: 'the accepted key must be remembered, not the old one');

    await svc.rememberFriends([{'id': 'f1', 'publicKey': oldKey}]); // a different key later is a new change
    expect(svc.peerInfo['f1']!.changed, isTrue);
  });
}
