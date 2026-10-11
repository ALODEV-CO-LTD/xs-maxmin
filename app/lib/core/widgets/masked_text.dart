import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../mask_store.dart';

/// A figure that shows "••••" while [MaskStore.masked] (the real text is never built then).
class MaskedText extends StatelessWidget {
  const MaskedText(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) {
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    return Text(masked ? '••••' : text, style: style, textAlign: textAlign);
  }
}

/// Toolbar with the "Ẩn số liệu" switch and the "Hiện số liệu" button (asks for the password).
class MaskBar extends StatelessWidget {
  const MaskBar({super.key});
  @override
  Widget build(BuildContext context) {
    final mask = context.watch<MaskStore>();
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      FilterChip(
        avatar: Icon(mask.enabled ? Icons.visibility_off : Icons.visibility, size: 18),
        label: Text(mask.enabled ? 'Số liệu đang ẩn' : 'Ẩn số liệu'),
        selected: mask.enabled,
        onSelected: (v) => mask.setEnabled(v),
      ),
      if (mask.enabled)
        FilledButton.tonalIcon(
          icon: Icon(mask.revealed ? Icons.lock : Icons.lock_open, size: 18),
          label: Text(mask.revealed ? 'Ẩn lại' : 'Hiện số liệu'),
          onPressed: () => mask.revealed ? mask.cover() : showRevealDialog(context),
        ),
      if (mask.enabled)
        PopupMenuButton<int>(
          tooltip: 'Thời gian hiện',
          icon: const Icon(Icons.timer_outlined),
          onSelected: mask.setRevealSeconds,
          itemBuilder: (_) => [
            for (final s in MaskStore.revealChoices) CheckedPopupMenuItem(value: s, checked: s == mask.revealSeconds, child: Text(s >= 60 ? '${s ~/ 60} phút' : '$s giây')),
          ],
        ),
    ]);
  }
}

Future<void> showRevealDialog(BuildContext context) async {
  final api = context.read<ApiClient>();
  final mask = context.read<MaskStore>();
  final ctrl = TextEditingController();
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Hiện số liệu'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Nhập mật khẩu tài khoản để xem số liệu.'),
          const SizedBox(height: 12),
          TextField(controller: ctrl, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: 'Mật khẩu', errorText: error)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await mask.revealWithPassword(api, ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on ApiError catch (e) {
                      setState(() {
                        busy = false;
                        error = e.message;
                      });
                    }
                  },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ),
  );
}
