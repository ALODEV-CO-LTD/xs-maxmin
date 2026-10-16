import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/format.dart';
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

/// Khách hàng: the customer roster with totals from the entries, add / edit phone / delete, and the scoring configs.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CustomersController>(
      create: (c) => CustomersController(api: c.read<ApiClient>(), auth: c.read<AuthStore>())..load(),
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

  Future<void> _editPhone(CustomersController c, Customer cu) async {
    final ctrl = TextEditingController(text: cu.phone);
    String error = '';
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AppDialog(
          title: 'Sửa ${cu.name}',
          closeEnabled: !busy,
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, autofocus: true, enabled: !busy, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại', hintText: 'Chưa có')),
            if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBox(error)),
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Huỷ')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setS(() {
                        busy = true;
                        error = '';
                      });
                      final err = await c.savePhone(cu, ctrl.text);
                      if (err.isEmpty) {
                        if (ctx.mounted) Navigator.pop(ctx);
                      } else {
                        setS(() {
                          busy = false;
                          error = err;
                        });
                      }
                    },
              child: Text(busy ? 'Đang lưu...' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

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
            Text('Số liệu vào/ra được tổng hợp từ các lượt nhập.', style: TextStyle(fontSize: 13, color: context.mutedColor)),
            const SizedBox(height: 10),
            if (c.fromCache) const InfoBox('Đang offline: hiển thị số liệu đã lưu trên máy. Thêm/xoá khách hàng cần có mạng.', kind: InfoKind.warning),
            if (c.loading)
              const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))
            else if (c.error.isNotEmpty && c.roster.isEmpty && c.entries.isEmpty) ...[
              InfoBox(c.error),
              FilledButton(onPressed: c.load, child: const Text('Thử lại')),
            ] else ...[
              const Align(alignment: Alignment.centerLeft, child: MaskBar()),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: () => _add(c), icon: const Icon(Icons.add), label: const Text('Thêm khách hàng')),
              ]),
              const SizedBox(height: 10),
              TextField(decoration: const InputDecoration(hintText: 'Tìm theo tên khách hàng...', prefixIcon: Icon(Icons.search)), onChanged: c.setQuery),
              const SizedBox(height: 10),
              if (_message.isNotEmpty) InfoBox(_message, onClose: () => setState(() => _message = '')),
              if (c.summaries.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Chưa có khách hàng nào. Bấm "Thêm khách hàng" để bắt đầu.')))
              else if (list.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Không tìm thấy khách hàng phù hợp.')))
              else
                for (var i = 0; i < list.length; i++) _tile(context, c, list[i], i + 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, CustomersController c, CustomerSummary s, int stt) {
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
            Container(
              width: 28,
              alignment: Alignment.center,
              child: Text('$stt', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            if (s.phone.isNotEmpty) Text(s.phone, style: TextStyle(color: context.mutedColor)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            stat('Điểm vào', formatNumber(s.vao), context.okColor),
            stat('Điểm ra', formatNumber(s.ra), context.badColor),
            stat('Lợi nhuận', formatNumber(s.chenhLech), s.chenhLech >= 0 ? context.okColor : context.badColor),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 0, children: [
            if (cu != null) TextButton(onPressed: () => _editPhone(c, cu), child: const Text('Sửa')),
            if (cu != null)
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerConfigScreen(controller: c, customer: cu))),
                child: Text(cu.scoringRates != null ? 'Cấu hình tính điểm (riêng)' : 'Cấu hình tính điểm'),
              ),
            if (cu != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: context.badColor),
                onPressed: _busyId == cu.id ? null : () => _remove(c, cu),
                child: Text(_busyId == cu.id ? 'Đang xoá...' : 'Xoá khỏi danh sách'),
              ),
            if (cu == null) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Chưa thêm vào danh sách', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
          ]),
        ]),
      ),
    );
  }
}
