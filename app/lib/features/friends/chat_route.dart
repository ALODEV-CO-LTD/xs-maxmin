import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'friends_controller.dart';
import 'messaging_host.dart';

/// `/friends/chat/:id`, the target of notification and banner taps. Waits for the hub, then shows the conversation.
class ChatRoutePage extends StatelessWidget {
  const ChatRoutePage({super.key, required this.friendId});
  final String friendId;

  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    if (hub == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final Friend? f = hub.friends.where((x) => x.id == friendId).firstOrNull ?? hub.groups.where((x) => x.id == friendId).firstOrNull;
        if (f != null && hub.chat != null) return ChatPage(controller: hub, friend: f);
        if (hub.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return Scaffold(appBar: AppBar(), body: const Center(child: Text('Không tìm thấy cuộc trò chuyện này.')));
      },
    );
  }
}
