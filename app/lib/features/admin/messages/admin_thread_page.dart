import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'admin_messages_logic.dart';
import 'thread_widgets.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/svg_icon.dart';

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

  Future<void> _pick() async {
    try {
      final bytes = await pickScrubbedImage(ImageSource.gallery);
      if (bytes == null || !mounted) return;
      setState(() {
        _pending = bytes;
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

  /// Asks, then deletes one message of this thread on the server (it disappears for the customer too).
  Future<void> _deleteOne(AdminMsg m) async {
    if (!await _confirm('Xoá tin nhắn', 'Xoá tin nhắn này? Tin nhắn cũng sẽ biến mất bên khách hàng và không thể khôi phục.') || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/admin/messages/$_uid/${m.id}');
      if (mounted) setState(() => _msgs = [for (final x in _msgs) if (x.id != m.id) x]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } catch (_) {
      if (mounted) setState(() => _sendError = 'Không xoá được tin nhắn');
    }
  }

  /// Clears the whole thread with this customer.
  Future<void> _clearAll() async {
    if (!await _confirm('Xoá cuộc trò chuyện', 'Xoá toàn bộ phản hồi với khách hàng này? Cả tin của khách và của Admin đều bị xoá, bên khách hàng cũng không còn thấy, không thể khôi phục.') || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/admin/messages/$_uid');
      if (mounted) setState(() => _msgs = []);
    } on ApiError catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } catch (_) {
      if (mounted) setState(() => _sendError = 'Không xoá được cuộc trò chuyện');
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false)),
            AppButton(label: 'Xoá', svg: AppSvg.delete, variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ) ==
      true;

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
        actions: [
          if (_msgs.isNotEmpty) IconButton(key: const Key('clear-thread'), tooltip: 'Xoá cuộc trò chuyện', icon: SvgIcon(AppSvg.delete, color: context.badColor), onPressed: _clearAll),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_error != null) Container(width: double.infinity, color: cs.error.withValues(alpha: 0.15), padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: Text(_error!, style: TextStyle(color: cs.error))), AppButton(label: 'Thử lại', variant: AppButtonVariant.ghost, onPressed: _load)])),
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
                              if (it is String) return DayDivider(it);
                              final m = it as AdminMsg;
                              return ThreadBubble(msg: m, mine: m.fromAdmin, attachmentPath: '/admin/messages/$_uid/attachment/${m.id}', onDelete: () => _deleteOne(m));
                            },
                          ),
                  ),
          ),
          ThreadComposer(
            draft: _draft,
            pending: _pending,
            sending: _sending,
            error: _sendError,
            hint: 'Nhập phản hồi...',
            onPick: _pick,
            onRemovePending: () => setState(() => _pending = null),
            onSend: _send,
          ),
        ]),
      ),
    );
  }
}
