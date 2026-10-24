import 'dart:io';
import '../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import 'archived_chats.dart';
import 'friends_controller.dart';
import '../../core/widgets/app_button.dart';

/// Texts of the keep-alive switch (shown in the sheet, and checked by a test: they must be honest about the battery).
const keepAliveTitle = 'Giữ kết nối để nhận tin nhắn và cuộc gọi khi thoát app';

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
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cài đặt tin nhắn', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(keepAliveTitle),
                value: c.keepAlive,
                onChanged: (v) async {
                  await c.setKeepAlive(v);
                  _refresh();
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SvgIcon(_allowed == true ? AppSvg.bell : AppSvg.bellOff, color: _allowed == true ? context.okColor : Brand.warning),
                title: Text(_allowed == true ? 'Thông báo đang bật' : 'Thông báo đang tắt'),
                trailing: _allowed == true
                    ? null
                    : AppButton(
                        label: 'Bật',
                        variant: AppButtonVariant.ghost,
                        onPressed: () async {
                          final t0 = DateTime.now();
                          final ok = await c.requestNotificationPermission(force: true);
                          // iOS asks only once: when it answers "no" at once (no dialog was shown) the switch is in Cài đặt.
                          if (!ok && Platform.isIOS && DateTime.now().difference(t0).inMilliseconds < 700) {
                            await launchUrl(Uri.parse('app-settings:'));
                          }
                          _refresh();
                        },
                      ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const SvgIcon(AppSvg.archive),
                title: const Text('Tin nhắn lưu trữ'),
                trailing: const SvgIcon(AppSvg.chevronRight),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // close this sheet first, the lock prompt and the list open on the page underneath
                  showArchivedChats(nav, c);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
