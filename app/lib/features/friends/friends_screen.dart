import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'chat_models.dart';
import 'chat_page.dart';
import 'friends_controller.dart';
import 'messaging_host.dart';
import 'messaging_settings.dart';
import '../../core/widgets/app_button.dart';

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
  bool _searching = false;
  final _searchFocus = FocusNode();
  bool _copied = false;
  bool _edit = false; // Sửa: pick conversations to archive / delete
  final Set<String> _picked = {};
  final _scroll = ScrollController();
  bool _showTop = false; // the round arrow that jumps back to the first conversation
  FriendsController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = MessagingScope.maybeOf(context);
    // Signed out (e.g. from another device): the hub is gone and disposed. Forget it, or this screen keeps listening to it.
    if (c == null) _c = null;
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
        content: const Text(
          'Tin nhắn được mã hoá 2 đầu và không lưu trên máy chủ, nên chỉ nhận được khi ứng dụng đang chạy. Bật thông báo để biết khi có tin nhắn hoặc cuộc gọi đến. Thông báo chỉ ghi "Tin nhắn mới từ <tên>", không hiện nội dung.',
        ),
        actions: [
          AppButton(
            label: 'Để sau',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppButton(
            label: 'Bật thông báo',
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.pop(ctx, true),
          ),
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
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openChat(Friend? f) {
    if (f == null || _c == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(controller: _c!, friend: f),
      ),
    );
  }

  void _onScroll() {
    final far = _scroll.hasClients && _scroll.offset > 600;
    if (far != _showTop) setState(() => _showTop = far);
  }

  void _toggleEdit() => setState(() {
    _edit = !_edit;
    _picked.clear();
  });

  Future<void> _archivePicked(FriendsController c) async {
    await c.chat?.setArchived(_picked.toList(), true);
    if (mounted) _toggleEdit();
  }

  Future<void> _deletePicked(FriendsController c) async {
    final done = await _deleteIds(c, _picked.toList());
    if (done && mounted) _toggleEdit();
  }

  /// Asks, then clears the conversations on this device (a group is left). Returns whether it was done.
  Future<bool> _deleteIds(FriendsController c, List<String> ids) async {
    if (ids.isEmpty) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá cuộc trò chuyện'),
        content: Text(
          'Xoá ${ids.length} cuộc trò chuyện khỏi máy này? Tin nhắn và ảnh trong đó sẽ mất trên máy này (người kia vẫn giữ bản của họ). Bạn bè vẫn còn trong danh bạ; nhóm thì bạn sẽ rời khỏi nhóm.',
        ),
        actions: [
          AppButton(
            label: 'Huỷ',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppButton(
            label: 'Xoá',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    for (final id in ids) {
      // A group is left (the members are told); a friend's conversation is only cleared on this device.
      if (isGroupId(id)) {
        await c.chat?.leaveGroup(id);
      } else {
        await c.chat?.deleteConversation(id);
      }
    }
    await c.refreshFriendList(quiet: true);
    return true;
  }

  /// Nhấn giữ một cuộc trò chuyện: Lưu trữ hoặc Xoá (nhóm thì Rời nhóm).
  Future<void> _rowMenu(FriendsController c, Friend f) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Align(alignment: Alignment.centerLeft, child: Text(c.nameOf(f), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
          ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Lưu trữ'), onTap: () => Navigator.pop(ctx, 'archive')),
          ListTile(
            leading: Icon(Icons.delete_outline, color: ctx.badColor),
            title: Text(f.isGroup ? 'Rời nhóm' : 'Xoá cuộc trò chuyện', style: TextStyle(color: ctx.badColor)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (pick == 'archive') {
      await c.chat?.setArchived([f.id], true);
    } else if (pick == 'delete') {
      await _deleteIds(c, [f.id]);
    }
  }

  /// "Thêm": Tin nhắn mới / Nhóm mới / Danh bạ mới.
  Future<void> _newMenu(FriendsController c) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Tạo mới',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              title: const Text('Tin nhắn mới'),
              onTap: () => Navigator.pop(ctx, 'message'),
            ),
            ListTile(
              title: const Text('Nhóm mới'),
              onTap: () => Navigator.pop(ctx, 'group'),
            ),
            ListTile(
              title: const Text('Danh bạ mới'),
              onTap: () => Navigator.pop(ctx, 'contact'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'message':
        final friends = [...c.friends]
          ..sort((a, b) => foldVi(c.nameOf(a)).compareTo(foldVi(c.nameOf(b))));
        final f = await showDialog<Friend>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Tin nhắn mới'),
            children: [
              if (friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Chưa có bạn bè. Chọn Danh bạ mới để tìm người và kết bạn.',
                  ),
                ),
              for (final f in friends)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, f),
                  child: Text(c.nameOf(f)),
                ),
            ],
          ),
        );
        if (f != null && mounted) {
          _openChat(f);
        }
      case 'group':
        final gid = await showDialog<String>(
          context: context,
          builder: (ctx) => _GroupDialog(controller: c),
        );
        if (gid != null && mounted) {
          await c.refreshFriendList(quiet: true);
          _openChat(c.groups.where((g) => g.id == gid).firstOrNull);
        }
      default:
        _openSearch();
    }
  }

  /// The search box lives in the top bar: opened by the magnifier (or by "Danh bạ mới"), closed by the X (clears the filter).
  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch(FriendsController c) {
    _search.clear();
    c.setSearch('');
    setState(() => _searching = false);
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// The ID used to be a card at the top of the list; now it is shown only when the person asks (the badge icon in the top bar).
  Future<void> _showMyId(FriendsController c) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: StatefulBuilder(
          builder: (sheet, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ID của bạn',
                  style: Theme.of(sheet).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Đưa ID này cho người muốn kết bạn với bạn.',
                  style: Theme.of(sheet).textTheme.bodySmall
                      ?.copyWith(color: sheet.mutedColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (c.myCode.isNotEmpty) ...[
                  SelectableText(
                    c.myCode,
                    textAlign: TextAlign.center,
                    style: Theme.of(sheet).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: Theme.of(sheet).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: _copied ? 'Đã chép' : 'Sao chép',
                    icon: Icons.copy,
                    variant: AppButtonVariant.primary,
                    onPressed: () async {
                      await _copyCode(c.myCode);
                      if (sheet.mounted) setSheet(() {});
                    },
                  ),
                ] else
                  Text(
                    'Chưa có ID. Tạo ID trong Tài khoản.',
                    style: Theme.of(sheet).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: _searching && c != null
            ? TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: c.setSearch,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Tìm kiếm',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              )
            : const Text('Tin nhắn'),
        actions: [
          if (c != null && _searching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Đóng tìm kiếm',
              onPressed: () => _closeSearch(c),
            )
          else if (c != null) ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Tìm kiếm',
              onPressed: _openSearch,
            ),
            AppButton(
              label: _edit ? 'Xong' : 'Sửa',
              variant: AppButtonVariant.ghost,
              onPressed: _toggleEdit,
            ),
            AppButton(
              label: 'Thêm',
              variant: AppButtonVariant.ghost,
              onPressed: () => _newMenu(c),
            ),
            IconButton(
              icon: const Icon(Icons.badge_outlined),
              tooltip: 'ID của bạn',
              onPressed: () => _showMyId(c),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Cài đặt tin nhắn',
              onPressed: () => showMessagingSettings(context, c),
            ),
          ],
        ],
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
    final friends = [
      for (final f in all)
        if (!archived.contains(f.id)) f,
    ];
    final list = RefreshIndicator(
      onRefresh: () async {
        await c.chat?.loadFriendKeys();
        await c.refreshFriendList();
        await c.pollUnread();
      },
      // The conversation rows run edge to edge (like a messenger list); everything else keeps the 16 dp side margin.
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (c.supportUnread > 0)
            _side(
              Card(
                child: ListTile(
                  leading: const Icon(Icons.support_agent),
                  title: Text('Có ${c.supportUnread} phản hồi mới từ Admin'),
                  subtitle: const Text('Chạm để xem Hỗ trợ từ Admin'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/support'),
                ),
              ),
            ),
          if (q.isEmpty && (c.incomingRequests.isNotEmpty || c.outgoingRequests.isNotEmpty)) _side(_RequestsBlock(controller: c, onMessage: _toast)),
          if (c.searchError.isNotEmpty) _side(Text(c.searchError, style: TextStyle(color: context.badColor))),
          if (c.addNotice.isNotEmpty) _side(Text(c.addNotice, key: const Key('add-notice'), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))),
          if (q.isNotEmpty && (c.searching || c.newPeople.isNotEmpty)) ...[
            _side(Text('Người mới', style: theme.textTheme.titleSmall)),
            if (c.searching && c.newPeople.isEmpty) _side(const Text('Đang tìm…')),
            for (final r in c.newPeople)
              _side(
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text(r.name),
                    subtitle: Text('@${r.username}'),
                    trailing: switch (r.requestState) {
                      'outgoing' => const AppButton(label: 'Đã gửi lời mời', variant: AppButtonVariant.ghost, onPressed: null),
                      'incoming' => AppButton(label: c.addingId == r.id ? '…' : 'Chấp nhận', variant: AppButtonVariant.primary, onPressed: c.addingId == r.id ? null : () => c.addFriend(r)),
                      _ => AppButton(label: c.addingId == r.id ? '…' : 'Kết bạn', variant: AppButtonVariant.secondary, onPressed: c.addingId == r.id ? null : () => c.addFriend(r)),
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (c.loading)
            _side(const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
          else if (c.loadError.isNotEmpty)
            _side(
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(c.loadError, style: TextStyle(color: context.badColor)),
                      AppButton(label: 'Thử lại', variant: AppButtonVariant.ghost, onPressed: c.refreshFriendList),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            if (q.isNotEmpty && friends.isNotEmpty) _side(Text('Bạn bè', style: theme.textTheme.titleSmall)),
            if (c.conversations.isEmpty)
              _side(const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bạn bè nào. Bấm Thêm > Danh bạ mới để tìm và kết bạn.'))))
            else if (friends.isEmpty)
              if (q.isNotEmpty)
                (!c.searching && c.newPeople.isEmpty)
                    ? _side(Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Không tìm thấy ai khớp với "$q". Nếu là mã ID, hãy kiểm tra lại các chữ số.'))))
                    : const SizedBox.shrink()
              else
                _side(Card(child: Padding(padding: const EdgeInsets.all(16), child: const Text('Chưa có cuộc trò chuyện nào. Bấm Thêm > Tin nhắn mới để bắt đầu.'))))
            else
              for (final f in friends) _friendTile(context, c, f),
            if (_edit)
              _side(
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppButton(
                      label: 'Lưu trữ${_picked.isEmpty ? '' : ' (${_picked.length})'}',
                      variant: AppButtonVariant.ghost,
                      onPressed: _picked.isEmpty ? null : () => _archivePicked(c),
                    ),
                    TextButton(
                      onPressed: _picked.isEmpty ? null : () => _deletePicked(c),
                      child: Text('Xoá${_picked.isEmpty ? '' : ' (${_picked.length})'}', style: TextStyle(color: _picked.isEmpty ? null : context.badColor)),
                    ),
                  ],
                ),
              )
          ],
        ],
      ),
    );
    return Stack(children: [
      Positioned.fill(child: list),
      if (_showTop)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'friends-top',
            tooltip: 'Lên đầu danh sách',
            onPressed: () => _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
            child: const Icon(Icons.keyboard_arrow_up),
          ),
        ),
    ]);
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Widget _side(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: w);

  /// One conversation row in the style of a messenger list: round avatar, bold name, one-line preview, the time of the last
  /// message at the right (with the unread badge under it) and a thin line between rows (no card around each row).
  Widget _friendTile(BuildContext context, FriendsController c, Friend f) {
    final theme = Theme.of(context);
    final unread = c.chat?.unread[f.id] ?? 0;
    final missed = c.unseenMissed[f.id] ?? 0;
    final name = c.nameOf(f);
    final time = chatListTime(f.lastMessageAt, DateTime.now());
    void toggle() => setState(() => _picked.contains(f.id) ? _picked.remove(f.id) : _picked.add(f.id));
    return Column(
      children: [
        InkWell(
          onTap: _edit ? toggle : () => _openChat(f),
          onLongPress: _edit ? null : () => _rowMenu(c, f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                if (_edit) Padding(padding: const EdgeInsets.only(right: 4), child: Checkbox(value: _picked.contains(f.id), onChanged: (_) => toggle())),
                CircleAvatar(
                  radius: 26,
                  backgroundColor: avatarColor(name),
                  child: f.isGroup ? const Icon(Icons.groups, color: Colors.white, size: 28) : Text(initialOf(name), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        f.lastMessage ?? 'Chưa có tin nhắn',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: unread > 0 ? Colors.black : context.mutedColor, fontWeight: unread > 0 ? FontWeight.w600 : null),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(time, style: TextStyle(fontSize: 13, color: unread > 0 ? theme.colorScheme.primary : context.mutedColor)),
                    if (unread > 0 || missed > 0) const SizedBox(height: 4),
                    if (unread > 0) _Badge(text: unread > 99 ? '99+' : '$unread', color: context.badColor),
                    if (missed > 0) _Badge(text: '☎ $missed', color: context.badColor),
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, indent: 16 + 52 + 14.0 + (_edit ? 44 : 0), color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}

/// "Lời mời kết bạn": requests sent to me (Chấp nhận / Từ chối) and requests I sent (Huỷ lời mời). The red count is the
/// number of pending incoming ones.
class _RequestsBlock extends StatelessWidget {
  const _RequestsBlock({required this.controller, required this.onMessage});
  final FriendsController controller;
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return Container(
      key: const Key('requests-block'),
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Lời mời kết bạn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              if (c.pendingIncoming > 0) _Badge(text: c.pendingIncoming > 99 ? '99+' : '${c.pendingIncoming}', color: context.badColor),
            ],
          ),
          for (final r in c.incomingRequests) _row(context, r),
          for (final r in c.outgoingRequests) _row(context, r),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, FriendRequest r) {
    final c = controller;
    final busy = c.requestBusyId == r.id;
    Future<void> run(Future<String?> Function(FriendRequest) f) async {
      final err = await f(r);
      if (err != null) onMessage(err);
    }

    return Padding(
      key: Key('request-${r.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (r.username.isNotEmpty) Text('@${r.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: context.mutedColor)),
          if (!r.incoming) Text('Đã gửi lời mời, chờ chấp nhận', style: TextStyle(fontSize: 13, color: context.mutedColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: r.incoming
                ? [
                    AppButton(label: 'Chấp nhận', variant: AppButtonVariant.primary, loading: busy, onPressed: () => run(c.acceptRequest)),
                    AppButton(label: 'Từ chối', variant: AppButtonVariant.ghost, onPressed: busy ? null : () => run(c.declineRequest)),
                  ]
                : [AppButton(label: 'Huỷ lời mời', variant: AppButtonVariant.ghost, loading: busy, onPressed: () => run(c.cancelRequest))],
          ),
        ],
      ),
    );
  }
}

/// First letter of a name, upper-case (web `initial`).
String initialOf(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first.toUpperCase();
}

/// "Nhóm mới": name + friends to add. The group exists only on the members' devices (end-to-end encrypted, nothing on the server).
class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.controller});
  final FriendsController controller;
  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final Set<String> _members = {};
  final _name = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Friend> get _friends {
    final c = widget.controller;
    // Friends only: an Admin account is not part of chats, and the relay only carries messages between friends.
    return [...c.friends.where((f) => !f.isAdmin && (c.chat?.friendKeys.containsKey(f.id) ?? false))]..sort((a, b) => foldVi(c.nameOf(a)).compareTo(foldVi(c.nameOf(b))));
  }

  bool get _canCreate => !_busy && _name.text.trim().isNotEmpty && _members.length >= 2;

  Future<void> _create() async {
    final c = widget.controller;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final byId = {for (final f in c.friends) f.id: f};
      final g = await c.chat!.createGroup(_name.text, c.userName, [for (final id in _members) GroupMember(id, c.nameOf(byId[id]!))]);
      if (mounted) Navigator.pop(context, g.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final friends = _friends;
    return AlertDialog(
      title: const Text('Tạo nhóm'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _name, maxLength: 60, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Tên nhóm', counterText: '')),
            const SizedBox(height: 8),
            Text('Chọn ít nhất 2 bạn bè (${_members.length} đã chọn)', style: TextStyle(fontSize: 13, color: context.mutedColor)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (friends.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Chưa có bạn bè nào dùng được để thêm vào nhóm.')),
                  for (final f in friends)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _members.contains(f.id),
                      title: Text(c.nameOf(f)),
                      onChanged: _busy ? null : (_) => setState(() => _members.contains(f.id) ? _members.remove(f.id) : _members.add(f.id)),
                    ),
                ],
              ),
            ),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error, style: TextStyle(fontSize: 13, color: context.badColor))),
            const SizedBox(height: 6),
            Text('Nhóm chỉ nằm trên máy của các thành viên, tin nhắn mã hoá 2 đầu, máy chủ không lưu. Bạn chỉ gửi được cho thành viên là bạn bè của bạn.', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          ],
        ),
      ),
      actions: [
        AppButton(label: 'Đóng', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        AppButton(label: 'Tạo nhóm', variant: AppButtonVariant.primary, loading: _busy, onPressed: _canCreate ? _create : null),
      ],
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
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
