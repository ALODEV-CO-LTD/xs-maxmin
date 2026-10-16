import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../chat_calc/chat_calc_entry.dart';
import 'call_service.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'friends_controller.dart';
import 'friends_screen.dart' show initialOf;
import 'image_scrub.dart';
import 'realtime_socket.dart';

sealed class _Item {
  _Item(this.at);
  final int at;
}

class _Msg extends _Item {
  _Msg(this.m) : super(m.createdAt);
  final ChatMessage m;
}

class _Call extends _Item {
  _Call(this.c) : super(DateTime.tryParse('${c['createdAt']}')?.millisecondsSinceEpoch ?? 0);
  final Map<String, dynamic> c;
}

/// One E2EE conversation (the thread half of FriendsView.vue).
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, required this.friend});
  final FriendsController controller;
  final Friend friend;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<_Item> _items = [];
  bool _loading = true;
  String _error = '';
  bool _sending = false;
  bool _showSecurity = false;
  RetentionRule? _rule;
  OutgoingImage? _pending;
  int _lastTick = -1;
  int _lastEnded = 0;
  ChatMessage? _replyTo; // the message being answered (shown above the input)
  List<String> _pins = [];
  bool _selecting = false; // "Nhập số liệu": tick messages, then "Tính toán"
  final Set<String> _picked = {};
  final Map<String, GlobalKey> _keys = {};
  final _input = FocusNode();

  FriendsController get _c => widget.controller;
  ChatService get _chat => _c.chat!;
  Friend get _f => widget.friend;
  List<Map<String, dynamic>> _calls = [];

  @override
  void initState() {
    super.initState();
    _chat.openPeer = _f.id;
    _c.markChatSeen(_f.id);
    _chat.addListener(_onChat);
    _scroll.addListener(_onScroll);
    _c.socket.addListener(_onSocket);
    _c.call?.addListener(_onCall);
    _lastEnded = _c.call?.endedTick ?? 0;
    _reload(first: true);
    _loadCalls();
    _chat.pinsOf(_f.id).then((p) {
      if (mounted) setState(() => _pins = p);
    });
    _chat.retentionOf(_f.id).then((r) {
      if (mounted) setState(() => _rule = r);
    });
  }

  @override
  void dispose() {
    _chat.openPeer = null;
    _chat.removeListener(_onChat);
    _c.call?.removeListener(_onCall);
    _c.socket.removeListener(_onSocket);
    _scroll.removeListener(_onScroll);
    _text.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _showDown = false;

  void _onScroll() {
    final far = _scroll.hasClients && _scroll.offset > 400; // the list is reversed: 0 is the newest message
    if (far != _showDown && mounted) setState(() => _showDown = far);
  }

  void _onSocket() {
    if (mounted) setState(() {});
  }

  void _toBottom() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _onChat() {
    if (_chat.tick != _lastTick) _reload();
    if ((_chat.unread[_f.id] ?? 0) > 0) _chat.markRead(_f.id);
  }

  void _onCall() {
    final c = _c.call!;
    if (c.endedTick != _lastEnded) {
      _lastEnded = c.endedTick;
      _loadCalls();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadCalls() async {
    _calls = await _c.callsWith(_f.id);
    _rebuildItems(await _chat.messages(_f.id));
  }

  Future<void> _reload({bool first = false}) async {
    _lastTick = _chat.tick;
    try {
      final list = await _chat.messages(_f.id);
      _rebuildItems(list);
      _error = '';
    } catch (_) {
      _error = 'Không đọc được tin nhắn trên thiết bị';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _rebuildItems(List<ChatMessage> msgs) {
    final items = <_Item>[for (final m in msgs) _Msg(m), for (final c in _calls) _Call(c)]..sort((a, b) => a.at.compareTo(b.at));
    if (mounted) setState(() => _items = items);
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = '');
    try {
      final x = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final clean = await scrubImage(bytes);
      if (mounted) setState(() => _pending = clean);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _attachMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Chọn ảnh từ thư viện'), subtitle: const Text('JPG, PNG, WebP'), onTap: () { Navigator.pop(ctx); _pick(ImageSource.gallery); }),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Chụp ảnh'), onTap: () { Navigator.pop(ctx); _pick(ImageSource.camera); }),
        ]),
      ),
    );
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if ((text.isEmpty && _pending == null) || _sending) return;
    setState(() { _sending = true; _error = ''; });
    try {
      await _chat.send(_f.id, composeReply(_replyTo, text), image: _pending);
      _text.clear();
      _pending = null;
      _replyTo = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _sending = false);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _openRetention() async {
    final rule = await showModalBottomSheet<({RetentionRule? rule, bool changed})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RetentionSheet(friendName: _f.name, current: _rule),
    );
    if (rule == null || !rule.changed) return;
    await _chat.setRetention(_f.id, rule.rule);
    if (!mounted) return;
    setState(() => _rule = rule.rule);
    _rebuildItems(await _chat.messages(_f.id));
  }

  // ---- long-press menu, pins, forward, delete, pick (FriendsView.vue) -----------------------------------------------

  List<ChatMessage> get _msgs => [for (final i in _items) if (i is _Msg) i.m];

  ChatMessage? get _pinned {
    final byId = {for (final m in _msgs) m.id: m};
    for (var i = _pins.length - 1; i >= 0; i--) {
      final m = byId[_pins[i]];
      if (m != null) return m;
    }
    return null;
  }

  Future<void> _menu(ChatMessage m) async {
    if (_selecting || m.sys != null) return;
    final pinned = _pins.contains(m.id);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: const Text('Trả lời'), onTap: () => Navigator.pop(ctx, 'reply')),
          if (m.text.isNotEmpty) ListTile(title: const Text('Sao chép'), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(title: Text(pinned ? 'Bỏ ghim' : 'Ghim'), onTap: () => Navigator.pop(ctx, 'pin')),
          ListTile(title: const Text('Chuyển tiếp'), onTap: () => Navigator.pop(ctx, 'forward')),
          ListTile(title: Text('Xoá', style: TextStyle(color: context.badColor)), onTap: () => Navigator.pop(ctx, 'delete')),
          if (m.text.isNotEmpty) ListTile(title: const Text('Chọn'), onTap: () => Navigator.pop(ctx, 'select')),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'reply':
        setState(() => _replyTo = m);
        _input.requestFocus();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: quoteOf(m.text).body));
      case 'pin':
        await _togglePin(m.id);
      case 'forward':
        await _forward(m);
      case 'delete':
        await _delete(m);
      case 'select':
        setState(() { _selecting = true; _picked.add(m.id); });
    }
  }

  Future<void> _togglePin(String id) async {
    final pins = await _chat.togglePin(_f.id, id);
    if (mounted) setState(() => _pins = pins);
  }

  Future<void> _delete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá tin nhắn'),
        content: const Text('Xoá tin nhắn này khỏi máy này? Người kia vẫn giữ bản của họ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Xoá', style: TextStyle(color: ctx.badColor))),
        ],
      ),
    );
    if (ok != true) return;
    await _chat.deleteMessage(_f.id, m.id);
    final pins = await _chat.pinsOf(_f.id);
    if (mounted) setState(() { _pins = pins; _picked.remove(m.id); if (_replyTo?.id == m.id) _replyTo = null; });
  }

  Future<void> _forward(ChatMessage m) async {
    final target = await showDialog<Friend>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Chuyển tiếp tới'),
        children: [
          for (final f in _c.friends.where((x) => !x.isAdmin)) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, f), child: Text(_c.nameOf(f))),
          if (_c.friends.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bạn bè.')),
        ],
      ),
    );
    if (target == null || !mounted) return;
    try {
      OutgoingImage? image;
      final a = m.att;
      if (a != null && a.isImage && a.path != null) {
        final bytes = await _chat.store.readFile(a.path!);
        if (bytes != null) image = OutgoingImage(bytes, a.type);
      }
      await _chat.send(target.id, quoteOf(m.text).body, image: image);
      if (!mounted) return;
      if (target.id != _f.id) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ChatPage(controller: _c, friend: target)));
      } else {
        setState(() => _error = '');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Scrolls to a message (the pin bar). The list is lazy, so first jump near it, then bring it fully into view.
  Future<void> _jumpTo(String id) async {
    final rev = _items.reversed.toList();
    final idx = rev.indexWhere((i) => i is _Msg && i.m.id == id);
    if (idx < 0 || !_scroll.hasClients) return;
    for (var tries = 0; tries < 8; tries++) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.3);
        return;
      }
      final pos = _scroll.position;
      final avg = pos.maxScrollExtent / (rev.length > 1 ? rev.length : 1);
      _scroll.jumpTo((avg * idx).clamp(0.0, pos.maxScrollExtent));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
  }

  void _cancelPick() => setState(() { _selecting = false; _picked.clear(); });

  /// "Nhập số liệu" starts picking; with something picked the button is "Tính toán" and opens Đối chiếu.
  void _onAction() {
    if (!_selecting) {
      setState(() => _selecting = true);
      return;
    }
    if (_picked.isEmpty) return;
    final chosen = [for (final m in _msgs) if (_picked.contains(m.id)) m]; // original display order
    openChatDecode(context, friendId: _f.id, friendName: _c.nameOf(_f), messages: chosen);
  }

  void _pickAll() => setState(() => _picked
    ..clear()
    ..addAll([for (final m in _msgs) if (m.sys == null && m.text.isNotEmpty) m.id]));

  /// ⚙: own display name (this device only), security code, auto-delete, remove friend.
  Future<void> _openSettings() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SettingsSheet(
        friend: _f,
        alias: _chat.aliases[_f.id] ?? '',
        hasPeerInfo: _chat.peerInfo[_f.id] != null,
        hasRule: _rule != null,
        onSaveAlias: (a) => _chat.setAlias(_f.id, a, _f.name),
      ),
    );
    if (!mounted || r == null) return;
    switch (r) {
      case 'security':
        setState(() => _showSecurity = !_showSecurity);
      case 'retention':
        await _openRetention();
      case 'retention-off':
        await _chat.setRetention(_f.id, null);
        if (mounted) setState(() => _rule = null);
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xoá bạn bè'),
            content: Text('Xoá bạn bè "${_f.name}"? Cuộc trò chuyện sẽ không còn hiển thị.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Xoá', style: TextStyle(color: ctx.badColor))),
            ],
          ),
        );
        if (ok != true) return;
        final err = await _c.removeFriend(_f);
        if (!mounted) return;
        if (err != null) {
          setState(() => _error = err);
        } else {
          Navigator.of(context).pop();
        }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = _c.call;
    final info = _chat.peerInfo[_f.id];
    final hasKey = _chat.friendKeys.containsKey(_f.id);
    final canCall = call != null && call.canCall && !_f.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          CircleAvatar(radius: 14, backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2), child: Text(initialOf(_c.nameOf(_f)), style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_c.nameOf(_f), overflow: TextOverflow.ellipsis),
              _ConnChip(state: _c.socket.state),
            ]),
          ),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Cài đặt cuộc trò chuyện', onPressed: _openSettings),
          if (canCall) IconButton(icon: const Icon(Icons.call), tooltip: 'Gọi thoại', onPressed: call.busy ? null : () => call.startCall(_f.id, _f.name)),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _chat,
          builder: (context, _) => Column(children: [
            if (info?.changed ?? false)
              _Banner(
                color: Brand.warning,
                child: Row(children: [
                  Expanded(child: Text('Khoá bảo mật của ${_f.name} đã thay đổi (họ đổi máy hoặc xoá dữ liệu ứng dụng). Hãy xác minh mã bảo mật mới với họ qua kênh khác rồi bấm Đã hiểu.')),
                  TextButton(onPressed: () => _chat.acceptKeyChange(_f.id), child: const Text('Đã hiểu')),
                ]),
              ),
            if (!hasKey) _Banner(color: Brand.warning, child: Text('${_f.name} chưa bật mã hoá 2 đầu (chưa mở phiên bản mới) nên chưa nhắn được.')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                const Text('🔒 '),
                Expanded(child: Text('Mã hoá 2 đầu, không lưu trên máy chủ. Chỉ gửi được khi bạn bè đang online.', style: theme.textTheme.bodySmall?.copyWith(color: context.mutedColor))),
              ]),
            ),
            if (_showSecurity && info != null)
              _Banner(
                color: theme.colorScheme.primary,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _CodeRow(label: 'Của ${_f.name}', code: info.fingerprint),
                  _CodeRow(label: 'Của bạn', code: _chat.myFingerprint),
                  const SizedBox(height: 4),
                  Text('Đọc hai mã này cho nhau qua kênh khác (gọi điện, gặp mặt). Nếu khớp thì không ai chen giữa.', style: theme.textTheme.bodySmall),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: Text(_rule?.describe ?? 'Tin nhắn không tự xoá', style: theme.textTheme.bodySmall?.copyWith(color: _rule != null ? theme.colorScheme.primary : context.mutedColor))),
            ),
            if (_pinned case final pm?)
              Material(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                child: InkWell(
                  onTap: () => _jumpTo(pm.id),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(children: [
                      Expanded(child: Text('📌 ${quoteText(pm)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Bỏ ghim', onPressed: () => _togglePin(pm.id)),
                    ]),
                  ),
                ),
              ),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Text(_error, style: TextStyle(color: context.badColor))),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: _list(context)),
                if (_showDown)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(heroTag: null, tooltip: 'Xuống tin mới nhất', onPressed: _toBottom, child: const Icon(Icons.keyboard_arrow_down)),
                  ),
              ]),
            ),
            if (_pending != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_pending!.bytes, width: 64, height: 64, fit: BoxFit.cover)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${(_pending!.bytes.length / 1024).round()} KB · đã xoá thông tin vị trí/thiết bị', style: theme.textTheme.bodySmall)),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Bỏ ảnh', onPressed: () => setState(() => _pending = null)),
                ]),
              ),
            if (_selecting)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(child: Text('Đã chọn ${_picked.length}', style: TextStyle(color: context.mutedColor))),
                  TextButton(onPressed: _pickAll, child: const Text('Chọn tất cả')),
                  TextButton(onPressed: () => setState(_picked.clear), child: const Text('Bỏ chọn')),
                  TextButton(onPressed: _cancelPick, child: const Text('Hủy')),
                ]),
              ),
            if (_replyTo case final rt?)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(children: [
                  Expanded(child: Text('↪ Trả lời: ${quoteText(rt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.mutedColor))),
                  IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'Bỏ trả lời', onPressed: () => setState(() => _replyTo = null)),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _picked.isNotEmpty && _selecting
                    ? FilledButton(onPressed: _onAction, child: const Text('Tính toán'))
                    : OutlinedButton(onPressed: _onAction, child: const Text('Nhập số liệu')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(icon: const Icon(Icons.image_outlined), tooltip: 'Gửi ảnh', onPressed: _sending || !hasKey ? null : _attachMenu),
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Nhập tin nhắn...'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _sending || !hasKey || (_text.text.trim().isEmpty && _pending == null) ? null : _send, child: const Text('Gửi')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return Center(child: Text('Chưa có tin nhắn nào.', style: TextStyle(color: context.mutedColor)));
    final rev = _items.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: rev.length,
      itemBuilder: (context, i) {
        final it = rev[i];
        return switch (it) {
          _Msg m => KeyedSubtree(key: _keys.putIfAbsent(m.m.id, GlobalKey.new), child: _bubble(context, m.m)),
          _Call c => _callLine(context, c.c),
        };
      },
    );
  }

  Widget _callLine(BuildContext context, Map<String, dynamic> c) {
    final missed = isMissedCall(c) || c['status'] == 'failed';
    final call = _c.call;
    final canRedial = call != null && call.canCall && !_f.isAdmin && (isMissedCall(c) || c['status'] == 'rejected' || c['status'] == 'failed');
    final color = missed ? context.badColor : context.mutedColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.call, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(callLine(c), style: TextStyle(color: color, fontSize: 13))),
        if (canRedial) TextButton(onPressed: call.busy ? null : () => call.startCall(_f.id, _f.name), child: const Text('Gọi lại')),
      ]),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m) {
    final theme = Theme.of(context);
    if (m.sys != null) {
      final failed = m.mine && m.status == MsgStatus.failed;
      final text = m.sys == SysKind.screenshot
          ? '📷 ${_f.name} vừa chụp màn hình cuộc trò chuyện này'
          : failed
              ? '📷 Bạn vừa chụp màn hình, nhưng ${_f.name} đang offline nên chưa được báo'
              : '📷 Bạn vừa chụp màn hình, ${_f.name} đã được báo';
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: failed ? context.badColor : context.mutedColor))));
    }
    final mine = m.mine;
    final q = quoteOf(m.text);
    final bg = mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = mine ? Colors.white : theme.colorScheme.onSurface;
    final pinned = _pins.contains(m.id);
    final tick = _selecting && m.text.isNotEmpty;
    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            GestureDetector(
              onLongPress: _selecting ? null : () => _menu(m),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (pinned) Text('📌', style: TextStyle(fontSize: 11, color: fg)),
                if (q.quote.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: fg.withValues(alpha: 0.6), width: 3))),
                    child: Text(q.quote, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8))),
                  ),
                if (m.att != null) _attachment(context, m.att!),
                if (m.att != null && q.body.isNotEmpty) const SizedBox(height: 6),
                if (q.body.isNotEmpty) Text(q.body, style: TextStyle(color: fg)),
                const SizedBox(height: 2),
                Text(DateFormat('HH:mm dd/MM').format(DateTime.fromMillisecondsSinceEpoch(m.createdAt)), style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7))),
              ]),
            )),
            if (mine && m.status == MsgStatus.failed)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(reasonText(m.reason), style: TextStyle(fontSize: 12, color: context.badColor))),
                TextButton(onPressed: () => _chat.retry(m.id), child: const Text('Gửi lại')),
              ])
            else if (mine && m.status != MsgStatus.delivered)
              Text(m.status == MsgStatus.sending ? 'Đang gửi...' : 'Đã gửi, chờ xác nhận...', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          ]),
        ),
      ),
    );
    if (!tick) return bubble;
    final on = _picked.contains(m.id);
    void toggle() => setState(() => on ? _picked.remove(m.id) : _picked.add(m.id));
    return InkWell(
      onTap: toggle,
      child: Row(children: [
        Checkbox(value: on, onChanged: (_) => toggle()),
        Expanded(child: IgnorePointer(child: bubble)),
      ]),
    );
  }

  Widget _attachment(BuildContext context, ChatAttachment a) {
    final path = a.path;
    if (!a.isImage || path == null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.insert_drive_file_outlined, size: 18), const SizedBox(width: 6), Flexible(child: Text(a.name))]);
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ImageViewer(path: path, title: a.name))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: path.startsWith('mem://')
            ? const SizedBox(width: 120, height: 80)
            : Image.file(File(path), width: 220, fit: BoxFit.cover, cacheWidth: 660, errorBuilder: (_, _, _) => const SizedBox(width: 120, height: 60, child: Center(child: Text('Không mở được ảnh')))),
      ),
    );
  }
}

/// Đang kết nối / Đã kết nối / Mất kết nối.
class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.state});
  final ConnState state;
  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (state) {
      ConnState.connected => ('Đã kết nối', context.okColor),
      ConnState.connecting => ('Đang kết nối', Brand.warning),
      ConnState.disconnected => ('Mất kết nối', context.badColor),
    };
    return Semantics(
      label: 'Trạng thái kết nối: $text',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: child),
      );
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.label, required this.code});
  final String label;
  final String code;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text('$label: ', overflow: TextOverflow.ellipsis)),
          SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 1)),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.copy, size: 16), tooltip: 'Sao chép', onPressed: () => Clipboard.setData(ClipboardData(text: code))),
        ]),
      );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.path, required this.title});
  final String path;
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(title), backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(maxScale: 5, child: Image.file(File(path), errorBuilder: (_, _, _) => const Text('Không mở được ảnh', style: TextStyle(color: Colors.white))))),
      );
}

class _RetentionSheet extends StatefulWidget {
  const _RetentionSheet({required this.friendName, required this.current});
  final String friendName;
  final RetentionRule? current;
  @override
  State<_RetentionSheet> createState() => _RetentionSheetState();
}

class _RetentionSheetState extends State<_RetentionSheet> {
  late int _ttl = widget.current?.ttlSeconds ?? 86400;
  late String _scope = widget.current?.scope ?? 'all';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tự xoá tin nhắn', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('Tin nhắn/ảnh cũ hơn thời gian chọn sẽ bị xoá khỏi thiết bị này. Máy chủ không lưu tin nhắn, và thiết bị của ${widget.friendName} có cài đặt riêng.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: retentionTtls.containsKey(_ttl) ? _ttl : 86400,
          decoration: const InputDecoration(labelText: 'Thời gian tự xoá'),
          items: [for (final e in retentionTtls.entries) DropdownMenuItem(value: e.key, child: Text('Sau ${e.value}'))],
          onChanged: (v) => setState(() => _ttl = v ?? _ttl),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _scope,
          decoration: const InputDecoration(labelText: 'Phạm vi tự xoá'),
          items: const [DropdownMenuItem(value: 'all', child: Text('Tin nhắn và tệp đính kèm')), DropdownMenuItem(value: 'images', child: Text('Chỉ ảnh'))],
          onChanged: (v) => setState(() => _scope = v ?? _scope),
        ),
        const SizedBox(height: 16),
        Row(children: [
          if (widget.current != null) Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, (rule: null as RetentionRule?, changed: true)), child: const Text('Tắt tự xoá'))),
          if (widget.current != null) const SizedBox(width: 12),
          Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: context.badColor), onPressed: () => Navigator.pop(context, (rule: RetentionRule(_ttl, _scope) as RetentionRule?, changed: true)), child: const Text('Áp dụng'))),
        ]),
      ]),
    );
  }
}

/// ⚙ sheet (web: settings overlay): own display name (saved only on this device) and the conversation tools.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.friend, required this.alias, required this.hasPeerInfo, required this.hasRule, required this.onSaveAlias});
  final Friend friend;
  final String alias;
  final bool hasPeerInfo;
  final bool hasRule;
  final Future<void> Function(String alias) onSaveAlias;
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _alias = TextEditingController(text: widget.alias);
  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.friend;
    final shown = _alias.text.trim().isEmpty ? f.name : _alias.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: CircleAvatar(radius: 32, child: Text(initialOf(shown), style: const TextStyle(fontSize: 26)))),
          const SizedBox(height: 6),
          Center(child: Text(shown, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          TextField(controller: _alias, maxLength: 40, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Tên hiển thị', hintText: f.name)),
          Text('Chỉ đổi cách hiển thị trên máy này, người kia không thấy.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.mutedColor)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (widget.hasPeerInfo) TextButton(onPressed: () => Navigator.pop(context, 'security'), child: const Text('Mã bảo mật')),
            if (!f.isAdmin) TextButton(onPressed: () => Navigator.pop(context, 'retention'), child: const Text('Cài đặt tự xoá')),
            if (widget.hasRule) TextButton(onPressed: () => Navigator.pop(context, 'retention-off'), child: const Text('Tắt tự xoá')),
            TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: Text('Xoá khỏi bạn bè', style: TextStyle(color: context.badColor))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
            FilledButton(
              onPressed: () async {
                await widget.onSaveAlias(_alias.text);
                if (context.mounted) Navigator.pop(context, 'saved');
              },
              child: const Text('Lưu'),
            ),
          ]),
        ]),
      ),
    );
  }
}
