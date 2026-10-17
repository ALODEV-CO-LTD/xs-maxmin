// Tính toán từ tin nhắn (web: ChatCalcDialog.vue): Chọn đài > Kết quả tính toán > Lưu / Copy / Gửi cho khách.
//   Chọn đài  một thẻ cho mỗi đài quay trong ngày; không tự chọn.
//   Kết quả   tính bằng kết quả ĐÚNG đài + ngày của tài khoản (bản đã lưu trên máy, chạy được offline); chưa có thì báo và cho
//             thử lại, tuyệt đối không dùng số mẫu hay đài khác.
//   Lưu       trên máy này (`report:<id>` + `reports:index`); id theo nội dung nên không trùng bản ghi.
//   Gửi       xem trước rồi gửi đúng nội dung báo cáo cho người bạn qua chat mã hoá 2 đầu.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import '../entries/message_parser.dart';
import '../scoring/entry_model.dart';
import '../scoring/scoring_logic.dart' show LotteryResult;
import 'chat_calc_services.dart';
import 'chat_report.dart';
import '../../core/widgets/app_button.dart';

enum _Step { station, report, saved }

class ChatCalcScreen extends StatefulWidget {
  const ChatCalcScreen({super.key, required this.services, required this.text, required this.date, required this.customerId, required this.friendId, required this.friendName});
  final ChatCalcServices services;

  /// Các dòng đã đối chiếu.
  final String text;
  final String date;
  final String customerId;
  final String friendId;
  final String friendName;

  @override
  State<ChatCalcScreen> createState() => _ChatCalcScreenState();
}

class _ChatCalcScreenState extends State<ChatCalcScreen> {
  _Step _step = _Step.station;
  String _selected = '';
  bool _loading = true;
  bool _busy = false;
  String _error = '';
  String _notice = '';
  ChatReport? _rep;
  CustomerRec? _customer;
  RatesMap _rates = {};
  List<Map<String, dynamic>> _saved = [];
  bool _sending = false;

  ChatCalcServices get svc => widget.services;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await svc.data.loadStations();
    } catch (_) {/* chỉ Miền Bắc */}
    try {
      _rates = await svc.data.accountRates();
    } catch (_) {/* mặc định */}
    try {
      _customer = (await svc.data.customers()).where((c) => c.id == widget.customerId).firstOrNull;
    } catch (_) {/* dùng cấu hình mặc định */}
    _saved = decodeIndex(await svc.meta.get('reports:index'));
    if (mounted) setState(() => _loading = false);
  }

  List<String> get _stationIds => ['mb', ...svc.stations.stationsOn('mt', widget.date), ...svc.stations.stationsOn('mn', widget.date)];
  String _nameFor(String id) => id == 'mb' ? 'Miền Bắc' : svc.stations.stationName(id);
  String _regionOf(String id) => svc.stations.loaded ? svc.stations.regionOf(id).id : defaultRegionOf(id);

  Future<void> _confirmStation() async {
    if (_selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      LotteryResult? result;
      try {
        result = await svc.data.result(widget.date, _selected);
      } catch (e) {
        setState(() => _error = 'Không lấy được kết quả xổ số');
        return;
      }
      final own = _customer?.scoringRates;
      final region = _regionOf(_selected);
      final types = typesOf(_rates);
      final parsed = parseMessage(widget.text, betTypes: types.isNotEmpty ? types : const ['de', 'lo'], kindSymbols: kindSymbolsFor(_rates, own, region));
      if (parsed.rows.isEmpty) {
        setState(() => _error = 'Không tìm thấy số liệu hợp lệ trong các tin đã chọn.');
        return;
      }
      final rep = buildReport(
        rows: [for (final r in parsed.rows) ReportRow(type: r.type, value: r.value, score: r.score, uncertain: r.uncertain)],
        result: result,
        station: _selected,
        stationName: _nameFor(_selected),
        date: widget.date,
        accountRates: _rates,
        customerRates: own,
        customerRegion: _customer?.homeRegion,
        regionOf: _regionOf,
      );
      setState(() {
        _rep = rep;
        _step = _Step.report;
        _notice = '';
        if (rep.missingResult) _error = 'Chưa có kết quả đài ${_nameFor(_selected)} ngày ${viDate(widget.date)}. Hãy lưu kết quả ở tab Kết quả rồi bấm Thử lại.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _text => _rep == null ? '' : reportText(_rep!);

  Future<void> _save() async {
    final rep = _rep!;
    setState(() => _notice = '');
    try {
      final id = reportId(rep, widget.text.split('\n'));
      final index = decodeIndex(await svc.meta.get('reports:index'));
      if (index.any((x) => x['id'] == id) && !rep.missingResult) {
        final old = await svc.meta.get('report:$id');
        if (old != null && (jsonDecode(old) as Map)['text'] == _text) {
          if (mounted) setState(() => _notice = 'Báo cáo này đã được lưu.');
          return;
        }
      }
      final savedAt = DateTime.now().toIso8601String();
      await svc.meta.set('report:$id', jsonEncode({'id': id, 'rep': rep.toJson(), 'source': widget.text, 'text': _text, 'savedAt': savedAt}));
      final entry = {'id': id, 'savedAt': savedAt, 'date': rep.date, 'stationName': rep.stationName, 'profit': rep.totals.profit};
      final next = [entry, ...index.where((x) => x['id'] != id)].take(200).toList();
      await svc.meta.set('reports:index', jsonEncode(next));
      if (mounted) {
        setState(() {
          _saved = next;
          _notice = 'Đã lưu báo cáo.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Không lưu được báo cáo.');
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _text));
      if (mounted) setState(() => _notice = 'Đã sao chép báo cáo');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Không sao chép được, hãy thử lại.');
    }
  }

  Future<void> _openSaved(Map<String, dynamic> s) async {
    final raw = await svc.meta.get('report:${s['id']}');
    if (raw == null || !mounted) return;
    final j = jsonDecode(raw) as Map;
    final at = DateTime.tryParse('${j['savedAt']}')?.toLocal();
    setState(() {
      _rep = ChatReport.fromJson(Map<String, dynamic>.from(j['rep'] as Map));
      _error = '';
      _notice = 'Báo cáo đã lưu lúc ${at == null ? '' : '${viDate(isoOf(at))} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'}.';
      _step = _Step.report;
    });
  }

  Future<void> _send() async {
    final sender = svc.sender;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gửi cho ${widget.friendName}'),
        content: SingleChildScrollView(child: Text(_text)),
        actions: [
          AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Gửi', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (sender == null) {
      setState(() => _notice = 'Mã hoá 2 đầu chưa sẵn sàng trên thiết bị này, chưa gửi được.');
      return;
    }
    setState(() {
      _sending = true;
      _notice = '';
    });
    final r = await sender.send(widget.friendId, _text);
    if (mounted) {
      setState(() {
        _sending = false;
        _notice = r.message;
      });
    }
  }

  void _back() {
    if (_step == _Step.station) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step = _Step.station);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) { _Step.station => 'Chọn đài tính toán', _Step.saved => 'Báo cáo đã lưu', _Step.report => 'Kết quả tính toán' };
    return PopScope(
      canPop: _step == _Step.station,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title), leading: BackButton(onPressed: _back)),
        body: _loading ? const Center(child: CircularProgressIndicator()) : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_step) {
      case _Step.station:
        return _stationStep(context);
      case _Step.saved:
        return _savedStep(context);
      case _Step.report:
        return _rep == null ? const SizedBox.shrink() : _reportStep(context, _rep!);
    }
  }

  Widget _stationStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Text('Ngày ${viDate(widget.date)}. Chọn đài có kết quả dùng để tính (tin nhắn và nội dung giải mã được giữ nguyên).', style: TextStyle(fontSize: 13.5, color: context.mutedColor)),
      const SizedBox(height: 10),
      Text('Khách hàng: ${_customer?.name ?? '(chưa chọn)'}', style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(_customer?.scoringRates != null ? 'Tính theo cấu hình giá riêng của khách này.' : 'Tính theo cấu hình giá mặc định.', style: TextStyle(fontSize: 13, color: context.mutedColor)),
      const SizedBox(height: 12),
      for (final id in _stationIds)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            key: ValueKey('station-card-$id'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _selected = id),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _selected == id ? cs.primaryContainer.withValues(alpha: 0.4) : null,
                border: Border.all(color: _selected == id ? cs.primary : cs.outlineVariant, width: _selected == id ? 2 : 1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(Icons.grid_view_rounded, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Dùng kết quả ${id == 'mb' ? 'Miền Bắc' : 'đài ${_nameFor(id)}'}', style: const TextStyle(fontSize: 16))),
                if (_selected == id) Icon(Icons.check_circle, color: cs.primary),
              ]),
            ),
          ),
        ),
      if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error, style: TextStyle(color: context.badColor))),
      AppButton(label: 'Xác nhận chọn đài', variant: AppButtonVariant.primary, loading: _busy, onPressed: _selected.isEmpty || _busy ? null : _confirmStation),
      const SizedBox(height: 4),
      AppButton(label: 'Báo cáo đã lưu (${_saved.length})', variant: AppButtonVariant.ghost, onPressed: () => setState(() => _step = _Step.saved)),
    ]);
  }

  Widget _savedStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_saved.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có báo cáo nào được lưu.', style: TextStyle(color: context.mutedColor)));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final s in _saved)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openSaved(s),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Đài ${s['stationName']} · ${viDate('${s['date']}')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Lợi nhuận: ${fmtProfit((s['profit'] as num?)?.toDouble())}', style: TextStyle(fontSize: 13, color: context.mutedColor)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _reportStep(BuildContext context, ChatReport rep) {
    final cs = Theme.of(context).colorScheme;
    final neg = rep.totals.profit != null && rep.totals.profit! < 0;
    Widget card(String n, List<Widget> children, {Color? border, Color? fill, bool other = false}) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: fill ?? (other ? cs.surfaceContainerHighest : null), border: Border.all(color: border ?? cs.outlineVariant, width: border == null ? 1 : 2), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary)), child: Text(n, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.primary))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
          ]),
        );
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), children: [
          Text('Đài ${rep.stationName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text('Ngày ${viDate(rep.date)}', style: TextStyle(color: context.mutedColor)),
          const SizedBox(height: 8),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_error, style: TextStyle(color: context.badColor)),
                if (rep.missingResult) AppButton(label: 'Thử lại', variant: AppButtonVariant.ghost, onPressed: _busy ? null : _confirmStation),
              ]),
            ),
          for (var i = 0; i < rep.groups.length; i++)
            card('${i + 1}', [
              for (final (j, l) in groupLines(rep.groups[i], rep.missingResult).indexed) Text(l, style: TextStyle(fontWeight: j == 0 ? FontWeight.w700 : FontWeight.w400)),
            ]),
          if (rep.other.stake != 0)
            card('+', [Text('Kiểu đánh khác (${rep.other.kinds.join(', ')}): đánh ${money(rep.other.stakeMoney)}${rep.missingResult ? '' : ', trúng ${money(rep.other.winMoney)}'} (đã tính vào tổng)')], other: true),
          card('6', [Text('Tổng tiền khách đánh: ${money(rep.totals.stake)}', style: const TextStyle(fontWeight: FontWeight.w700))]),
          card('7', [Text('Tổng tiền khách trúng: ${rep.missingResult ? 'Chưa đủ dữ liệu' : money(rep.totals.won)}', style: const TextStyle(fontWeight: FontWeight.w700))]),
          card('8', [Text('Tổng lợi nhuận: ${fmtProfit(rep.totals.profit)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: neg ? context.badColor : null))], border: neg ? context.badColor : cs.primary, fill: neg ? context.badColor.withValues(alpha: 0.08) : cs.primaryContainer.withValues(alpha: 0.3)),
          if (rep.skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${rep.skipped.length} dòng cần kiểm tra chưa được tính: ${rep.skipped.map((r) => r.value).join(', ')}. Sửa ở màn đối chiếu rồi tính lại.', style: const TextStyle(color: Color(0xFFB45309), fontSize: 13.5)),
            ),
          if (_notice.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_notice, style: TextStyle(color: context.okColor, fontSize: 13.5))),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(child: AppButton(label: 'Lưu', variant: AppButtonVariant.secondary, icon: Icons.save_outlined, onPressed: _save)),
            const SizedBox(width: 8),
            Expanded(child: AppButton(label: 'Copy', variant: AppButtonVariant.secondary, icon: Icons.copy, onPressed: _copy)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: AppButton(label: 'Gửi cho khách', variant: AppButtonVariant.primary, icon: Icons.send, loading: _sending, onPressed: _sending ? null : _send)),
          ]),
        ),
      ),
    ]);
  }
}
