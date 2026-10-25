import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/svg_icon.dart';
import '../payments/payments_logic.dart' show viDateTime;
import '../settings/settings_ui.dart';
import 'trash_logic.dart';

/// Admin - Thùng rác (right trash.manage). Body only (the shell draws the AppBar). What the Admin deleted stays here for 7 days:
/// "Khôi phục" puts it back, "Xoá hẳn" removes it at once. The content of a customer's data is never shown, only how many rows.
class AdminTrashScreen extends StatefulWidget {
  const AdminTrashScreen({super.key});
  @override
  State<AdminTrashScreen> createState() => _AdminTrashScreenState();
}

class _AdminTrashScreenState extends State<AdminTrashScreen> {
  bool _loading = true;
  String? _error, _message, _busy;
  List<TrashItem> _items = [];
  int _days = 7;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/admin/trash') as Map;
      if (!mounted) return;
      setState(() {
        _days = res['trashDays'] is num ? (res['trashDays'] as num).toInt() : 7;
        _items = [for (final i in (res['items'] as List? ?? const [])) TrashItem.fromJson((i as Map).cast<String, dynamic>())];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được thùng rác'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(TrashItem t) async {
    if (!await confirmDialog(context, title: 'Khôi phục', message: 'Khôi phục "${t.label}" (${t.kindLabel.toLowerCase()})? Mọi dữ liệu đã xoá cùng được trả lại.', confirmText: 'Khôi phục')) return;
    setState(() {
      _busy = t.id;
      _error = null;
      _message = null;
    });
    try {
      await _api.post('/admin/trash/${t.id}/restore');
      _message = 'Đã khôi phục "${t.label}".';
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không khôi phục được'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _purge(TrashItem t) async {
    if (!await confirmDialog(context, title: 'Xoá hẳn', message: 'Xoá hẳn "${t.label}"? Sau đó không thể khôi phục (trừ khi còn trong một bản sao lưu).', confirmText: 'Xoá hẳn', danger: true)) return;
    setState(() {
      _busy = t.id;
      _error = null;
      _message = null;
    });
    try {
      await _api.delete('/admin/trash/${t.id}');
      _message = 'Đã xoá hẳn "${t.label}".';
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không xoá được'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Text('Những gì Admin đã xoá được giữ $_days ngày để khôi phục khi xoá nhầm. Dữ liệu khách tự xoá không nằm ở đây: hãy khôi phục từ bản sao lưu (Cài đặt > Sao lưu).', style: TextStyle(color: context.mutedColor, fontSize: 13)),
          const SizedBox(height: 10),
          if (_error != null) Banner2(_error!),
          if (_message != null) Banner2(_message!, error: false),
          if (_loading)
            const Placeholder2('', busy: true)
          else if (_items.isEmpty)
            const Placeholder2('Thùng rác trống.')
          else
            for (final t in _items)
              Card(
                key: ValueKey('trash-${t.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SvgIcon(t.icon, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(t.timeLeft, style: TextStyle(color: t.daysLeft <= 1 ? context.badColor : context.mutedColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 4),
                    Text('${t.kindLabel} · xoá ${viDateTime(t.deletedAt)}${t.deletedByName == null ? '' : ' bởi ${t.deletedByName}'}', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
                    if (countsSummary(t.counts).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(countsSummary(t.counts), style: const TextStyle(fontSize: 13))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: AppButton(label: 'Khôi phục', variant: AppButtonVariant.primary, loading: _busy == t.id, onPressed: _busy != null ? null : () => _restore(t))),
                      const SizedBox(width: 10),
                      Expanded(child: AppButton(label: 'Xoá hẳn', variant: AppButtonVariant.secondary, onPressed: _busy != null ? null : () => _purge(t))),
                    ]),
                  ]),
                ),
              ),
        ],
      ),
    );
  }
}
