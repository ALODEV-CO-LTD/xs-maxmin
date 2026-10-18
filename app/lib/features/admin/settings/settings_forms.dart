import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'settings_logic.dart';
import 'settings_ui.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/keyboard.dart';

Widget _editBar({required bool editing, required bool saving, required VoidCallback onEdit, required VoidCallback onCancel, required VoidCallback? onSave, required String saveLabel}) {
  if (!editing) {
    return SizedBox(
      width: double.infinity,
      child: AppButton(label: 'Sửa', variant: AppButtonVariant.secondary, onPressed: onEdit),
    );
  }
  return Row(
    children: [
      Expanded(
        child: AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: saving ? null : onCancel),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: AppButton(label: saveLabel, variant: AppButtonVariant.primary, loading: saving, onPressed: saving ? null : onSave),
      ),
    ],
  );
}

/// Thanh toán: bank account customers transfer to (display-only until "Sửa").
class BankSection extends StatefulWidget {
  const BankSection({super.key, required this.raw, required this.onRaw});
  final Map<String, dynamic> raw;
  final ValueChanged<Map<String, dynamic>> onRaw;
  @override
  State<BankSection> createState() => _BankSectionState();
}

class _BankSectionState extends State<BankSection> {
  late final EditSession<BankForm> _edit = EditSession(BankForm.fromSettings(widget.raw));
  late BankForm _form = _edit.saved;
  late final _acc = TextEditingController(text: _form.account);
  late final _holder = TextEditingController(text: _form.holder);
  bool _saving = false, _saved = false;
  String? _error;

  @override
  void dispose() {
    _acc.dispose();
    _holder.dispose();
    super.dispose();
  }

  void _apply(BankForm f) {
    _form = f;
    _acc.text = f.account;
    _holder.text = f.holder;
  }

  Future<void> _save() async {
    final cur = _form.copyWith(account: _acc.text, holder: _holder.text);
    final bad = cur.validate();
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    try {
      final res = await context.read<ApiClient>().put('/admin/settings', cur.toBody());
      if (!mounted) return;
      final raw = Map<String, dynamic>.from(res as Map);
      final saved = BankForm.fromSettings(raw);
      setState(() {
        _edit.commit(saved);
        _apply(saved);
        _saved = true;
      });
      widget.onRaw(raw);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không thể lưu cấu hình thanh toán'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _edit.editing;
    final known = vietQrBanks.any((b) => b.bin == _form.bin);
    return SectionCard(
      title: 'Tài khoản nhận thanh toán',
      subtitle: 'Khách hàng sẽ thấy thông tin này (và mã QR chuyển khoản nhanh) ở trang Gói dịch vụ khi mua gói.',
      children: [
        if (_error != null) Banner2(_error!),
        if (_saved) const Banner2('Đã lưu cấu hình thanh toán', error: false),
        AppDropdown<String>(
          key: ValueKey('bank-${_form.bin}-$editing'),
          initialValue: known ? _form.bin : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Ngân hàng'),
          hint: const Text('-- Chưa chọn ngân hàng --'),
          items: [for (final b in vietQrBanks) DropdownMenuItem(value: b.bin, child: Text(b.name))],
          onChanged: editing ? (v) => setState(() => _form = _form.copyWith(bin: v ?? '')) : null,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _acc,
          enabled: editing,
          keyboardType: kNumbersKeyboard,
          decoration: const InputDecoration(labelText: 'Số tài khoản'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _holder,
          enabled: editing,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Chủ tài khoản'),
        ),
        const SizedBox(height: 14),
        _editBar(
          editing: editing,
          saving: _saving,
          onEdit: () => setState(() {
            _edit.begin();
            _saved = false;
          }),
          onCancel: () => setState(() {
            _apply(_edit.cancel());
            _error = null;
          }),
          onSave: _save,
          saveLabel: 'Lưu cấu hình thanh toán',
        ),
      ],
    );
  }
}

/// Giới hạn ID: max virtual IDs (Mã ID) per customer account.
class MaxIdsSection extends StatefulWidget {
  const MaxIdsSection({super.key, required this.raw, required this.onRaw});
  final Map<String, dynamic> raw;
  final ValueChanged<Map<String, dynamic>> onRaw;
  @override
  State<MaxIdsSection> createState() => _MaxIdsSectionState();
}

class _MaxIdsSectionState extends State<MaxIdsSection> {
  late final EditSession<String> _edit = EditSession('${widget.raw['max_virtual_ids'] ?? ''}');
  late final _c = TextEditingController(text: _edit.saved);
  bool _saving = false, _saved = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bad = validateMaxIds(_c.text);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    try {
      final res = await context.read<ApiClient>().put('/admin/settings', {'max_virtual_ids': maxIdsBody(_c.text)});
      if (!mounted) return;
      final raw = Map<String, dynamic>.from(res as Map);
      setState(() {
        _edit.commit('${raw['max_virtual_ids'] ?? ''}');
        _c.text = _edit.saved;
        _saved = true;
      });
      widget.onRaw(raw);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không thể lưu giới hạn ID ảo'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Giới hạn ID ảo',
    subtitle: 'Số Mã ID (ID ảo) tối đa mỗi tài khoản khách hàng được tạo. Mặc định 5.',
    children: [
      if (_error != null) Banner2(_error!),
      if (_saved) const Banner2('Đã lưu giới hạn ID ảo', error: false),
      TextField(
        controller: _c,
        enabled: _edit.editing,
        keyboardType: kNumbersKeyboard,
        decoration: const InputDecoration(labelText: 'Số ID tối đa mỗi tài khoản (1-100)', hintText: '5'),
      ),
      const SizedBox(height: 14),
      _editBar(
        editing: _edit.editing,
        saving: _saving,
        onEdit: () => setState(() {
          _edit.begin();
          _saved = false;
        }),
        onCancel: () => setState(() {
          _c.text = _edit.cancel();
          _error = null;
        }),
        onSave: _save,
        saveLabel: 'Lưu giới hạn',
      ),
    ],
  );
}

/// Giá gói: the editable package catalog (/admin/packages).
class PackagesSection extends StatefulWidget {
  const PackagesSection({super.key});
  @override
  State<PackagesSection> createState() => _PackagesSectionState();
}

class _PackagesSectionState extends State<PackagesSection> {
  bool _loading = true;
  String? _error, _notice, _busy;
  String? _editing; // package type, or 'new'
  List<PackageItem> _items = [];
  final _label = TextEditingController();
  final _days = TextEditingController();
  final _price = TextEditingController();

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    _days.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/admin/packages');
      if (!mounted) return;
      setState(() {
        _items = [
          for (final p in ((res as Map)['packages'] as List? ?? const []))
            if (p is Map<String, dynamic>) PackageItem.fromJson(p),
        ];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được danh sách gói'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startNew() => setState(() {
    _label.clear();
    _days.clear();
    _price.clear();
    _editing = 'new';
    _notice = null;
  });

  void _startEdit(PackageItem p) => setState(() {
    _label.text = p.label;
    _days.text = '${p.durationDays}';
    _price.text = '${p.priceVnd}';
    _editing = p.type;
    _notice = null;
  });

  Future<void> _save() async {
    final parsed = parsePackageForm(_label.text, _days.text, _price.text);
    if (parsed.error != null) {
      setState(() => _error = parsed.error);
      return;
    }
    final target = _editing!;
    setState(() {
      _busy = target;
      _error = null;
    });
    try {
      if (target == 'new') {
        await _api.post('/admin/packages', parsed.body);
      } else {
        await _api.patch('/admin/packages/$target', parsed.body);
      }
      _notice = target == 'new' ? 'Đã thêm gói' : 'Đã lưu gói (giá mới chỉ áp dụng cho yêu cầu mua sau này)';
      _editing = null;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không lưu được gói'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _toggle(PackageItem p) async {
    setState(() {
      _busy = p.type;
      _error = null;
    });
    try {
      await _api.patch('/admin/packages/${p.type}', {'active': !p.active});
      _notice = p.active ? 'Đã ẩn gói ${p.label} (người dùng không còn thấy để mua)' : 'Đã hiện lại gói ${p.label}';
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không cập nhật được gói'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remove(PackageItem p) async {
    if (p.inUse) {
      setState(() => _error = 'Gói "${p.label}" đã có tài khoản hoặc giao dịch sử dụng nên không xoá được. Hãy ẩn gói để ngừng bán.');
      return;
    }
    if (!await confirmDialog(context, title: 'Xoá gói', message: 'Xoá gói "${p.label}"?', confirmText: 'Xoá', danger: true)) return;
    setState(() {
      _busy = p.type;
      _error = null;
    });
    try {
      await _api.delete('/admin/packages/${p.type}');
      _notice = 'Đã xoá gói ${p.label}';
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không xoá được gói'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _form(String key, String saveLabel) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _label,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Tên gói', hintText: 'Vd: 2 tháng'),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _days,
              keyboardType: kNumbersKeyboard,
              decoration: const InputDecoration(labelText: 'Thời hạn (ngày)', helperText: '1-3650'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _price,
              keyboardType: kNumbersKeyboard,
              decoration: const InputDecoration(labelText: 'Giá (đ)'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy == key ? null : () => setState(() => _editing = null)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: AppButton(label: saveLabel, variant: AppButtonVariant.primary, onPressed: _busy == key ? null : _save),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Placeholder2('', busy: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Thêm, sửa, ẩn hoặc xoá các gói khách hàng có thể mua. Đổi giá chỉ áp dụng cho yêu cầu mua sau này.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
        const SizedBox(height: 10),
        if (_error != null) Banner2(_error!),
        if (_notice != null) Banner2(_notice!, error: false),
        if (_editing == 'new')
          SectionCard(title: 'Gói mới', children: [_form('new', 'Thêm gói')])
        else
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(label: 'Thêm gói', variant: AppButtonVariant.primary, icon: Icons.add, onPressed: _startNew),
          ),
        const SizedBox(height: 10),
        if (_items.isEmpty && _editing != 'new') const Placeholder2('Chưa có gói nào.'),
        for (final p in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _editing == p.type
                    ? _form(p.type, 'Lưu')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ),
                              if (!p.active)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Chip(label: Text('Đang ẩn'), visualDensity: VisualDensity.compact),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${formatDuration(p.durationDays)} · ${formatVndPlain(p.priceVnd)} · ${p.users} tài khoản đang dùng', style: TextStyle(color: context.mutedColor, fontSize: 13)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(label: 'Sửa', variant: AppButtonVariant.primary, onPressed: _busy == p.type ? null : () => _startEdit(p)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppButton(label: p.active ? 'Ẩn' : 'Hiện lại', variant: AppButtonVariant.secondary, onPressed: _busy == p.type ? null : () => _toggle(p)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppButton(label: 'Xoá', variant: AppButtonVariant.danger, onPressed: _busy == p.type ? null : () => _remove(p)),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
