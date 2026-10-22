import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_button.dart';

/// Card with an optional title row (+ trailing widget) and a column of children.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.children, this.danger = false});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: danger ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.error.withValues(alpha: 0.6))) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text(title!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: danger ? cs.error : null))),
                ?trailing,
              ]),
            ),
          ...children,
        ]),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, {super.key, this.value, this.child});
  final String label;
  final String? value;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(flex: 4, child: Text(label, style: TextStyle(color: context.mutedColor, fontSize: 14))),
          const SizedBox(width: 8),
          Expanded(flex: 6, child: Align(alignment: Alignment.centerRight, child: child ?? Text(value ?? '-', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)))),
        ]),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.color, this.small = false});
  final String text;
  final Color? color;

  /// About half the size (a tag next to a title, e.g. "Đang dùng").
  final bool small;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.mutedColor;
    return Container(
      padding: small ? const EdgeInsets.symmetric(horizontal: 6, vertical: 1) : const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Text(text, style: TextStyle(color: c, fontSize: small ? 10 : 12.5, fontWeight: FontWeight.w600, height: small ? 1.3 : null)),
    );
  }
}

/// Error / success / warning message box.
class NoticeBox extends StatelessWidget {
  const NoticeBox(this.text, {super.key, this.kind = NoticeKind.error});
  final String text;
  final NoticeKind kind;
  @override
  Widget build(BuildContext context) {
    final c = switch (kind) { NoticeKind.error => Theme.of(context).colorScheme.error, NoticeKind.success => context.okColor, NoticeKind.warning => Brand.warning };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: kind == NoticeKind.warning ? null : c)),
    );
  }
}

enum NoticeKind { error, success, warning }

/// Password input: obscured, no suggestions/learning, with a show/hide toggle. Never logged or stored.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, required this.label, this.enabled = true, this.autofocus = false, this.errorText, this.onSubmitted, this.textInputAction, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final bool autofocus;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: widget.errorText,
          suffixIcon: IconButton(
            tooltip: _show ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
      );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String confirmText = 'Xác nhận', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false)),
        AppButton(label: confirmText, variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok == true;
}

Future<void> copyText(BuildContext context, String text, {String done = 'Đã sao chép'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
}

/// A dialog with N secret fields. [validate] returns a client-side error (or null); [submit] calls the API and
/// returns the success message (throw [ApiError] to show the server's message). Passwords stay in the controllers
/// of this dialog only and are cleared on success.
class SecretFormDialog extends StatefulWidget {
  const SecretFormDialog({super.key, required this.title, this.description, required this.labels, required this.submitLabel, required this.validate, required this.submit});
  final String title;
  final String? description;
  final List<String> labels;
  final String submitLabel;
  final String? Function(List<String> values) validate;
  final Future<String> Function(List<String> values) submit;
  @override
  State<SecretFormDialog> createState() => _SecretFormDialogState();
}

class _SecretFormDialogState extends State<SecretFormDialog> {
  late final List<TextEditingController> _c = [for (final _ in widget.labels) TextEditingController()];
  String? _error;
  String? _success;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go() async {
    final values = [for (final c in _c) c.text];
    final bad = widget.validate(values);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final msg = await widget.submit(values);
      for (final c in _c) {
        c.clear();
      }
      if (mounted) setState(() => _success = msg);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Đã xảy ra lỗi, vui lòng thử lại');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _success != null;
    return AppDialog(
      title: widget.title,
      closeEnabled: !_busy,
      description: widget.description,
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) NoticeBox(_error!),
          if (_success != null) NoticeBox(_success!, kind: NoticeKind.success),
          if (!done)
            for (var i = 0; i < _c.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              PasswordField(
                controller: _c[i],
                label: widget.labels[i],
                enabled: !_busy,
                autofocus: i == 0,
                textInputAction: i == _c.length - 1 ? TextInputAction.done : TextInputAction.next,
                onSubmitted: i == _c.length - 1 ? (_) => _go() : null,
              ),
            ],
      ]),
      actions: [
        AppButton(label: done ? 'Đóng' : 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        if (!done) AppButton(label: widget.submitLabel, variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _go),
      ],
    );
  }
}

/// Mã khôi phục shown exactly once; "Tiếp tục" is enabled only after the user ticks that it was saved.
class RecoveryCodeDisplay extends StatefulWidget {
  const RecoveryCodeDisplay({super.key, required this.code, required this.onConfirmed, this.continueText = 'Tiếp tục'});
  final String code;
  final VoidCallback onConfirmed;
  final String continueText;
  @override
  State<RecoveryCodeDisplay> createState() => _RecoveryCodeDisplayState();
}

class _RecoveryCodeDisplayState extends State<RecoveryCodeDisplay> {
  bool _saved = false;
  bool _copied = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoticeBox(
        'Đây là mã khôi phục của bạn. Mã chỉ hiển thị một lần duy nhất và không ai (kể cả quản trị viên) xem lại được. Hãy ghi lại hoặc lưu ở nơi an toàn. Có mã này, bạn đặt lại được mật khẩu khi quên - vì vậy đừng chia sẻ cho người khác.',
        kind: NoticeKind.warning,
      ),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outline)),
        child: SelectableText(widget.code, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ),
      const SizedBox(height: 12),
      AppButton(
        icon: _copied ? Icons.check : null,
        svg: _copied ? null : AppSvg.copy,
        label: _copied ? 'Đã sao chép' : 'Sao chép mã',
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: widget.code));
          if (mounted) setState(() => _copied = true);
        },
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _saved,
        onChanged: (v) => setState(() => _saved = v ?? false),
        title: const Text('Tôi đã lưu mã khôi phục ở nơi an toàn.'),
      ),
      AppButton(label: widget.continueText, variant: AppButtonVariant.primary, block: true, onPressed: _saved ? widget.onConfirmed : null),
    ]);
  }
}
