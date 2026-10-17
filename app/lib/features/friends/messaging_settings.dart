import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'friends_controller.dart';
import '../../core/widgets/app_button.dart';

/// Texts of the keep-alive switch (shown in the sheet, and checked by a test: they must be honest about the battery).
const keepAliveTitle = 'Giữ kết nối để nhận tin nhắn và cuộc gọi khi thoát app';
const keepAliveExplain = 'Tin nhắn mã hoá 2 đầu không lưu trên máy chủ nên chỉ nhận được khi MAMBA đang kết nối. Bật mục này sẽ chạy một dịch vụ nền với thông báo cố định "Đang giữ kết nối", giữ kết nối mạng liên tục nên TỐN PIN HƠN và dùng dữ liệu nền. Tắt nếu bạn không cần. Một số hãng máy (Xiaomi, Oppo, Samsung...) vẫn có thể tự tắt app nền khi tiết kiệm pin.';

Future<void> showMessagingSettings(BuildContext context, FriendsController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _Sheet(c: c),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.c});
  final FriendsController c;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a = await widget.c.notifier.allowed;
    if (mounted) setState(() => _allowed = a);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cài đặt tin nhắn & cuộc gọi', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(keepAliveTitle),
              subtitle: const Padding(padding: EdgeInsets.only(top: 4), child: Text(keepAliveExplain)),
              value: c.keepAlive,
              onChanged: (v) async {
                await c.setKeepAlive(v);
                _refresh();
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_allowed == true ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, color: _allowed == true ? context.okColor : Brand.warning),
              title: Text(_allowed == true ? 'Thông báo đang bật' : 'Thông báo đang tắt'),
              subtitle: const Text('Thông báo tin nhắn chỉ ghi "Tin nhắn mới từ <tên>", không bao giờ hiện nội dung.'),
              trailing: _allowed == true
                  ? null
                  : AppButton(label: 'Bật', variant: AppButtonVariant.ghost, onPressed: () async {
                        await c.requestNotificationPermission(force: true);
                        _refresh();
                      }),
            ),
          ]),
        ),
      ),
    );
  }
}
