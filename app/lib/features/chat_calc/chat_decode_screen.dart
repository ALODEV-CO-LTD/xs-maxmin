// Màn Đối chiếu tin nhắn (web: ChatDecodeDialog.vue): tin gốc (chỉ đọc) và bản giải mã từng dòng (sửa được), theo bố cục dọc.
// Tin gốc không bao giờ bị đổi; bản đã sửa lưu riêng trên máy này (`decode:<id>`), mở lại vẫn còn.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import '../calc/calc_screen.dart';
import '../entries/dialogs.dart';
import '../scoring/date_field.dart';
import '../scoring/entry_model.dart';
import 'chat_calc_screen.dart';
import 'chat_calc_services.dart';
import 'chat_decode_model.dart';
import 'chat_prefill.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dropdown.dart';

const chatCalcRouteName = 'chat_calc';

class ChatDecodeScreen extends StatefulWidget {
  const ChatDecodeScreen({super.key, this.services, required this.friendId, required this.friendName, required this.messages, this.calcFirst = false, this.initialDate});
  final ChatCalcServices? services;
  final String friendId;
  final String friendName;
  final List<DecodeSource> messages;

  /// Mở từ "Tính toán": tiêu đề và nút chính là Tính toán.
  final bool calcFirst;

  /// Ngày ban đầu (mặc định: hôm nay).
  final String? initialDate;

  @override
  State<ChatDecodeScreen> createState() => _ChatDecodeScreenState();
}

class _ChatDecodeScreenState extends State<ChatDecodeScreen> {
  ChatCalcServices? _svc;
  List<CustomerRec> _customers = [];
  String _customerId = '';
  bool _needCustomer = false;
  late String _date = widget.initialDate ?? todayIso();
  String _station = 'mb';
  List<DecodeItem> _items = [];
  final Map<DecodeLine, TextEditingController> _ctl = {};
  DecodeFn _decode = decoderFor(betTypes: const ['de', 'lo']);
  bool _loading = true;
  String _note = '';

  ChatCalcServices get svc => _svc!;
  CustomerRec? get _customer => _customers.where((c) => c.id == _customerId).firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_svc != null) return;
    _svc = widget.services ?? ChatCalcServices.of(context);
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    RatesMap rates = {};
    try {
      rates = await svc.data.accountRates();
    } catch (_) {/* giải mã với loại mặc định */}
    final types = typesOf(rates);
    _decode = decoderFor(betTypes: types.isNotEmpty ? types : const ['de', 'lo'], kindSymbols: kindSymbolsFor(rates, null, 'mb'));
    try {
      _customers = await svc.data.customers();
    } catch (_) {
      _customers = [];
    }
    unawaited(svc.data.loadStations().then((_) => mounted ? setState(() {}) : null));
    final items = await buildDecodeItems(widget.messages, _decode, (id) => svc.meta.get('decode:$id'));
    if (!mounted) return;
    setState(() {
      _items = items;
      _bind();
      _loading = false;
    });
  }

  void _bind() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl.clear();
    for (final it in _items) {
      for (final l in it.lines) {
        _ctl[l] = TextEditingController(text: l.text);
      }
    }
  }

  void _sync(DecodeLine l) => _ctl[l]?.text = l.text;

  void _restore(DecodeLine l) => setState(() {
        restoreLine(l);
        _sync(l);
      });

  Future<void> _redo() async {
    if (anyEdited(_items) && !await confirmDialog(context, title: 'Giải mã lại', message: 'Giải mã lại sẽ bỏ mọi chỗ bạn đã sửa (chưa lưu). Tiếp tục?', confirmText: 'Giải mã lại')) return;
    setState(() {
      redecode(_items, _decode);
      for (final it in _items) {
        it.lines.forEach(_sync);
      }
      _note = 'Đã giải mã lại, các chỗ sửa đã bỏ (chưa lưu).';
    });
  }

  Future<void> _save() async {
    for (final it in _items) {
      await svc.meta.set('decode:${it.id}', it.savedJson());
    }
    if (mounted) setState(() => _note = 'Đã lưu bản sửa trên máy này. Tin nhắn gốc không bị đổi.');
  }

  bool _requireCustomer() {
    if (_customerId.isNotEmpty) return true;
    setState(() => _needCustomer = true);
    return false;
  }

  Future<void> _calc() async {
    if (!_requireCustomer()) return;
    await _save();
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      settings: const RouteSettings(name: chatCalcRouteName),
      builder: (_) => ChatCalcScreen(
        services: svc,
        text: joinedText(_items),
        date: _date,
        customerId: _customerId,
        friendId: widget.friendId,
        friendName: widget.friendName,
      ),
    ));
  }

  void _use() {
    if (!_requireCustomer()) return;
    ChatPrefillHub.instance.offer(ChatPrefill(text: joinedText(_items), customer: _customer?.name ?? '', date: _date, station: _station));
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    router?.go(calcLocation('entries'));
  }

  @override
  Widget build(BuildContext context) {
    final stations = svc.stations;
    final options = stations.stationOptions(_date);
    final stationValue = options.any((o) => o.value == _station) ? _station : 'mb';
    final hint = _dayHint(stationValue);
    return Scaffold(
      appBar: AppBar(title: Text(widget.calcFirst ? 'Tính toán từ tin nhắn' : 'Đối chiếu tin nhắn')),
      bottomNavigationBar: _loading ? null : _actionBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
              Text('Mỗi tin có bản gốc (giữ nguyên) và nội dung giải mã bên dưới. Sửa từng dòng nếu giải mã chưa đúng; dòng có dấu ! cần kiểm tra.', style: TextStyle(fontSize: 13.5, color: context.mutedColor)),
              const SizedBox(height: 12),
              AppDropdown<String>(
                key: ValueKey('customer-$_customerId-${_customers.length}'),
                initialValue: _customerId.isEmpty ? null : _customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Khách hàng của số liệu này *'),
                hint: const Text('Chọn khách hàng...'),
                items: [for (final c in _customers) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() {
                  _customerId = v ?? '';
                  _needCustomer = false;
                }),
              ),
              if (_needCustomer) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Hãy chọn khách hàng cho số liệu đã nhập trước khi tiếp tục.', style: TextStyle(color: context.badColor, fontWeight: FontWeight.w600))),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 4,
                  child: DateField(
                    label: 'Ngày',
                    value: _date,
                    onChanged: (v) => setState(() {
                      if (v.isNotEmpty) _date = v;
                      if (!stations.stationOptions(_date).any((o) => o.value == _station)) _station = 'mb';
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: AppDropdown<String>(
                    key: ValueKey('station-$_date-${stations.loaded}'),
                    initialValue: stationValue,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Đài'),
                    items: [for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label.trim(), overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _station = v ?? 'mb'),
                  ),
                ),
              ]),
              if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hint, style: TextStyle(fontSize: 13.5, color: context.mutedColor))),
              const SizedBox(height: 12),
              for (var n = 0; n < _items.length; n++) _itemCard(context, n, _items[n]),
              if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_note, style: TextStyle(color: context.okColor, fontSize: 13.5))),
            ]),
    );
  }

  // Luôn thấy các nút ở cuối màn hình, không phải cuộn hết các tin mới bấm được.
  Widget _actionBar(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: AppButton(label: 'Giải mã lại', variant: AppButtonVariant.ghost, onPressed: _redo)),
              Expanded(child: AppButton(label: 'Lưu bản sửa', variant: AppButtonVariant.ghost, onPressed: _save)),
            ]),
            Row(children: [
              Expanded(
                child: widget.calcFirst ? AppButton(label: 'Dùng cho Nhập số', variant: AppButtonVariant.secondary, onPressed: _use) : AppButton(label: 'Dùng cho Nhập số', variant: AppButtonVariant.secondary, onPressed: _use),
              ),
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: 'Tính toán', variant: AppButtonVariant.primary, onPressed: _calc)),
            ]),
          ]),
        ),
      );

  String _dayHint(String code) {
    if (code == 'mb') return '';
    final st = svc.stations;
    final region = st.isRegionCode(code) ? code : st.regionOf(code).id;
    final list = st.stationsOn(region, _date);
    return list.length > 1 ? 'Ngày này ${st.regionOf(region).name} quay ${list.length} đài: ${list.map(st.stationName).join(', ')}. Chọn một đài hoặc cả vùng.' : '';
  }

  Widget _itemCard(BuildContext context, int n, DecodeItem it) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Tin ${n + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (var i = 0; i < it.lines.length; i++) _lineTile(context, i, it.lines[i]),
      ]),
    );
  }

  Widget _lineTile(BuildContext context, int i, DecodeLine l) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Tin gốc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.mutedColor)),
        Container(
          margin: const EdgeInsets.only(top: 2, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Text(l.original.isEmpty ? ' ' : l.original),
        ),
        Text('Giải mã (sửa được)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.mutedColor)),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(
            child: TextField(
              key: ValueKey('decoded-$i-${l.original}'),
              controller: _ctl[l],
              onChanged: (v) => setState(() => l.text = v),
              decoration: InputDecoration(isDense: true, hintText: l.original.isEmpty ? '' : null, fillColor: l.edited ? cs.primaryContainer.withValues(alpha: 0.35) : null),
            ),
          ),
          if (l.unknown) const Padding(padding: EdgeInsets.only(left: 8), child: Tooltip(message: 'Có phần chưa nhận ra, hãy kiểm tra', child: Text('!', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w800, fontSize: 18)))),
          if (l.edited) AppButton(label: 'Khôi phục', variant: AppButtonVariant.ghost, onPressed: () => _restore(l)),
        ]),
      ]),
    );
  }
}
