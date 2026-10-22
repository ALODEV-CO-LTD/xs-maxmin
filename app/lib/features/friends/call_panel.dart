import 'dart:async';
import '../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'call_service.dart';

String formatElapsed(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

/// Full-screen call UI (CallOverlay.vue): incoming (Nghe máy / Từ chối), outgoing (Đang gọi / Đang đổ chuông),
/// connecting and connected (timer, mute, speaker, hang up). Shown above every route by MessagingHost, so a call rings on any screen.
class CallPanel extends StatefulWidget {
  const CallPanel({super.key, required this.call});
  final CallService call;
  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.call.status == CallStatus.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _statusText(CallService c) => switch (c.status) {
        CallStatus.incoming => 'Cuộc gọi thoại đến',
        CallStatus.outgoing => c.ringing ? 'Đang đổ chuông…' : 'Đang gọi…',
        CallStatus.connecting => 'Đang kết nối…',
        CallStatus.connected => c.reconnecting ? 'Đang kết nối lại…' : formatElapsed(DateTime.now().difference(c.startedAt ?? DateTime.now())),
        CallStatus.idle => '',
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final name = c.peer?.name ?? '';
    final connected = c.status == CallStatus.connected;
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              CircleAvatar(
                radius: 52,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: 44, color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 20),
              Text(name, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_statusText(c), style: theme.textTheme.titleMedium?.copyWith(color: context.mutedColor)),
              if (connected && c.health.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(c.health, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: c.health.startsWith('Âm thanh đã thông') ? context.okColor : Brand.warning)),
              ],
              const Spacer(flex: 3),
              if (c.status == CallStatus.incoming)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundButton(icon: AppSvg.phoneOff, color: context.badColor, label: 'Từ chối', onTap: c.reject),
                    _RoundButton(icon: AppSvg.phone, color: context.okColor, label: 'Nghe máy', onTap: c.accept),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (connected || c.status == CallStatus.outgoing || c.status == CallStatus.connecting) _RoundButton(icon: c.muted ? AppSvg.micOff : AppSvg.mic, color: c.muted ? Brand.warning : theme.colorScheme.surfaceContainerHighest, label: c.muted ? 'Bật micro' : 'Tắt micro', onTap: c.toggleMute),
                    _RoundButton(icon: AppSvg.phoneOff, color: context.badColor, label: 'Kết thúc', onTap: c.hangUp),
                    if (connected) _RoundButton(icon: c.speaker ? AppSvg.volumeOn : AppSvg.volumeOff, color: c.speaker ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest, label: c.speaker ? 'Loa ngoài' : 'Loa trong', onTap: c.toggleSpeaker),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.color, required this.label, required this.onTap});
  final AppSvg icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          button: true,
          label: label,
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 68, height: 68, child: SvgIcon(icon, size: 30, color: Colors.white))),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ]);
}
