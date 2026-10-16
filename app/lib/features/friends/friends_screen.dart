import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'chat_page.dart';
import 'friends_controller.dart';
import 'messaging_host.dart';
import 'messaging_settings.dart';

/// Bạn bè: friend list (unread / missed-call badges), search and add by name or Mã ID, and the E2EE chat + voice
/// calls (FriendsView.vue). The WebSocket, chat and call services are the APP-level ones (see MessagingHost): this
/// screen only shows them.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _search = TextEditingController();
  bool _copied = false;
  FriendsController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = MessagingScope.maybeOf(context);
    if (c != null && !identical(c, _c)) {
      _c = c;
      // Fresh data every time the screen opens; the services themselves are already running.
      c.refreshFriendList(quiet: true);
      c.pollUnread();
      c.loadUnseenMissed();
      WidgetsBinding.instance.addPostFrameCallback((_) => _askNotifications(c));
    }
  }

  /// First visit: explain why notifications matter, then ask (Android 13+ shows its own dialog).
  Future<void> _askNotifications(FriendsController c) async {
    if (!mounted || c.notificationsAsked || await c.notifier.allowed) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bật thông báo?'),
        content: const Text('Tin nhắn được mã hoá 2 đầu và không lưu trên máy chủ, nên chỉ nhận được khi ứng dụng đang chạy. Bật thông báo để biết khi có tin nhắn hoặc cuộc gọi đến. Thông báo chỉ ghi "Tin nhắn mới từ <tên>", không hiện nội dung.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Để sau')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bật thông báo')),
        ],
      ),
    );
    if (ok == true) {
      await c.requestNotificationPermission(force: true);
    } else {
      await c.skipNotificationPrompt();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis)));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openChat(Friend? f) {
    if (f == null || _c == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatPage(controller: _c!, friend: f)));
  }

  Future<void> _remove(Friend f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá bạn bè'),
        content: Text('Xoá bạn bè "${f.name}"? Cuộc trò chuyện sẽ không còn hiển thị.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Xoá', style: TextStyle(color: ctx.badColor))),
        ],
      ),
    );
    if (ok != true) return;
    final err = await _c!.removeFriend(f);
    if (err != null) _snack(err);
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bạn bè & tin nhắn'),
        actions: [if (c != null) IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Cài đặt tin nhắn', onPressed: () => showMessagingSettings(context, c))],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: Listenable.merge([c, c.chat]),
              builder: (context, _) => _body(context, c),
            ),
    );
  }

  Widget _body(BuildContext context, FriendsController c) {
    final theme = Theme.of(context);
    final q = c.searchQuery.trim();
    final friends = c.filteredFriends;
    return RefreshIndicator(
      onRefresh: () async {
        await c.chat?.loadFriendKeys();
        await c.refreshFriendList();
        await c.pollUnread();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.myCode.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ID của bạn', style: theme.textTheme.labelLarge?.copyWith(color: context.mutedColor)),
                      Text(c.myCode, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 3, color: theme.colorScheme.primary)),
                    ]),
                  ),
                  OutlinedButton(onPressed: () => _copyCode(c.myCode), child: Text(_copied ? 'Đã chép' : 'Sao chép')),
                ]),
              ),
            )
          else if (c.noMyCode)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có ID. Tạo ID trong Tài khoản.', style: theme.textTheme.bodyMedium))),
          if (c.supportUnread > 0) ...[
            const SizedBox(height: 8),
            Card(child: ListTile(leading: const Icon(Icons.support_agent), title: Text('Có ${c.supportUnread} phản hồi mới từ Admin'), subtitle: const Text('Chạm để xem Hỗ trợ từ Admin'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/support'))),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: c.setSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tên, tài khoản hoặc mã ID (6-12 số)…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), tooltip: 'Xoá', onPressed: () { _search.clear(); c.setSearch(''); }),
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text('Lọc bạn bè của bạn và tìm người mới để kết bạn.', style: theme.textTheme.bodySmall?.copyWith(color: context.mutedColor))),
          if (c.searchError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.searchError, style: TextStyle(color: context.badColor))),
          if (q.isNotEmpty && (c.searching || c.newPeople.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Text('Người mới', style: theme.textTheme.titleSmall),
            if (c.searching && c.newPeople.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Đang tìm…')),
            for (final r in c.newPeople)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  title: Text(r.name),
                  subtitle: Text('@${r.username}'),
                  trailing: FilledButton.tonal(onPressed: c.addingId == r.id ? null : () => c.addFriend(r), child: Text(c.addingId == r.id ? '…' : 'Kết bạn')),
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (c.loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (c.loadError.isNotEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [Text(c.loadError, style: TextStyle(color: context.badColor)), TextButton(onPressed: c.refreshFriendList, child: const Text('Thử lại'))])))
          else ...[
            if (q.isNotEmpty && friends.isNotEmpty) Text('Bạn bè', style: theme.textTheme.titleSmall),
            if (c.friends.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bạn bè nào.')))
            else if (friends.isEmpty && q.isNotEmpty)
              (!c.searching && c.newPeople.isEmpty)
                  ? Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Không tìm thấy ai khớp với "$q". Nếu là mã ID, hãy kiểm tra lại các chữ số.')))
                  : const SizedBox.shrink()
            else
              for (final f in friends) _friendTile(context, c, f),
          ],
        ],
      ),
    );
  }

  Widget _friendTile(BuildContext context, FriendsController c, Friend f) {
    final theme = Theme.of(context);
    final unread = c.chat?.unread[f.id] ?? 0;
    final missed = c.unseenMissed[f.id] ?? 0;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        onTap: () => _openChat(f),
        leading: CircleAvatar(backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2), child: Text(f.name.isEmpty ? '?' : f.name.characters.first.toUpperCase())),
        title: Row(children: [
          Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (unread > 0) ...[const SizedBox(width: 8), _Badge(text: unread > 99 ? '99+' : '$unread', color: theme.colorScheme.primary)],
          if (missed > 0) ...[const SizedBox(width: 6), _Badge(text: '☎ $missed', color: context.badColor)],
        ]),
        subtitle: Text(f.lastMessage ?? 'Chưa có tin nhắn', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread > 0 ? FontWeight.w700 : null)),
        trailing: IconButton(icon: const Icon(Icons.person_remove_outlined), tooltip: 'Xoá bạn bè', onPressed: () => _remove(f)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
