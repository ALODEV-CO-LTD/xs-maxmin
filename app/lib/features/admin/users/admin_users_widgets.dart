import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_button.dart';

Future<bool> adminConfirm(BuildContext context, {required String title, required String message, required String confirmText, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(c, false)),
        AppButton(label: confirmText, variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary, onPressed: () => Navigator.pop(c, true)),
      ],
    ),
  );
  return ok == true;
}

class AdminChip extends StatelessWidget {
  const AdminChip(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.mutedColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

class AdminBanner extends StatelessWidget {
  const AdminBanner(this.text, {super.key, this.error = true});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final c = error ? context.badColor : context.okColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Text(text, style: TextStyle(color: c)),
    );
  }
}

/// A value shown once (password, recovery code, support code) with a copy button.
class SecretRow extends StatelessWidget {
  const SecretRow({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: context.mutedColor)),
            SelectableText(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
        ),
        AppButton(label: 'Chép', variant: AppButtonVariant.ghost, icon: Icons.copy, onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã chép')));
          }),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(text, style: TextStyle(color: context.mutedColor), textAlign: TextAlign.center)));
}
