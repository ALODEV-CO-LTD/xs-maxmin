import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'call_service.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'friends_controller.dart';
import 'image_scrub.dart';

/// Android 14+ can report screenshots of the app only through native code. If the host app forwards them on this
/// channel (method `screenshot`), the friend is warned just like the web does on a screenshot shortcut.
const screenshotChannel = MethodChannel('mamba/screenshot');

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

  FriendsController get _c => widget.controller;
  ChatService get _chat => _c.chat!;
  Friend get _f => widget.friend;
  List<Map<String, dynamic>> _calls = [];

  @override
  void initState() {
    super.initState();
    _chat.openPeer = _f.id;
    _chat.markRead(_f.id);
    _chat.addListener(_onChat);
    _c.call?.addListener(_onCall);
    _lastEnded = _c.call?.endedTick ?? 0;
    screenshotChannel.setMethodCallHandler((call) async {
      if (call.method == 'screenshot' && mounted && !_f.isAdmin) _chat.notifyScreenshot(_f.id);
    });
    _reload(first: true);
    _loadCalls();
    _chat.retentionOf(_f.id).then((r) {
      if (mounted) setState(() => _rule = r);
    });
  }

  @override
  void dispose() {
    _chat.openPeer = null;
    _chat.removeListener(_onChat);
    _c.call?.removeListener(_onCall);
    screenshotChannel.setMethodCallHandler(null);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
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
      await _chat.send(_f.id, text, image: _pending);
      _text.clear();
      _pending = null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = _c.call;
    final info = _chat.peerInfo[_f.id];
    final hasKey = _chat.friendKeys.containsKey(_f.id);
    final canCall = call != null && call.canCall && !_f.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(_f.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (canCall) IconButton(icon: const Icon(Icons.call), tooltip: 'Gọi thoại', onPressed: call.busy ? null : () => call.startCall(_f.id, _f.name)),
          if (info != null) IconButton(icon: Icon(Icons.verified_user_outlined, color: _showSecurity ? theme.colorScheme.primary : null), tooltip: 'Mã bảo mật', onPressed: () => setState(() => _showSecurity = !_showSecurity)),
          IconButton(icon: Icon(Icons.timer_outlined, color: _rule != null ? theme.colorScheme.primary : null), tooltip: 'Cài đặt tự xoá', onPressed: _openRetention),
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
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: Text(_error, style: TextStyle(color: context.badColor))),
            Expanded(child: _list(context)),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(icon: const Icon(Icons.image_outlined), tooltip: 'Gửi ảnh', onPressed: _sending || !hasKey ? null : _attachMenu),
                Expanded(
                  child: TextField(
                    controller: _text,
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
          _Msg m => _bubble(context, m.m),
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
    final bg = mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = mine ? Colors.white : theme.colorScheme.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (m.att != null) _attachment(context, m.att!),
                if (m.att != null && m.text.isNotEmpty) const SizedBox(height: 6),
                if (m.text.isNotEmpty) SelectableText(m.text, style: TextStyle(color: fg)),
                const SizedBox(height: 2),
                Text(DateFormat('HH:mm dd/MM').format(DateTime.fromMillisecondsSinceEpoch(m.createdAt)), style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7))),
              ]),
            ),
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
