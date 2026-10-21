import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/mask_store.dart';
import '../../core/scoring_config_bus.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/masked_text.dart';
import '../entries/dialogs.dart';
import 'add_customer_dialog.dart';
import 'customer_config_screen.dart';
import 'customer_model.dart';
import 'customers_controller.dart';
import '../../core/widgets/app_button.dart';

/// Khách hàng: the customer roster with totals from the entries, add / edit phone / delete, and the scoring configs.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CustomersController>(
      create: (c) => CustomersController(api: c.read<ApiClient>(), auth: c.read<AuthStore>(), stations: c.read<LotteryStations>())..load(),
      child: const _CustomersBody(),
    );
  }
}

class _CustomersBody extends StatefulWidget {
  const _CustomersBody();
  @override
  State<_CustomersBody> createState() => _CustomersBodyState();
}

class _CustomersBodyState extends State<_CustomersBody> {
  String _message = '';
  String? _busyId;
  ScoringConfigBus? _bus;

  @override
  void initState() {
    super.initState();
    // The default config is edited in the Cấu hình tab: take the saved one.
    _bus = Provider.of<ScoringConfigBus?>(context, listen: false)?..addListener(_onConfigSaved);
  }

  void _onConfigSaved() {
    final rates = _bus?.rates;
    if (rates == null || !mounted) return;
    final c = context.read<CustomersController>();
    c.accountRates = rates;
    c.invalidate();
  }

  @override
  void dispose() {
    _bus?.removeListener(_onConfigSaved);
    super.dispose();
  }

  Future<void> _add(CustomersController c) async {
    final created = await showAddCustomerDialog(context);
    if (created != null) c.addLocal(created);
  }

  Future<void> _editPhone(CustomersController c, Customer cu) =>
      showDialog<void>(context: context, builder: (_) => _EditPhoneDialog(controller: c, customer: cu));

  Future<void> _remove(CustomersController c, Customer cu) async {
    final ok = await confirmDialog(context, title: 'Xoá khách hàng', message: 'Xoá "${cu.name}" khỏi danh sách khách hàng? Số liệu đã nhập của khách này vẫn được giữ nguyên.', confirmText: 'Xoá', danger: true);
    if (!ok || !mounted) return;
    setState(() => _busyId = cu.id);
    final err = await c.remove(cu);
    if (mounted) {
      setState(() {
        _busyId = null;
        _message = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CustomersController>();
    final mask = context.watch<MaskStore>();
    final list = c.shown;
    return Listener(
      onPointerDown: (_) => mask.touch(),
      child: RefreshIndicator(
        onRefresh: c.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Tiền vào/ra tính theo bảng giá của từng khách; lợi nhuận chỉ tính các ngày đã có kết quả xổ số.', style: TextStyle(fontSize: 13, color: context.mutedColor)),
            const SizedBox(height: 10),
            if (c.fromCache) const InfoBox('Đang offline: hiển thị số liệu đã lưu trên máy. Thêm/xoá khách hàng cần có mạng.', kind: InfoKind.warning),
            if (c.loading)
              const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))
            else if (c.error.isNotEmpty && c.roster.isEmpty && c.entries.isEmpty) ...[
              InfoBox(c.error),
              AppButton(label: 'Thử lại', variant: AppButtonVariant.primary, onPressed: c.load),
            ] else ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                AppButton(label: 'Thêm khách hàng', variant: AppButtonVariant.primary, icon: Icons.add, onPressed: () => _add(c)),
              ]),
              const SizedBox(height: 10),
              TextField(decoration: const InputDecoration(hintText: 'Tìm theo tên khách hàng...', prefixIcon: Icon(Icons.search)), onChanged: c.setQuery),
              const SizedBox(height: 8),
              _filters(c),
              const SizedBox(height: 10),
              if (_message.isNotEmpty) InfoBox(_message, onClose: () => setState(() => _message = '')),
              if (c.summaries.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Chưa có khách hàng nào. Bấm "Thêm khách hàng" để bắt đầu.')))
              else if (list.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Không tìm thấy khách hàng phù hợp.')))
              else
                for (final s in list) _tile(context, c, s),
            ],
          ],
        ),
      ),
    );
  }

  /// Một nút "Bộ lọc" (kèm số mục đang áp dụng); bấm thì mở bảng chọn lọc và sắp xếp.
  Widget _filters(CustomersController c) {
    final n = c.activeCount;
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.tune, size: 18),
        label: Text(n == 0 ? 'Bộ lọc' : 'Bộ lọc ($n)'),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => ChangeNotifierProvider<CustomersController>.value(value: c, child: const _FilterSheet()),
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onPressed, {Color? color}) => IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        icon: Icon(icon, size: 21, color: color),
        onPressed: onPressed,
      );

  Widget _tile(BuildContext context, CustomersController c, CustomerSummary s) {
    final cu = s.customer;
    Widget stat(String label, String value, Color? color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: context.mutedColor)),
            MaskedText(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                if (s.phone.isNotEmpty) Text(s.phone, style: TextStyle(fontSize: 13, color: context.mutedColor)),
                if (cu == null) Text('Chưa thêm vào danh sách', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
                if (cu != null && cu.pending) Text('Chờ đồng bộ (đã lưu trên máy, sẽ tạo khi có mạng)', style: TextStyle(fontSize: 12.5, color: Brand.warning)),
              ]),
            ),
            // The actions as icons (the label is the tooltip): edit, scoring config (filled when this customer has its own), remove.
            if (cu != null) ...[
              _iconAction(Icons.edit_outlined, 'Sửa', () => _editPhone(c, cu)),
              _iconAction(
                cu.scoringRates != null ? Icons.tune : Icons.tune_outlined,
                cu.scoringRates != null ? 'Cấu hình tính điểm (riêng)' : 'Cấu hình tính điểm',
                () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerConfigScreen(controller: c, customer: cu))),
                color: cu.scoringRates != null ? Theme.of(context).colorScheme.primary : null,
              ),
              _busyId == cu.id
                  ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : _iconAction(Icons.delete_outline, 'Xoá khỏi danh sách', () => _remove(c, cu), color: context.badColor),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            stat('Tiền vào', c.moneyReady ? formatNumber(s.sent) : '...', context.okColor),
            stat('Tiền ra', c.moneyReady ? formatNumber(s.won) : '...', context.badColor),
            stat('Lợi nhuận', c.moneyReady ? formatNumber(s.profit) : '...', s.profit >= 0 ? context.okColor : context.badColor),
          ]),
        ]),
      ),
    );
  }
}

/// "Sửa" a customer: the phone number. A widget of its own so the text controller lives (and is disposed) with the dialog,
/// not right after showDialog returns while the dialog is still animating out.
class _EditPhoneDialog extends StatefulWidget {
  const _EditPhoneDialog({required this.controller, required this.customer});
  final CustomersController controller;
  final Customer customer;
  @override
  State<_EditPhoneDialog> createState() => _EditPhoneDialogState();
}

class _EditPhoneDialogState extends State<_EditPhoneDialog> {
  late final TextEditingController _phone = TextEditingController(text: widget.customer.phone);
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final err = await widget.controller.savePhone(widget.customer, _phone.text);
    if (!mounted) return;
    if (err.isEmpty) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Sửa ${widget.customer.name}',
      closeEnabled: !_busy,
      body: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _phone, autofocus: true, enabled: !_busy, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại', hintText: 'Chưa có')),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBox(_error)),
      ]),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        AppButton(label: 'Lưu', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _save),
      ],
    );
  }
}

/// Bảng "Bộ lọc": lọc theo kết quả và miền, sắp xếp theo tiền vào / tiền ra / lợi nhuận / tên. Áp dụng ngay khi chọn.
class _FilterSheet extends StatelessWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CustomersController>();
    Widget group(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: chips),
          ]),
        );
    Widget chip(String label, bool on, VoidCallback onTap) => ChoiceChip(label: Text(label), selected: on, showCheckmark: false, onSelected: (_) => onTap());
    const results = {
      CustomerResultFilter.profit: 'Lãi',
      CustomerResultFilter.loss: 'Lỗ',
      CustomerResultFilter.noData: 'Chưa có số liệu',
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          group('Sắp xếp', [for (final s in CustomerSort.values) chip(s.label, c.sort == s, () => c.setSort(s))]),
          group('Kết quả', [
            for (final e in results.entries) chip(e.value, c.resultFilter == e.key, () => c.setResultFilter(c.resultFilter == e.key ? null : e.key)),
          ]),
          group('Miền của khách', [
            chip('Miền Bắc', c.regionFilter == 'mb', () => c.setRegionFilter(c.regionFilter == 'mb' ? null : 'mb')),
            chip('Nam/Trung', c.regionFilter == 'mn', () => c.setRegionFilter(c.regionFilter == 'mn' ? null : 'mn')),
          ]),
          Row(children: [
            AppButton(label: 'Đặt lại', variant: AppButtonVariant.ghost, onPressed: c.activeCount == 0 ? null : c.clearFilters),
            const Spacer(),
            AppButton(label: 'Xong', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(context)),
          ]),
        ]),
      ),
    );
  }
}
