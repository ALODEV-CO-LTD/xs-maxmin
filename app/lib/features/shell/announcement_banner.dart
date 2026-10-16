import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

/// Notices from Admin for customers (web: components/AnnouncementBanner.vue, `GET /announcements`): the maintenance
/// notice (cannot be closed while it is on) and announcements the user can hide one by one. What was hidden is kept on
/// this device.
class Announcement {
  const Announcement({required this.id, required this.kind, required this.title, required this.body});
  final String id, kind, title, body;

  static Announcement? fromJson(Object? j) {
    if (j is! Map || '${j['id'] ?? ''}'.isEmpty) return null;
    return Announcement(id: '${j['id']}', kind: '${j['kind'] ?? 'info'}', title: '${j['title'] ?? ''}', body: '${j['body'] ?? ''}');
  }

  String get kindLabel => switch (kind) { 'maintenance' => 'Bảo trì', 'policy' => 'Chính sách', _ => 'Thông báo' };
}

class NoticesState {
  const NoticesState({this.maintenance = false, this.maintenanceMessage = '', this.announcements = const []});
  final bool maintenance;
  final String maintenanceMessage;
  final List<Announcement> announcements;

  factory NoticesState.fromJson(Map<String, dynamic> j) {
    final m = j['maintenance'];
    return NoticesState(
      maintenance: m is Map && m['enabled'] == true,
      maintenanceMessage: m is Map ? '${m['message'] ?? ''}' : '',
      announcements: [for (final a in (j['announcements'] as List? ?? const [])) ?Announcement.fromJson(a)],
    );
  }

  /// Announcements not hidden by the user.
  List<Announcement> visible(Set<String> hidden) => [for (final a in announcements) if (!hidden.contains(a.id)) a];
}

const dismissedNoticesKey = 'xoso_dismissed_notices';
const noticeRefresh = Duration(minutes: 5);

/// Banner area at the top of the customer's screens; shows nothing while there is nothing to show or while offline.
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key, this.refresh = noticeRefresh});
  final Duration refresh;
  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  NoticesState _state = const NoticesState();
  Set<String> _hidden = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadHidden();
    _load();
    _timer = Timer.periodic(widget.refresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadHidden() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getStringList(dismissedNoticesKey);
      if (saved != null && mounted) setState(() => _hidden = {..._hidden, ...saved});
    } catch (_) {/* the notices simply show again */}
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().get('/announcements') as Map<String, dynamic>;
      if (mounted) setState(() => _state = NoticesState.fromJson(res));
    } catch (_) {/* offline or not allowed: keep what we have */}
  }

  Future<void> _hide(String id) async {
    setState(() => _hidden = {..._hidden, id});
    try {
      final p = await SharedPreferences.getInstance();
      // Only ids still announced are kept, so the list does not grow for ever.
      final keep = {for (final a in _state.announcements) a.id}.intersection(_hidden);
      await p.setStringList(dismissedNoticesKey, keep.toList());
    } catch (_) {/* hidden for this run only */}
  }

  @override
  Widget build(BuildContext context) {
    final list = _state.visible(_hidden);
    if (!_state.maintenance && list.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        children: [
          if (_state.maintenance)
            _NoticeCard(
              key: const ValueKey('maintenance'),
              warning: true,
              title: 'Hệ thống đang bảo trì.',
              body: _state.maintenanceMessage.isEmpty ? 'Một số chức năng có thể tạm thời không hoạt động.' : _state.maintenanceMessage,
            ),
          for (final a in list)
            _NoticeCard(key: ValueKey(a.id), warning: a.kind == 'maintenance', title: '${a.kindLabel}: ${a.title}', body: a.body, onClose: () => _hide(a.id)),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({super.key, required this.warning, required this.title, required this.body, this.onClose});
  final bool warning;
  final String title, body;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    final c = warning ? Brand.warning : context.okColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(12, 8, onClose == null ? 12 : 0, 8),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(warning ? Icons.build_circle_outlined : Icons.campaign_outlined, size: 20, color: warning ? null : c),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(body, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
        ),
        if (onClose != null) IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 40, minHeight: 40), tooltip: 'Ẩn thông báo', icon: const Icon(Icons.close, size: 20), onPressed: onClose),
      ]),
    );
  }
}
