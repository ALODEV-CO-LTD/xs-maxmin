import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/bet_types.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import '../entries/dialogs.dart';
import 'add_bet_type_dialog.dart';
import 'customer_model.dart';
import 'scoring_editor_model.dart';

/// Cấu hình tính điểm, one editor for both places:
///  - [customer] == null: the account-wide default (GET/PUT /me/scoring-settings);
///  - [customer] set: that customer's own settings (PATCH /me/customers/:id {scoringRates}), falling back to [accountRates].
/// It does not scroll by itself: put it in a scroll view.
class ScoringConfigEditor extends StatefulWidget {
  const ScoringConfigEditor({super.key, this.customer, this.accountRates = const {}, this.onSaved});
  final Customer? customer;
  final RatesMap accountRates;

  /// Called with the saved map (customer: null = follows the account again).
  final void Function(RatesMap? saved)? onSaved;

  @override
  State<ScoringConfigEditor> createState() => _ScoringConfigEditorState();
}

class _ScoringConfigEditorState extends State<ScoringConfigEditor> {
  late final ScoringEditorModel _m = ScoringEditorModel(isCustomer: widget.customer != null, accountRates: widget.accountRates);
  bool _loading = true;
  bool _saving = false;
  String _error = '';
  String _notice = '';

  bool get _isCustomer => widget.customer != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(ScoringConfigEditor old) {
    super.didUpdateWidget(old);
    if (_isCustomer && !identical(old.accountRates, widget.accountRates)) {
      _m.accountRates = widget.accountRates;
      if (!_loading) setState(_m.buildRows);
    }
  }

  Future<void> _init() async {
    try {
      if (_isCustomer) {
        _m.load(widget.customer!.scoringRates ?? {});
      } else {
        final res = await context.read<ApiClient>().get('/me/scoring-settings');
        final rates = res is Map ? res['rates'] : null;
        _m.load(rates is Map && rates.isNotEmpty ? Map<String, dynamic>.from(rates) : defaultRates);
      }
    } on ApiError catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Không tải được cấu hình';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _m.buildRows();
    });
  }

  void _switchRegion(String id) {
    final problem = _m.switchRegion(id);
    setState(() => _error = problem);
  }

  Future<void> _remove(EditorRow r) async {
    final name = betTypeLabel(r.type);
    final cust = _isCustomer ? widget.customer!.name : '';
    final regionName = regionNames[_m.region]!;
    final kind = _m.removeKind(r);
    final message = switch (kind) {
      RemoveKind.regionType =>
        'Xoá loại "$name" của $regionName${_isCustomer ? ' ($cust)' : ''}? Số liệu đã nhập với loại này vẫn được giữ và tính theo cấu hình mặc định. Bấm Lưu để áp dụng.',
      RemoveKind.everywhere =>
        'Xoá loại "$name"${_isCustomer ? ' của $cust' : ' khỏi mọi miền'}? Số liệu đã nhập với loại này vẫn được giữ và tính theo cấu hình mặc định. Bấm Lưu để áp dụng.',
      RemoveKind.thisRegionOnly =>
        'Bỏ loại "$name" của $cust ở $regionName? Các miền khác và các khách khác vẫn giữ; bạn có thể khôi phục lại ở đây. Bấm Lưu để áp dụng.',
    };
    final ok = await confirmDialog(context, title: 'Xoá loại đánh', message: message, confirmText: kind == RemoveKind.thisRegionOnly ? 'Bỏ' : 'Xoá', danger: true);
    if (!ok || !mounted) return;
    setState(() => _m.removeRow(r));
  }

  Future<void> _add() async {
    final p = await showAddBetTypeDialog(context, existingKeys: _m.typeKeys, regionName: regionNames[_m.region]!);
    if (p == null || !mounted) return;
    setState(() => _m.addType(key: p.key, rate: p.rate, tiers: p.tiers, digits: p.digits, unit: p.unit, pointValue: p.pointValue));
  }

  Future<void> _save() async {
    final problem = _m.validate();
    if (problem.isNotEmpty) {
      setState(() {
        _error = problem;
        _notice = '';
      });
      return;
    }
    final map = _m.resultMap();
    if (!_isCustomer && map.isEmpty) {
      setState(() => _error = 'Cần ít nhất một loại đánh');
      return;
    }
    final api = context.read<ApiClient>();
    setState(() {
      _saving = true;
      _error = '';
      _notice = '';
    });
    try {
      if (_isCustomer) {
        final res = await api.patch('/me/customers/${widget.customer!.id}', {'scoringRates': map.isEmpty ? null : map}) as Map;
        final saved = res['scoringRates'] is Map ? Map<String, dynamic>.from(res['scoringRates'] as Map) : null;
        _m.load(saved ?? {});
        _notice = saved != null ? 'Đã lưu cấu hình riêng cho ${widget.customer!.name}' : '${widget.customer!.name} đang dùng cấu hình mặc định';
        widget.onSaved?.call(saved);
      } else {
        final res = await api.put('/me/scoring-settings', {'rates': map}) as Map;
        final saved = Map<String, dynamic>.from(res['rates'] as Map);
        _m.load(saved);
        _notice = 'Đã lưu cấu hình mặc định';
        widget.onSaved?.call(saved);
      }
      _m.buildRows();
    } on ApiError catch (e) {
      _error = e.status == 0 ? 'Mất kết nối tới máy chủ, chưa lưu được.' : e.message;
    } catch (_) {
      _error = 'Không lưu được cấu hình';
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final muted = TextStyle(fontSize: 13, color: context.mutedColor);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        '${_isCustomer ? 'Cấu hình dùng để tính điểm cho ${widget.customer!.name}. Dòng nào không đổi sẽ theo cấu hình mặc định.' : 'Cấu hình mặc định dùng cho mọi khách chưa có cấu hình riêng.'} '
        'Mỗi miền có thể có tỉ lệ khác nhau: chọn miền rồi sửa. Loại đánh thêm ở tab nào chỉ dùng cho miền đó.',
        style: muted,
      ),
      const SizedBox(height: 10),
      if (_error.isNotEmpty) InfoBox(_error),
      if (_notice.isNotEmpty) InfoBox(_notice, kind: InfoKind.success),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final id in editorRegions)
          ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(regionNames[id]!),
              if (_m.regionHasOverride(id)) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.circle, size: 8, color: Theme.of(context).colorScheme.primary)),
            ]),
            selected: _m.region == id,
            onSelected: (_) => _switchRegion(id),
          ),
      ]),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: Text('Thêm loại đánh (${regionNames[_m.region]})')),
      ),
      const SizedBox(height: 8),
      for (final r in _m.rows) _rowCard(context, r),
      const SizedBox(height: 8),
      Text(_m.overrideCount > 0 ? '${_m.overrideCount} mục riêng' : (_isCustomer ? 'Đang dùng cấu hình mặc định' : 'Chưa có cấu hình riêng theo miền'), style: muted),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _saving ? null : () => setState(_m.resetAll), child: Text(_isCustomer ? 'Bỏ cấu hình riêng' : 'Đặt lại mặc định'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(onPressed: _saving || !_m.dirty ? null : _save, child: Text(_saving ? 'Đang lưu...' : (_isCustomer ? 'Lưu cấu hình khách này' : 'Lưu cấu hình')))),
      ]),
    ]);
  }

  Widget _rowCard(BuildContext context, EditorRow r) {
    final own = _m.isRegionOnly(r);
    final scheme = Theme.of(context).colorScheme;
    final tag = _m.tag(r);
    return Card(
      key: ValueKey('${_m.version}-${r.type}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: r.off ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(betTypeLabel(r.type), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text('(${r.type})', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: (own ? scheme.primary : scheme.outline).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Text(tag, style: TextStyle(fontSize: 12, color: own ? scheme.primary : context.mutedColor)),
            ),
          ]),
          Wrap(children: [
            if (r.off) TextButton(onPressed: () => setState(() => _m.restoreRow(r)), child: const Text('Khôi phục')),
            if (own) TextButton(onPressed: () => setState(() => _m.resetRow(r)), child: const Text('Theo chung')),
            if (!r.off) TextButton(style: TextButton.styleFrom(foregroundColor: context.badColor), onPressed: () => _remove(r), child: const Text('Xoá')),
          ]),
          if (!r.off) ...[
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('rate-${_m.version}-${r.type}'),
                  initialValue: r.rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Tỉ lệ ăn', isDense: true),
                  onChanged: (v) => setState(() => r.rate = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('digits-${_m.version}-${r.type}'),
                  initialValue: r.digits,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'So khớp', isDense: true),
                  items: [for (final d in digitOptions) DropdownMenuItem(value: d, child: Text('$d số cuối'))],
                  onChanged: (v) => setState(() => r.digits = v ?? 2),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('unit-${_m.version}-${r.type}'),
                  initialValue: r.unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tính theo', isDense: true),
                  items: const [DropdownMenuItem(value: 'point', child: Text('Điểm')), DropdownMenuItem(value: 'money', child: Text('Tiền'))],
                  onChanged: (v) => setState(() => r.unit = v ?? 'money'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: r.unit == 'point'
                    ? TextFormField(
                        key: ValueKey('pv-${_m.version}-${r.type}'),
                        initialValue: r.pointValue,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '1 điểm = (đồng)', isDense: true),
                        onChanged: (v) => setState(() => r.pointValue = v),
                      )
                    : const SizedBox.shrink(),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 0, children: [
              for (final t in prizeTiers)
                if (!(t.key == 'giaiTam' && _m.region == 'mb'))
                  FilterChip(
                    label: Text(t.key == 'giaiTam' ? 'Giải tám' : t.label),
                    selected: r.tiers.contains(t.key),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => r.toggleTier(t.key)),
                  ),
            ]),
          ],
        ]),
      ),
    );
  }
}
