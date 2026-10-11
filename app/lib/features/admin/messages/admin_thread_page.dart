import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../friends/chat_models.dart' show imageOnlyMessage, maxAttachmentBytes, sniffImageType;
import '../../friends/image_scrub.dart';
import 'admin_messages_logic.dart';

/// One customer's support thread (web: components/AdminChatPane.vue). Oldest on top, newest at the bottom.
class AdminThreadPage extends StatefulWidget {
  const AdminThreadPage({super.key, required this.conversation, this.packageLabels = const {}});
  final Conversation conversation;
  final Map<String, String> packageLabels;
  @override
  State<AdminThreadPage> createState() => _AdminThreadPageState();
}

class _AdminThreadPageState extends State<AdminThreadPage> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _draft = TextEditingController();
  List<AdminMsg> _msgs = [];
  bool _loading = true;
  String? _error;
  String? _sendError;
  bool _sending = false;
  Uint8List? _pending; // scrubbed picture waiting to be sent
  Timer? _timer;
  bool _foreground = true;

  String get _uid => widget.conversation.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft.addListener(() => setState(() {}));
    _load();
    _markRead();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_foreground && mounted) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _load(quiet: true);
  }

  void _markRead() {
    context.read<ApiClient>().post('/me/unread/read', {'peerId': _uid}).catchError((_) => null);
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _load({bool quiet = false}) async {
    final api = context.read<ApiClient>();
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await api.get('/admin/messages/$_uid') as Map<String, dynamic>;
      final list = [for (final m in (res['messages'] as List? ?? const [])) AdminMsg.fromJson(m as Map<String, dynamic>)];
      if (!mounted) return;
      final grew = list.length != _msgs.length;
      setState(() {
        _msgs = list;
        _error = null;
        _loading = false;
      });
      if (!quiet || grew) _toEnd();
      if (quiet && grew && list.isNotEmpty && !list.last.fromAdmin) _markRead();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể tải cuộc trò chuyện';
        _loading = false;
      });
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
      if (x == null) return;
      final raw = await x.readAsBytes();
      if (raw.isEmpty) throw Exception('Tệp trống');
      if (sniffImageType(raw) == null) throw Exception(imageOnlyMessage);
      final clean = await scrubImage(raw);
      if (clean.bytes.length > maxAttachmentBytes) throw Exception('Tệp quá lớn (tối đa 5 MB)');
      if (!mounted) return;
      setState(() {
        _pending = clean.bytes;
        _sendError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (_sending || (text.isEmpty && _pending == null)) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final att = _pending == null ? null : buildAttachmentPayload(_pending!);
      final res = await context.read<ApiClient>().post('/admin/messages/$_uid', buildReplyBody(text, att)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _msgs = [..._msgs, AdminMsg.fromJson(res)];
        _draft.clear();
        _pending = null;
      });
      _toEnd();
    } on ApiError catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } catch (e) {
      if (mounted) setState(() => _sendError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _subtitle {
    final c = widget.conversation;
    return [
      if (c.username.isNotEmpty) '@${c.username}',
      if ((c.packageType ?? '').isNotEmpty) widget.packageLabels[c.packageType] ?? c.packageType!,
      if (expiryLabel(c.packageExpiresAt).isNotEmpty) 'hết hạn ${expiryLabel(c.packageExpiresAt)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final cs = Theme.of(context).colorScheme;
    final items = threadItems(_msgs);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.userName.isEmpty ? 'Khách hàng' : c.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (_subtitle.isNotEmpty) Text(_subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65))),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          if (_error != null) Container(width: double.infinity, color: cs.error.withValues(alpha: 0.15), padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: Text(_error!, style: TextStyle(color: cs.error))), TextButton(onPressed: _load, child: const Text('Thử lại'))])),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _load(quiet: true),
                    child: _msgs.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [Padding(padding: const EdgeInsets.all(48), child: Center(child: Text('Chưa có tin nhắn nào', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))))])
                        : ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final it = items[i];
                              if (it is String) return _DayDivider(it);
                              return _Bubble(msg: it as AdminMsg, userId: _uid);
                            },
                          ),
                  ),
          ),
          _composer(cs),
        ]),
      ),
    );
  }

  Widget _composer(ColorScheme cs) => Container(
        decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_sendError != null) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 6, bottom: 4), child: Text(_sendError!, style: TextStyle(color: cs.error, fontSize: 13)))),
          if (_pending != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Stack(children: [
                Padding(padding: const EdgeInsets.all(6), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_pending!, height: 72, fit: BoxFit.cover))),
                Positioned(right: 0, top: 0, child: InkWell(onTap: () => setState(() => _pending = null), child: CircleAvatar(radius: 11, backgroundColor: cs.error, child: const Icon(Icons.close, size: 14, color: Colors.white)))),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Gửi ảnh (JPG, PNG, WebP)',
              onPressed: _sending ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _draft,
                enabled: !_sending,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Nhập phản hồi...', isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Gửi',
              onPressed: _sending || (_draft.text.trim().isEmpty && _pending == null) ? null : _send,
              icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
            ),
          ]),
        ]),
      );
}

class _DayDivider extends StatelessWidget {
  const _DayDivider(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.userId});
  final AdminMsg msg;
  final String userId;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mine = msg.fromAdmin;
    final bg = mine ? cs.primary : cs.surfaceContainerHighest;
    final fg = mine ? Colors.white : cs.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (msg.content.isNotEmpty) SelectableText(msg.content, style: TextStyle(color: fg)),
              if (msg.attachment != null) ...[
                if (msg.content.isNotEmpty) const SizedBox(height: 6),
                AttachmentView(att: msg.attachment!, path: '/admin/messages/$userId/attachment/${msg.id}', color: fg),
              ],
            ]),
          ),
          Padding(padding: const EdgeInsets.only(top: 2, bottom: 2), child: Text(timeLabel(msg.createdAt), style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55)))),
        ]),
      ),
    );
  }
}

/// An attachment inside a bubble: images are fetched with the session token (ApiClient.blob) and shown from memory;
/// tap opens full size. Other types (the server only accepts pictures) show name and size.
class AttachmentView extends StatefulWidget {
  const AttachmentView({super.key, required this.att, required this.path, this.color});
  final MsgAttachment att;
  final String path;
  final Color? color;
  @override
  State<AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<AttachmentView> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.att.isImage) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _failed = false);
    try {
      final b = await context.read<ApiClient>().blob(widget.path);
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.att;
    if (a.isImage && _bytes != null) {
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(children: [
              Center(child: InteractiveViewer(child: Image.memory(_bytes!))),
              SafeArea(child: IconButton(color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
            ]),
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_bytes!, width: 220, fit: BoxFit.cover, semanticLabel: a.name, errorBuilder: (_, _, _) => const Icon(Icons.broken_image))),
      );
    }
    if (a.isImage && !_failed) return const SizedBox(width: 220, height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    return InkWell(
      onTap: a.isImage ? _fetch : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_failed ? Icons.error_outline : Icons.attach_file, size: 18, color: _failed ? Brand.danger : widget.color),
        const SizedBox(width: 6),
        Flexible(child: Text(_failed ? 'Không tải được ảnh, chạm để thử lại' : '${a.name} (${formatSize(a.size)})', style: TextStyle(color: widget.color))),
      ]),
    );
  }
}
