import 'package:flutter/material.dart';
import '../../../core/widgets/svg_icon.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../payments/payments_logic.dart' show viDateTime;
import 'settings_logic.dart';
import 'settings_ui.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/keyboard.dart';

/// Nhật ký bảo mật: the 50 latest security events.
class SecurityEventsSection extends StatefulWidget {
  const SecurityEventsSection({super.key});
  @override
  State<SecurityEventsSection> createState() => _SecurityEventsSectionState();
}

class _SecurityEventsSectionState extends State<SecurityEventsSection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().get('/admin/security-events?limit=50');
      if (!mounted) return;
      setState(
        () => _events = [
          for (final e in ((res as Map)['events'] as List? ?? const []))
            if (e is Map<String, dynamic>) e,
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không thể tải nhật ký bảo mật'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nhật ký bảo mật gần đây. Không ghi mật khẩu hay token.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
        const SizedBox(height: 10),
        if (_error != null) Banner2(_error!),
        if (_loading)
          const Placeholder2('', busy: true)
        else if (_events.isEmpty)
          const Placeholder2('Chưa có sự kiện nào.')
        else
          for (final e in _events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(securityEventLabels['${e['type']}'] ?? '${e['type']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${viDateTime(e['createdAt'] as String?)} · ${(e['username'] ?? '-')} · IP ${(e['ip'] ?? '-')}', style: TextStyle(color: context.mutedColor, fontSize: 12)),
                      if ('${e['detail'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${e['detail']}', style: const TextStyle(fontSize: 13)),
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

/// Chính sách bảo mật: display-only until "Sửa".
class SecurityPolicySection extends StatefulWidget {
  const SecurityPolicySection({super.key});
  @override
  State<SecurityPolicySection> createState() => _SecurityPolicySectionState();
}

class _SecurityPolicySectionState extends State<SecurityPolicySection> {
  final _edit = EditSession<SecurityPolicyForm>(const SecurityPolicyForm());
  SecurityPolicyForm _flags = const SecurityPolicyForm();
  SecurityPolicyForm _defaults = const SecurityPolicyForm();
  final _ctrls = {for (final k in policyRanges.keys) k: TextEditingController()};
  bool _loading = true, _saving = false;
  String? _error, _notice;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Form as currently typed (an unparsable number becomes -1 so validate() refuses it).
  SecurityPolicyForm get _current {
    var f = _flags;
    for (final e in _ctrls.entries) {
      f = f.withNumber(e.key, int.tryParse(e.value.text.trim()) ?? -1);
    }
    return f;
  }

  void _fill(Map res, {bool leave = true}) {
    final f = SecurityPolicyForm.fromJson(Map<String, dynamic>.from(res['policy'] as Map));
    _defaults = SecurityPolicyForm.fromJson(Map<String, dynamic>.from(res['defaults'] as Map? ?? const {}));
    _setForm(f);
    _edit.reset(f, leave: leave);
  }

  void _setForm(SecurityPolicyForm f) {
    _flags = f;
    for (final e in _ctrls.entries) {
      e.value.text = '${f.numeric(e.key)}';
    }
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/admin/security-policy');
      if (mounted) setState(() => _fill(res as Map));
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được chính sách bảo mật'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final cur = _current;
    final bad = cur.validate();
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await _api.put('/admin/security-policy', cur.toJson());
      if (!mounted) return;
      setState(() {
        _fill(res as Map);
        _notice = 'Đã lưu chính sách bảo mật.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không lưu được'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (!await confirmDialog(context, title: 'Đặt lại mặc định', message: 'Đặt lại toàn bộ chính sách bảo mật về giá trị mặc định?', confirmText: 'Đặt lại')) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await _api.delete('/admin/security-policy');
      if (!mounted) return;
      setState(() {
        _fill(res as Map);
        _notice = 'Đã đặt lại về mặc định.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không đặt lại được'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _num(String key, String help) {
    final r = policyRanges[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: ValueKey('policy-$key'),
        controller: _ctrls[key],
        enabled: _edit.editing,
        keyboardType: kNumbersKeyboard,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: r.label, helperMaxLines: 3, helperText: '${r.min} đến ${r.max} (mặc định ${_defaults.numeric(key)}). $help'.trim()),
      ),
    );
  }

  Widget _sw(String title, bool v, ValueChanged<bool> on, {String? sub}) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: v,
    onChanged: _edit.editing ? (x) => setState(() => on(x)) : null,
    title: Text(title),
    subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12)),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Placeholder2('', busy: true);
    final editing = _edit.editing;
    final cur = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Áp dụng cho toàn hệ thống. Mọi thay đổi được ghi vào nhật ký bảo mật.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
        const SizedBox(height: 10),
        if (_error != null) Banner2(_error!),
        if (_notice != null) Banner2(_notice!, error: false),
        SectionCard(
          title: 'Chống đoán mật khẩu',
          subtitle: 'Nhập sai quá số lần cho phép thì bị khoá tạm theo tài khoản và địa chỉ IP; mỗi lần sai tiếp theo, thời gian khoá nhân đôi đến mức tối đa.',
          children: [
            _num('loginFreeAttempts', ''),
            _num('loginBaseLockSeconds', ''),
            _num('loginMaxLockSeconds', ''),
            Text('Các lần khoá liên tiếp: ${cur.validate() == null ? cur.lockExample : '-'}', style: TextStyle(color: context.mutedColor, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Phiên đăng nhập',
          children: [_num('tokenDays', 'Chỉ áp dụng cho lần đăng nhập mới.'), _num('autoLockMinutes', '0 là tắt. Áp dụng cho cả hệ thống, chỉ dùng cho người chưa tự chọn trong Tài khoản.'), _num('hideLockSeconds', '0 là tắt. Khoá khi thoát ra hoặc chuyển ứng dụng quá số giây này (tắt màn hình cũng tính). Áp dụng cho cả hệ thống, chỉ dùng cho người chưa tự chọn trong Tài khoản.')],
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Bảo vệ màn hình',
          children: [
            _sw(
              'Bật đóng dấu tên người xem',
              _flags.watermarkEnabled,
              (v) => _flags = _flags.withFlags(watermark: v),
              sub: 'Dấu tên người xem mờ phủ trên mọi màn hình để ảnh bị lộ truy ra được tài khoản.',
            ),
            _sw('Phủ đen màn hình khi bấm phím chụp màn hình (máy tính)', _flags.screenshotGuardEnabled, (v) => _flags = _flags.withFlags(screenshotGuard: v)),
            _sw(
              'Làm mờ màn hình khi ẩn trang hoặc mất focus',
              _flags.blurOnHideEnabled,
              (v) => _flags = _flags.withFlags(blurOnHide: v),
              sub: 'Làm mờ nội dung khi chuyển sang ứng dụng khác. Mỗi người vẫn tự tắt được trong Tài khoản.',
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!editing)
          AppButton(label: 'Sửa', svg: AppSvg.edit, variant: AppButtonVariant.secondary, onPressed: () => setState(() {
              _edit.begin();
              _notice = null;
            }))
        else ...[
          AppButton(label: 'Đặt lại mặc định', variant: AppButtonVariant.secondary, onPressed: _saving ? null : _reset),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _saving
                      ? null
                      : () => setState(() {
                          _setForm(_edit.cancel());
                          _error = null;
                        })),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: AppButton(label: 'Lưu chính sách', variant: AppButtonVariant.primary, loading: _saving, onPressed: _saving || !_edit.dirty(cur) ? null : _save),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
