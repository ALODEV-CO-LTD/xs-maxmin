import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../entries/dialogs.dart' show InfoBox;
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dialog.dart';
import 'chat_page.dart';
import 'friends_controller.dart';

/// Cài đặt tin nhắn > "Tin nhắn lưu trữ": archived conversations are hidden from the Tin nhắn list; to look at them the
/// customer retypes the layer-2 password (`POST /me/verify-password`, which also takes the login password for an
/// account that never set a layer-2 one).
Future<void> showArchivedChats(NavigatorState nav, FriendsController c) async {
  final ok = await showDialog<bool>(context: nav.context, builder: (_) => _PasswordDialog(api: c.api));
  if (ok != true) return;
  await nav.push(MaterialPageRoute<void>(builder: (_) => ArchivedChatsPage(controller: c)));
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.api});
  final ApiClient api;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _pw = TextEditingController();
  String _error = '';
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pw.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.api.post('/me/verify-password', {'password': _pw.text});
      if (mounted) Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.status == 0 ? 'Không có mạng để kiểm tra mật khẩu' : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Xem tin nhắn lưu trữ',
      description: 'Nhập mật khẩu cấp 2 để xem các cuộc trò chuyện đã lưu trữ.',
      closeEnabled: !_busy,
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _pw,
          autofocus: true,
          obscureText: !_show,
          enabled: !_busy,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Mật khẩu cấp 2',
            suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
          ),
        ),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBox(_error)),
      ]),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        AppButton(label: 'Xem', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _submit),
      ],
    );
  }
}

class ArchivedChatsPage extends StatelessWidget {
  const ArchivedChatsPage({super.key, required this.controller});
  final FriendsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Tin nhắn lưu trữ')),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final archived = c.chat?.archived ?? const <String>{};
          final list = [for (final f in c.conversations) if (archived.contains(f.id)) f];
          if (list.isEmpty) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Chưa lưu trữ cuộc trò chuyện nào.', style: TextStyle(color: context.mutedColor))));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final f = list[i];
              return ListTile(
                leading: CircleAvatar(child: Text(c.nameOf(f).trim().isEmpty ? '?' : c.nameOf(f).trim()[0].toUpperCase())),
                title: Text(c.nameOf(f), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(f.lastMessage ?? 'Chưa có tin nhắn', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(onPressed: () => c.chat?.setArchived([f.id], false), child: const Text('Bỏ lưu trữ')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatPage(controller: c, friend: f))),
              );
            },
          );
        },
      ),
    );
  }
}
