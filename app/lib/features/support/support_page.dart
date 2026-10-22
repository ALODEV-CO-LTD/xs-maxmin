import 'dart:async';
import '../../core/widgets/svg_icon.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../admin/messages/admin_messages_logic.dart';
import '../admin/messages/thread_widgets.dart';
import '../friends/friends_controller.dart';
import '../friends/messaging_host.dart';
import '../../core/widgets/app_button.dart';

/// "Hỗ trợ từ Admin" (web: components/SupportChat.vue): the customer's thread with Admin. Oldest on top, newest at the
/// bottom, the list sticks to the end. Opening it marks the replies as read; while it is open anything new counts as read.
class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _draft = TextEditingController();
  List<AdminMsg> _msgs = [];
  bool _loading = true;
  String? _error;
  String? _sendError;
  bool _sending = false;
  Uint8List? _pending;
  Timer? _timer;
  bool _foreground = true;
  FriendsController? _hub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_foreground && mounted) _load(quiet: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hub = MessagingScope.maybeOf(context);
    if (!identical(hub, _hub)) {
      _hub?.supportVisible = false;
      _hub = hub;
      hub?.supportVisible = true;
      hub?.markSupportRead();
    }
    if (hub == null) context.read<ApiClient>().post('/me/unread/read', {'peerId': 'support'}).catchError((_) => null);
  }

  @override
  void dispose() {
    _hub?.supportVisible = false;
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

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _load({bool quiet = false}) async {
    final api = context.read<ApiClient>();
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await api.get('/me/messages') as Map<String, dynamic>;
      final list = [for (final m in (res['messages'] as List? ?? const [])) AdminMsg.fromJson(m as Map<String, dynamic>)];
      if (!mounted) return;
      final grew = list.length != _msgs.length;
      setState(() {
        _msgs = list;
        _error = null;
        _loading = false;
      });
      if (!quiet || grew) _toEnd();
      if (grew && list.isNotEmpty && list.last.fromAdmin) _hub?.markSupportRead();
    } on ApiError catch (e) {
      if (!mounted) return;
      // A failed background refresh keeps what is on screen; only the first load shows the error.
      if (!quiet || _msgs.isEmpty) setState(() => _error = e.message);
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      if (!quiet || _msgs.isEmpty) setState(() => _error = 'Không tải được tin nhắn');
      setState(() => _loading = false);
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
      if (mounted) setState(() => _sendError = e.toString().replaceFirst('Exception: ', ''));
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
      final res = await context.read<ApiClient>().post('/me/messages', buildReplyBody(text, att)) as Map<String, dynamic>;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = threadItems(_msgs);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/account')),
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hỗ trợ từ Admin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('Gửi câu hỏi hoặc báo lỗi, Admin trả lời tại đây.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: cs.error.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(8),
              child: Row(children: [Expanded(child: Text(_error!, style: TextStyle(color: cs.error))), AppButton(label: 'Thử lại', variant: AppButtonVariant.ghost, onPressed: _load)]),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _load(quiet: true),
                    child: _msgs.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                            Padding(padding: const EdgeInsets.all(48), child: Center(child: Text('Chưa có tin nhắn nào. Hãy gửi tin nhắn đầu tiên cho Admin.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))))),
                          ])
                        : ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final it = items[i];
                              if (it is String) return DayDivider(it);
                              final m = it as AdminMsg;
                              return ThreadBubble(msg: m, mine: !m.fromAdmin, senderLabel: m.fromAdmin ? 'Admin' : null, attachmentPath: '/me/messages/${m.id}/attachment');
                            },
                          ),
                  ),
          ),
          ThreadComposer(
            draft: _draft,
            pending: _pending,
            sending: _sending,
            error: _sendError,
            hint: 'Nhập tin nhắn...',
            maxLength: 2000,
            onPick: _pick,
            onRemovePending: () => setState(() => _pending = null),
            onSend: _send,
          ),
        ]),
      ),
    );
  }
}

/// Entry to the support thread with the unread count: a card for the Tài khoản screen.
class SupportEntryCard extends StatelessWidget {
  const SupportEntryCard({super.key});
  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    Widget tile(int n) => Card(
          child: ListTile(
            leading: Badge(isLabelVisible: n > 0, label: Text(n > 9 ? '9+' : '$n'), child: const SvgIcon(AppSvg.support)),
            title: const Text('Hỗ trợ từ Admin', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(n > 0 ? 'Có $n phản hồi mới từ Admin' : 'Gửi câu hỏi hoặc báo lỗi cho Admin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/support'),
          ),
        );
    if (hub == null) return tile(0);
    return ListenableBuilder(listenable: hub, builder: (_, _) => tile(hub.supportUnread));
  }
}
