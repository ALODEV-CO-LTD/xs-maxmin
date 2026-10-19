import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/scoring_config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../entries/dialogs.dart';
import 'add_bet_type_dialog.dart';
import 'customer_model.dart';
import 'scoring_editor_model.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/keyboard.dart';

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

  /// false = the table is only shown; "Sửa" opens the inputs.
  bool _editing = false;
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

  /// "Huỷ": drop what was not saved, load the saved config again and go back to the view.
  Future<void> _cancelEdit() async {
    setState(() {
      _editing = false;
      _error = '';
      _notice = '';
    });
    await _init();
  }

  void _switchRegion(String id) {
    final problem = _m.switchRegion(id);
    setState(() => _error = problem);
  }

  Future<void> _remove(EditorRow r) async {
    final regionName = regionNames[_m.region]!;
    final message = 'Xoá "${r.label}" khỏi bảng $regionName${_isCustomer ? ' của ${widget.customer!.name}' : ''}? '
        'Số liệu đã nhập với cách này vẫn được giữ và tính theo cấu hình mặc định. Bạn có thể thêm lại bằng "+ Thêm cách đánh". Bấm Lưu để áp dụng.';
    final ok = await confirmDialog(context, title: 'Xoá cách đánh', message: message, confirmText: 'Xoá', danger: true);
    if (!ok || !mounted) return;
    setState(() => _m.removeRow(r));
  }

  Future<void> _add(TableGroup g) async {
    await showAddBetTypeDialog(
      context,
      groupLabel: g.label,
      regionName: regionNames[_m.region]!,
      restorable: _m.restorable(g.id),
      onSubmit: (p) {
        final err = p.restore != null
            ? (() {
                _m.restoreKind(p.restore!);
                return '';
              })()
            : _m.addCustom(group: g.id, name: p.name, symbol: p.symbol, allTiers: p.allTiers, digits: p.digits, price: p.price, payout: p.payout);
        if (err.isEmpty) setState(() {});
        return err;
      },
    );
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
      setState(() => _error = 'Cần ít nhất một kiểu đánh');
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
      _editing = false;
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
      if (_error.isNotEmpty) InfoBox(_error),
      if (_notice.isNotEmpty) InfoBox(_notice, kind: InfoKind.success),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final id in editorRegions)
          ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(regionNames[id]!),
              if (_isCustomer && _m.regionHasOverride(id)) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.circle, size: 8, color: Theme.of(context).colorScheme.primary)),
            ]),
            selected: _m.region == id,
            onSelected: (_) => _switchRegion(id),
          ),
        if (!_editing)
          AppButton(label: 'Sửa', variant: AppButtonVariant.secondary, onPressed: () => setState(() {
                _editing = true;
                _notice = '';
              })),
      ]),
      // While editing, the actions sit in ONE row right under the regions (where "Sửa" is when viewing).
      if (_editing)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            AppButton(label: _isCustomer ? 'Bỏ riêng' : 'Đặt lại mặc định', variant: AppButtonVariant.secondary, size: AppButtonSize.small, onPressed: _saving ? null : () => setState(_m.resetAll)),
            const SizedBox(width: 6),
            AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, size: AppButtonSize.small, onPressed: _saving ? null : _cancelEdit),
            const SizedBox(width: 6),
            Expanded(child: AppButton(label: _isCustomer ? 'Lưu cấu hình khách này' : 'Lưu cấu hình', variant: AppButtonVariant.primary, loading: _saving, onPressed: _saving || !_m.dirty ? null : _save)),
          ]),
        ),
      const SizedBox(height: 8),
      for (final g in _m.groupsOf(all: _editing)) ...[
        Container(
          key: ValueKey('group-${g.group.id}'),
          margin: const EdgeInsets.only(top: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: g.group.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                TextSpan(text: ' · ${g.rows.length} cách đánh', style: TextStyle(color: context.mutedColor, fontSize: 13)),
              ])),
            ),
            if (_editing) AppButton(key: ValueKey('add-${g.group.id}'), label: '+ Thêm cách đánh', variant: AppButtonVariant.ghost, onPressed: () => _add(g.group)),
          ]),
        ),
        for (final r in g.rows) Padding(padding: const EdgeInsets.only(left: 14), child: _rowCard(context, r)),
      ],
      if (_editing) ...[
        const SizedBox(height: 8),
        Text(!_isCustomer ? '' : (_m.overrideCount > 0 ? '${_m.overrideCount} mục riêng' : 'Đang dùng cấu hình mặc định'), style: muted),
      ] else if (_isCustomer)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(_m.overrideCount > 0 ? '${_m.overrideCount} mục riêng' : 'Đang dùng cấu hình mặc định', style: muted)),
    ]);
  }

  String _fmt(String s) {
    final n = parseNum(s);
    return n == null ? s : formatNumber(n);
  }

  /// One kiểu đánh. View: text only (customer: ✓ / –). Edit: the inputs, the "Dùng" switch, "Theo chung" / "Xoá".
  Widget _rowCard(BuildContext context, EditorRow r) {
    final own = _isCustomer && _m.hasOwn(r);
    final scheme = Theme.of(context).colorScheme;
    final tag = _m.tag(r);
    final notSet = _m.notSet(r);
    final k = '${_m.version}-${r.type}';
    final warn = TextStyle(color: context.badColor, fontWeight: FontWeight.w600);
    Widget value(String label, String text, {bool bad = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
            Text(r.off ? '-' : text, style: bad ? warn : const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (bad && !r.off) Text('Chưa nhập', style: TextStyle(fontSize: 11.5, color: context.badColor)),
          ]),
        );
    return Card(
      key: ValueKey('row-$k'),
      margin: const EdgeInsets.only(bottom: 8),
      color: r.off ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (_isCustomer && _editing)
              Switch(key: ValueKey('use-$k'), value: !r.off, onChanged: (_) => setState(() => _m.toggleOff(r)))
            else if (_isCustomer)
              Padding(padding: const EdgeInsets.only(right: 10, top: 8, bottom: 8), child: Text(r.off ? '–' : '✓', style: const TextStyle(fontSize: 16))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (_editing && r.extra)
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        key: ValueKey('name-$k'),
                        initialValue: r.name,
                        maxLength: 30,
                        decoration: const InputDecoration(labelText: 'Tên', isDense: true, counterText: ''),
                        onChanged: (v) => r.name = v,
                      ),
                    )
                  else
                    Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (tag.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(color: (own ? scheme.primary : scheme.outline).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                      child: Text(tag, style: TextStyle(fontSize: 12, color: own ? scheme.primary : context.mutedColor)),
                    ),
                ]),
                if (!(_editing && r.editable && !r.off) && r.symbolText.isNotEmpty) Text(r.symbolText, style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Lấy số: ${_m.srcCaption(r)}', key: ValueKey('src-$k'), style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
                  if (_editing && !r.off)
                    TextButton(
                      key: ValueKey('srcbtn-$k'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 28)),
                      onPressed: () => setState(() => r.srcOpen = !r.srcOpen),
                      child: Text(r.srcOpen ? 'Đóng' : 'Chỉnh lấy số', style: const TextStyle(fontSize: 12)),
                    ),
                ]),
              ]),
            ),
            if (_editing && own) AppButton(label: 'Theo chung', variant: AppButtonVariant.ghost, onPressed: () => setState(() => _m.resetRow(r))),
            if (_editing && (r.extra || !_isCustomer)) TextButton(style: TextButton.styleFrom(foregroundColor: context.badColor), onPressed: () => _remove(r), child: const Text('Xoá')),
          ]),
          if (_editing && r.editable && !r.off)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: TextFormField(
                key: ValueKey('sym-$k'),
                initialValue: r.symbolsInput,
                decoration: const InputDecoration(labelText: 'Ký hiệu', hintText: 'Cách nhau bằng dấu phẩy', isDense: true),
                onChanged: (v) => setState(() => r.symbolsInput = v),
              ),
            ),
          if (_editing && r.srcOpen && !r.off) _srcPanel(context, r, k),
          const SizedBox(height: 6),
          if (!_editing)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              value('Giá tiền / 1 điểm', _fmt(r.price)),
              value('Giá trúng / 1 điểm', _fmt(r.payout), bad: notSet),
            ])
          else if (!r.off)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('price-$k'),
                  initialValue: r.price,
                  keyboardType: kNumbersKeyboard,
                  decoration: const InputDecoration(labelText: 'Giá tiền / 1 điểm', isDense: true),
                  onChanged: (v) => setState(() => r.price = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('payout-$k'),
                  initialValue: r.payout,
                  keyboardType: kNumbersKeyboard,
                  decoration: InputDecoration(labelText: 'Giá trúng / 1 điểm', isDense: true, errorText: notSet ? 'Chưa nhập' : null),
                  onChanged: (v) => setState(() => r.payout = v),
                ),
              ),
            ]),
        ]),
      ),
    );
  }

  /// "Chỉnh lấy số": which prizes, đầu / cuối, how many digits, which lô of each prize.
  Widget _srcPanel(BuildContext context, EditorRow r, String k) {
    final f = _m.fieldsOf(r);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (f.tiers) ...[
          const Text('Giải (dãy giải lấy số)', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 6, runSpacing: 0, children: [
            for (final p in prizeInfo(_m.region))
              FilterChip(
                key: ValueKey('tier-$k-${p.tier}'),
                label: Text('${p.label} (${p.count} lô × ${p.digits} số)', style: const TextStyle(fontSize: 12)),
                selected: r.srcTiers.contains(p.tier),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _m.toggleTier(r, p.tier)),
              ),
          ]),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.end, children: [
          if (f.position)
            SizedBox(
              width: 150,
              child: AppDropdown<String>(
                key: ValueKey('pos-$k'),
                initialValue: r.srcPos,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vị trí', isDense: true),
                items: const [DropdownMenuItem(value: 'last', child: Text('Cuối (đuôi)')), DropdownMenuItem(value: 'first', child: Text('Đầu'))],
                onChanged: (v) => setState(() => r.srcPos = v ?? 'last'),
              ),
            ),
          if (f.digits)
            SizedBox(
              width: 120,
              child: AppDropdown<int>(
                key: ValueKey('dig-$k'),
                initialValue: r.srcDigits,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bao nhiêu số', isDense: true),
                items: [for (var n = 1; n <= 6; n++) DropdownMenuItem(value: n, child: Text('$n số'))],
                onChanged: (v) => setState(() => r.srcDigits = v ?? 2),
              ),
            ),
          if (f.pick)
            SizedBox(
              width: 170,
              child: TextFormField(
                key: ValueKey('pick-$k'),
                initialValue: r.srcPick,
                decoration: const InputDecoration(labelText: 'Lô thứ (trống = mọi lô)', hintText: 'Ví dụ: 1, 2', isDense: true),
                onChanged: (v) => setState(() => r.srcPick = v),
              ),
            ),
          AppButton(key: ValueKey('srcreset-$k'), label: 'Về mặc định', variant: AppButtonVariant.ghost, onPressed: () => setState(() {
              _m.resetSrc(r);
              _m.version++; // new keys: the inputs are rebuilt with the default values
            })),
        ]),
        const SizedBox(height: 4),
        Text('Đang lấy: ${describeSource(_m.srcOf(r), _m.region)}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
      ]),
    );
  }
}
