import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/admin_session.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'admin_messages_logic.dart';
import 'admin_thread_page.dart';
import '../../../core/widgets/app_button.dart';

/// Admin - Phản hồi: the support inbox (web: views/admin/MessagesView.vue). Body only; the admin shell draws the
/// AppBar and drawer. Tapping a customer pushes [AdminThreadPage].
class AdminMessagesScreen extends StatefulWidget {
  const AdminMessagesScreen({super.key});
  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen> with WidgetsBindingObserver {
  List<Conversation> _all = [];
  Map<String, int> _unread = {};
  final Map<String, String> _packages = {'none': 'Chưa đăng ký', 'trial': 'Dùng thử 30 ngày'};
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _onlyAwaiting = false;
  Timer? _timer;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadPackages();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_inForeground && mounted) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (_inForeground) _load(quiet: true);
  }

  Future<void> _loadPackages() async {
    try {
      final res = await context.read<ApiClient>().get('/me/packages?all=1');
      final list = (res is Map ? res['packages'] : null) as List? ?? const [];
      if (!mounted) return;
      setState(() {
        for (final p in list) {
          if (p is Map && p['type'] != null) _packages['${p['type']}'] = '${p['label']}';
        }
      });
    } catch (_) {/* labels are cosmetic: unknown codes show as-is */}
  }

  Future<void> _load({bool quiet = false}) async {
    final api = context.read<ApiClient>();
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await api.get('/admin/messages') as Map<String, dynamic>;
      final convs = sortConversations([for (final c in (res['conversations'] as List? ?? const [])) Conversation.fromJson(c as Map<String, dynamic>)]);
      var unread = _unread;
      try {
        final u = await api.get('/me/unread');
        final by = (u is Map ? u['supportByUser'] : null) as Map? ?? const {};
        unread = {for (final e in by.entries) '${e.key}': (e.value as num).toInt()};
      } catch (_) {/* badges are optional */}
      if (!mounted) return;
      setState(() {
        _all = convs;
        _unread = unread;
        _error = null;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể tải danh sách phản hồi';
        _loading = false;
      });
    }
  }

  Future<void> _open(Conversation c) async {
    setState(() => _unread = {..._unread}..remove(c.userId));
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: context.read<ApiClient>()),
          ChangeNotifierProvider<AdminSession>.value(value: context.read<AdminSession>()),
        ],
        child: AdminThreadPage(conversation: c, packageLabels: _packages),
      ),
    ));
    if (mounted) _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = filterConversations(_all, query: _query, onlyAwaiting: _onlyAwaiting);
    final awaiting = awaitingCount(_all);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Tìm tên hoặc tên đăng nhập', prefixIcon: Icon(Icons.search), isDense: true),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(spacing: 8, children: [
          ChoiceChip(label: Text('Tất cả ${_all.length}'), selected: !_onlyAwaiting, onSelected: (_) => setState(() => _onlyAwaiting = false)),
          ChoiceChip(label: Text(awaiting > 0 ? 'Chưa trả lời $awaiting' : 'Chưa trả lời'), selected: _onlyAwaiting, onSelected: (_) => setState(() => _onlyAwaiting = true)),
        ]),
      ),
      if (_error != null && _all.isNotEmpty)
        Container(width: double.infinity, color: cs.error.withValues(alpha: 0.15), padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: cs.error))),
      Expanded(child: RefreshIndicator(onRefresh: () => _load(quiet: true), child: _body(filtered))),
    ]);
  }

  Widget _body(List<Conversation> filtered) {
    final cs = Theme.of(context).colorScheme;
    Widget msg(String text, {bool retry = false}) => ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(children: [
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: retry ? cs.error : cs.onSurface.withValues(alpha: 0.6))),
              if (retry) AppButton(label: 'Thử lại', variant: AppButtonVariant.ghost, onPressed: _load),
            ]),
          ),
        ]);
    if (_loading) return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))]);
    if (_error != null && _all.isEmpty) return msg(_error!, retry: true);
    if (_all.isEmpty) return msg('Chưa có ai nhắn tin cho bạn');
    if (filtered.isEmpty) return msg('Không có cuộc trò chuyện phù hợp');
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
      itemBuilder: (_, i) {
        final c = filtered[i];
        final n = _unread[c.userId] ?? 0;
        return ListTile(
          onTap: () => _open(c),
          leading: CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.2), child: Text(initial(c.userName), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700))),
          title: Row(children: [
            Expanded(child: Text(c.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(shortTime(c.lastMessageAt), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          ]),
          subtitle: Row(children: [
            Expanded(child: Text(c.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (n > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(10)),
                child: Text(n > 9 ? '9+' : '$n', semanticsLabel: 'Tin chưa đọc', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              )
            else if (c.awaitingReply)
              Semantics(label: 'Chưa trả lời', child: Container(margin: const EdgeInsets.only(left: 8), width: 10, height: 10, decoration: const BoxDecoration(color: Brand.warning, shape: BoxShape.circle))),
          ]),
        );
      },
    );
  }
}
