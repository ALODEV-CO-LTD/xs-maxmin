import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/admin_session.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'admin_recovery_requests.dart';
import 'admin_user_detail.dart';
import 'admin_users_logic.dart';
import 'admin_users_widgets.dart';
import '../../../core/widgets/app_button.dart';

/// Admin - Khách hàng: searchable, paged customer list + recovery-request queue. Body only (the shell draws the AppBar).
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      UsersListBody(api: context.read<ApiClient>(), rights: UserRights.of(context.watch<AdminSession>()));
}

class UsersListBody extends StatefulWidget {
  const UsersListBody({super.key, required this.api, required this.rights});
  final ApiClient api;
  final UserRights rights;
  @override
  State<UsersListBody> createState() => _UsersListBodyState();
}

class _UsersListBodyState extends State<UsersListBody> {
  final _pager = UsersPager();
  final _q = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  int _total = 0, _pending = 0;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    if (!widget.rights.view) {
      setState(() => _loading = false);
      return;
    }
    try {
      final q = _q.text.trim();
      final res = await widget.api.get('/admin/users${q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}') as Map<String, dynamic>;
      if (!mounted || seq != _seq) return;
      final page = UsersPage.fromJson(res);
      setState(() {
        _total = page.total;
        _pager.reset(page.users);
        _error = null;
      });
      if (widget.rights.recovery) _loadPending();
    } on ApiError catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _loadPending() async {
    try {
      final res = await widget.api.get('/admin/recovery-requests') as Map<String, dynamic>;
      if (mounted) setState(() => _pending = RecoveryQueue.fromJson(res).pending);
    } on ApiError {
      // The queue is secondary; the list still works.
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _loading = true);
      _load();
    });
  }

  Future<void> _open(Subscriber s) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AdminUserDetailPage(
          api: widget.api,
          rights: widget.rights,
          userId: s.id,
          initial: s,
          onChanged: (u) => setState(() => _pager.replace(u)),
          onDeleted: () => setState(() {
            _pager.remove(s.id);
            _total = _pager.all.length;
          }),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    if (!widget.rights.view) return const EmptyState('Tài khoản của bạn chưa được cấp quyền xem khách hàng.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tổng cộng $_total khách hàng', style: TextStyle(color: context.mutedColor)),
          const SizedBox(height: 12),
          if (widget.rights.recovery)
            Card(
              child: ListTile(
                leading: const Icon(Icons.support_agent),
                title: const Text('Yêu cầu hỗ trợ khôi phục'),
                subtitle: Text(_pending > 0 ? '$_pending yêu cầu chờ duyệt' : 'Không có yêu cầu chờ duyệt'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => AdminRecoveryRequestsPage(api: widget.api, onCount: (n) => _pending = n)));
                  if (mounted) _loadPending();
                },
              ),
            ),
          if (widget.rights.recovery) const SizedBox(height: 12),
          TextField(
            controller: _q,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tìm theo tên...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () { _q.clear(); _onSearch(''); setState(() {}); }),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) AdminBanner(_error!),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_pager.all.isEmpty && _error == null)
            const EmptyState('Không có khách hàng nào')
          else ...[
            for (final s in _pager.visible) _tile(context, s),
            if (_pager.hasMore)
              AppButton(label: 'Xem thêm (${_pager.all.length - _pager.shown})', variant: AppButtonVariant.secondary, onPressed: () => setState(_pager.loadMore)),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Subscriber s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(s),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16), overflow: TextOverflow.ellipsis)),
                  AdminChip(s.active ? 'Hoạt động' : 'Hết hạn', color: s.active ? context.okColor : Brand.warning),
                  if (s.locked) ...[const SizedBox(width: 6), AdminChip('Đã khoá', color: context.badColor)],
                ]),
                const SizedBox(height: 4),
                Text('@${s.username} · ${s.packageLabel} · HSD ${fmtDate(s.expiresAt)}', style: TextStyle(fontSize: 13, color: context.mutedColor)),
              ]),
            ),
          ),
        ),
      );
}
