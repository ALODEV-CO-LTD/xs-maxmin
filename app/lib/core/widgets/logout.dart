import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_store.dart';
import 'app_button.dart';

/// Asks for confirmation, then signs out (the router returns to the login screen; the messaging hub and keys are
/// wiped by their own listeners). Used by every place that offers "Đăng xuất" (account, more tab, admin drawer).
Future<void> confirmLogout(BuildContext context) async {
  final auth = context.read<AuthStore>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Đăng xuất'),
      content: const Text('Bạn có chắc muốn đăng xuất?'),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false)),
        AppButton(label: 'Đăng xuất', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (ok == true) await auth.logout();
}
