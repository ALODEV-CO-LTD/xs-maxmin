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
  final _searchFocus = FocusNode();
  bool _copied = false;
  bool _edit = false; // Sửa: pick conversations to archive / delete
  bool _showArchived = false;
  final Set<String> _picked = {};
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

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openChat(Friend? f) {
    if (f == null || _c == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatPage(controller: _c!, friend: f)));
  }

  void _toggleEdit() => setState(() { _edit = !_edit; _picked.clear(); });

  Future<void> _archivePicked(FriendsController c) async {
    await c.chat?.setArchived(_picked.toList(), !_showArchived);
    if (mounted) _toggleEdit();
  }

  Future<void> _deletePicked(FriendsController c) async {
    final ids = _picked.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá cuộc trò chuyện'),
        content: Text('Xoá ${ids.length} cuộc trò chuyện khỏi máy này? Tin nhắn và ảnh trong đó sẽ mất trên máy này (người kia vẫn giữ bản của họ). Bạn bè vẫn còn trong danh bạ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Xoá', style: TextStyle(color: ctx.badColor))),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in ids) {
      await c.chat?.deleteConversation(id);
    }
    await c.refreshFriendList(quiet: true);
    if (mounted) _toggleEdit();
  }

  /// "Mới": Tin nhắn mới / Nhóm mới / Danh bạ mới.
  Future<void> _newMenu(FriendsController c) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(12), child: Text('Tạo mới', style: TextStyle(fontWeight: FontWeight.w700))),
          ListTile(title: const Text('Tin nhắn mới'), onTap: () => Navigator.pop(ctx, 'message')),
          ListTile(title: const Text('Nhóm mới'), onTap: () => Navigator.pop(ctx, 'group')),
          ListTile(title: const Text('Danh bạ mới'), onTap: () => Navigator.pop(ctx, 'contact')),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'message':
        final friends = [...c.friends]..sort((a, b) => foldVi(c.nameOf(a)).compareTo(foldVi(c.nameOf(b))));
        final f = await showDialog<Friend>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Tin nhắn mới'),
            children: [
              if (friends.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bạn bè. Chọn Danh bạ mới để tìm người và kết bạn.')),
              for (final f in friends) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, f), child: Text(c.nameOf(f))),
            ],
          ),
        );
        if (f != null && mounted) {
          setState(() => _showArchived = false);
          _openChat(f);
        }
      case 'group':
        await showDialog<void>(context: context, builder: (ctx) => _GroupDialog(friends: c.friends, nameOf: c.nameOf));
      default:
        _searchFocus.requestFocus();
    }
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
    final all = c.filteredFriends;
    final archived = c.chat?.archived ?? const <String>{};
    final friends = [for (final f in all) if (archived.contains(f.id) == _showArchived) f];
    final archivedCount = c.friends.where((f) => archived.contains(f.id)).length;
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
          Row(children: [
            TextButton(onPressed: _toggleEdit, child: Text(_edit ? 'Xong' : 'Sửa')),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: c.setSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), tooltip: 'Xoá', onPressed: () { _search.clear(); c.setSearch(''); }),
                ),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(onPressed: () => _newMenu(c), child: const Text('Mới', style: TextStyle(fontWeight: FontWeight.w700))),
          ]),
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
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bạn bè nào. Bấm Mới > Danh bạ mới để tìm và kết bạn.')))
            else if (friends.isEmpty)
              if (q.isNotEmpty)
                (!c.searching && c.newPeople.isEmpty)
                    ? Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Không tìm thấy ai khớp với "$q". Nếu là mã ID, hãy kiểm tra lại các chữ số.')))
                    : const SizedBox.shrink()
              else
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_showArchived ? 'Chưa lưu trữ cuộc trò chuyện nào.' : 'Chưa có cuộc trò chuyện nào. Bấm Mới > Tin nhắn mới để bắt đầu.')))
            else
              for (final f in friends) _friendTile(context, c, f),
            if (_edit)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(onPressed: _picked.isEmpty ? null : () => _archivePicked(c), child: Text('${_showArchived ? 'Bỏ lưu trữ' : 'Lưu trữ'}${_picked.isEmpty ? '' : ' (${_picked.length})'}')),
                TextButton(onPressed: _picked.isEmpty ? null : () => _deletePicked(c), child: Text('Xoá${_picked.isEmpty ? '' : ' (${_picked.length})'}', style: TextStyle(color: _picked.isEmpty ? null : context.badColor))),
              ])
            else if (archivedCount > 0 || _showArchived)
              Center(child: TextButton(onPressed: () => setState(() => _showArchived = !_showArchived), child: Text(_showArchived ? '← Về tin nhắn' : 'Đã lưu trữ ($archivedCount)'))),
          ],
        ],
      ),
    );
  }

  Widget _friendTile(BuildContext context, FriendsController c, Friend f) {
    final theme = Theme.of(context);
    final unread = c.chat?.unread[f.id] ?? 0;
    final missed = c.unseenMissed[f.id] ?? 0;
    final name = c.nameOf(f);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        onTap: _edit ? () => setState(() => _picked.contains(f.id) ? _picked.remove(f.id) : _picked.add(f.id)) : () => _openChat(f),
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_edit) Checkbox(value: _picked.contains(f.id), onChanged: (_) => setState(() => _picked.contains(f.id) ? _picked.remove(f.id) : _picked.add(f.id))),
          CircleAvatar(backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2), child: Text(initialOf(name))),
        ]),
        title: Row(children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (unread > 0) ...[const SizedBox(width: 8), _Badge(text: unread > 99 ? '99+' : '$unread', color: theme.colorScheme.primary)],
          if (missed > 0) ...[const SizedBox(width: 6), _Badge(text: '☎ $missed', color: context.badColor)],
        ]),
        subtitle: Text(f.lastMessage ?? 'Chưa có tin nhắn', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread > 0 ? FontWeight.w700 : null)),
      ),
    );
  }
}

/// First letter of a name, upper-case (web `initial`).
String initialOf(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first.toUpperCase();
}

/// "Nhóm mới": the sheet exists like on the web, but group chat is not on the server yet so "Tạo nhóm" stays disabled.
class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.friends, required this.nameOf});
  final List<Friend> friends;
  final String Function(Friend) nameOf;
  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final Set<String> _members = {};
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tạo nhóm'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const TextField(decoration: InputDecoration(hintText: 'Tên nhóm')),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                if (widget.friends.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Chưa có bạn bè nào để thêm vào nhóm.')),
                for (final f in widget.friends)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _members.contains(f.id),
                    title: Text(widget.nameOf(f)),
                    onChanged: (_) => setState(() => _members.contains(f.id) ? _members.remove(f.id) : _members.add(f.id)),
                  ),
              ]),
            ),
            const Text('Nhóm chat chưa có trên máy chủ nên chưa tạo được nhóm thật.', style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
          const FilledButton(onPressed: null, child: Text('Tạo nhóm')),
        ],
      );
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
