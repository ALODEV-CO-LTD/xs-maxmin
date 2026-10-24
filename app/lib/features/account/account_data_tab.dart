import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_dialog.dart';
import 'account_controller.dart';
import 'account_widgets.dart';
import '../scoring/deletion_schedules_page.dart' show DeletionSchedules;
import 'auth_flows.dart' show errorText;
import '../../core/widgets/app_button.dart';

/// Must match backend/lib/src/data_wipe.dart (the single definition of the wipe scope).
const wipeDeletes = 'số liệu đã nhập, danh sách khách hàng, mẫu cú pháp, lịch xoá tự động, nhật ký cuộc gọi, tin nhắn phản hồi với Admin, lịch sử giao dịch và các yêu cầu thanh toán chưa duyệt';
const wipeKeeps = 'Tài khoản, gói dịch vụ, danh sách bạn bè, tin nhắn trò chuyện với bạn bè, Mã ID và cấu hình tính điểm được giữ nguyên.';

/// Dữ liệu: scheduled deletion (Lịch xoá dữ liệu) and "delete all my data". The recovery code is in Thiết bị & riêng tư, like the web.
class AccountDataTab extends StatelessWidget {
  const AccountDataTab({super.key, required this.ctl});
  final AccountController ctl;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionCard(title: 'Lịch xoá dữ liệu', children: [DeletionSchedules(api: context.read<ApiClient>())]),
        const SizedBox(height: 14),
        const _DeleteDataCard(),
      ]);
}

class RecoveryCodeCard extends StatefulWidget {
  const RecoveryCodeCard({super.key, required this.ctl});
  final AccountController ctl;
  @override
  State<RecoveryCodeCard> createState() => RecoveryCodeCardState();
}

class RecoveryCodeCardState extends State<RecoveryCodeCard> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  String? _newCode;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return setState(() => _error = 'Nhập mật khẩu hiện tại để tiếp tục');
    final api = context.read<ApiClient>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await api.post('/me/recovery-code', {'currentPassword': _password.text});
      final code = res is Map ? res['recoveryCode'] : null;
      if (code is! String || code.isEmpty) throw ApiError(500, 'Không tạo được mã khôi phục');
      _password.clear();
      if (mounted) setState(() => _newCode = code);
      await widget.ctl.load(silent: true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.ctl.me?.hasRecoveryCode == true;
    return SectionCard(title: 'Mã khôi phục', children: [
      if (_newCode != null)
        RecoveryCodeDisplay(code: _newCode!, continueText: 'Xong', onConfirmed: () => setState(() => _newCode = null))
      else ...[
        Text(
          has
              ? 'Bạn đã có mã khôi phục (vì lý do bảo mật, mã cũ không thể xem lại). Tạo mã mới sẽ vô hiệu mã cũ. Mã chỉ hiển thị một lần.'
              : 'Tài khoản chưa có mã khôi phục. Tạo mã để có thể đặt lại mật khẩu khi quên (mã chỉ hiển thị một lần).',
          style: TextStyle(color: context.mutedColor, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        if (_error != null) NoticeBox(_error!),
        PasswordField(controller: _password, label: 'Mật khẩu hiện tại', enabled: !_busy, onSubmitted: (_) => _submit()),
        const SizedBox(height: 12),
        AppButton(label: has ? 'Đổi mã khôi phục' : 'Tạo mã khôi phục', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _submit),
      ],
    ]);
  }
}

/// Confirm + password + POST /me/delete-data. Null = the user backed out; otherwise `error` is null on success.
Future<({String? error})?> runDeleteData(BuildContext context) async {
  final api = context.read<ApiClient>();
  if (!await confirmDialog(context, title: 'Xoá toàn bộ dữ liệu', message: 'CẢNH BÁO: Thao tác này sẽ xoá vĩnh viễn: $wipeDeletes. $wipeKeeps Bạn có chắc chắn muốn tiếp tục?', confirmText: 'Tiếp tục', danger: true)) return null;
  if (!context.mounted) return null;
  final password = await showDialog<String>(context: context, builder: (_) => const _PasswordPrompt());
  if (password == null || password.isEmpty) return null;
  try {
    await api.post('/me/delete-data', {'password': password});
    return (error: null);
  } catch (e) {
    return (error: e is ApiError ? e.message : 'Không xoá được dữ liệu');
  }
}

/// The compact "Xoá toàn bộ dữ liệu" button (Tổng quan, under the all-time figures). [onDeleted] runs after a successful wipe.
class DeleteDataButton extends StatefulWidget {
  const DeleteDataButton({super.key, this.onDeleted});
  final VoidCallback? onDeleted;
  @override
  State<DeleteDataButton> createState() => _DeleteDataButtonState();
}

class _DeleteDataButtonState extends State<DeleteDataButton> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await runDeleteData(context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r?.error;
    });
    if (r != null && r.error == null) widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) NoticeBox(_error!),
        AppButton(label: 'Xoá toàn bộ dữ liệu', svg: AppSvg.delete, variant: AppButtonVariant.danger, loading: _busy, block: true, onPressed: _busy ? null : _delete),
      ]);
}

class _DeleteDataCard extends StatefulWidget {
  const _DeleteDataCard();
  @override
  State<_DeleteDataCard> createState() => _DeleteDataCardState();
}

class _DeleteDataCardState extends State<_DeleteDataCard> {
  String? _error;
  String? _success;
  bool _busy = false;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final r = await runDeleteData(context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _error = r.error;
        _success = r.error == null ? 'Đã xoá toàn bộ dữ liệu của bạn.' : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: 'Xoá toàn bộ dữ liệu', danger: true, children: [
      Text('Xoá: $wipeDeletes. $wipeKeeps Không thể hoàn tác.', style: TextStyle(color: context.mutedColor, fontSize: 13.5)),
      const SizedBox(height: 12),
      if (_error != null) NoticeBox(_error!),
      if (_success != null) NoticeBox(_success!, kind: NoticeKind.success),
      AppButton(label: 'Xoá toàn bộ dữ liệu', variant: AppButtonVariant.danger, loading: _busy, block: true, onPressed: _busy ? null : _delete),
    ]);
  }
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt();
  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: 'Xác nhận xoá dữ liệu',
        body: PasswordField(controller: _c, label: 'Mật khẩu đăng nhập', autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(context)),
          AppButton(label: 'Xoá dữ liệu', svg: AppSvg.delete, variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(context, _c.text)),
        ],
      );
}
