// On a phone / emulator: the chat history and the private key are still there after the chat store is closed and opened
// again (what happens at every logout + login, and at every app start). Uses the real sqlite and the real secure storage.
//   flutter test integration_test/chat_persistence_test.dart -d <device>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('messages, settings and the key survive closing and reopening the store (logout + login)', (t) async {
    final user = 'persist-${DateTime.now().millisecondsSinceEpoch}';
    var store = await SqliteChatStore.open(user);
    await store.putMessage(ChatMessage(id: 'm1', peerId: 'f1', mine: true, text: 'xin chào', createdAt: 1, status: 'sent'));
    await store.putMessage(ChatMessage(id: 'm2', peerId: 'f1', mine: false, text: 'chào bạn', createdAt: 2, status: 'delivered'));
    await store.setMeta('pin:f1', 'm1');
    await store.close();

    // "logout, then login again": a new store object on the same account
    store = await SqliteChatStore.open(user);
    expect((await store.messagesOf('f1')).map((m) => m.text), ['xin chào', 'chào bạn']);
    expect(await store.meta('pin:f1'), 'm1');
    await store.close();

    // another account on the same phone has its own history
    final other = await SqliteChatStore.open('$user-other');
    expect(await other.messagesOf('f1'), isEmpty);
    await other.close();

    // the private key is kept by the secure storage between runs
    const vault = SecureKeyVault();
    await vault.write('mamba_test_key_$user', 'abc');
    expect(await vault.read('mamba_test_key_$user'), 'abc');
  });
}
