import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'date_field.dart';
import 'entry_model.dart';

/// "Đặt lịch xóa": schedule the automatic removal of saved entries (one customer or everyone, an optional date range, or
/// repeating while keeping the newest N days) and see / cancel the pending schedules.
///
/// GET/POST /me/deletion-schedules, DELETE /me/deletion-schedules/:id, GET /me/customers. POST without `confirm` only
/// answers a preview ({scopeText, willDeleteNow, runAt}) that is shown first; with `confirm: true` and the account
/// `password` it creates the schedule (403 wrong password). A repeating schedule never carries dateFrom / dateTo.
class DeletionSchedulesPage extends StatelessWidget {
  const DeletionSchedulesPage({super.key, required this.api, this.customerName = ''});
  final ApiClient api;
  final String customerName;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Đặt lịch xóa')),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: DeletionSchedules(api: api, customerName: customerName),
        ),
      );
}

/// The schedule form and the list of schedules (web: components/DeletionSchedules.vue). Shown in the Đặt lịch xóa page
/// of Tính điểm and in the Dữ liệu tab of Tài khoản.
class DeletionSchedules extends StatefulWidget {
  const DeletionSchedules({super.key, required this.api, this.customerName = ''});
  final ApiClient api;
  final String customerName;
  @override
  State<DeletionSchedules> createState() => _DeletionSchedulesState();
}

const _unitText = {'day': 'ngày', 'week': 'tuần', 'month': 'tháng'};
const _ttlText = {3600: '1 giờ', 86400: '1 ngày', 604800: '7 ngày', 2592000: '30 ngày'};

String _fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)} ${two(d.day)}/${two(d.month)}/${d.year}';
}

String describeSchedule(Map<String, dynamic> s) {
  if (s['kind'] == 'chat') {
    final what = s['chatScope'] == 'images' ? 'Ảnh' : 'Tin nhắn & tệp';
    final ttl = s['ttlSeconds'];
    return '$what cũ hơn ${_ttlText[ttl] ?? '$ttl giây'} trong cuộc trò chuyện với ${s['friendName'] ?? '?'}';
  }
  final cn = s['customerName'];
  final who = cn is String && cn.isNotEmpty ? 'khách "$cn"' : 'mọi khách';
  final from = s['dateFrom'], to = s['dateTo'];
  final range = from != null || to != null ? ', ngày ${from ?? '...'} đến ${to ?? '...'}' : ', mọi ngày';
  final keep = (s['keepDays'] as num? ?? 0) > 0 ? ', giữ lại ${s['keepDays']} ngày gần nhất' : '';
  return 'Số liệu đã nhập của $who$range$keep';
}

String scheduleStatus(Map<String, dynamic> s) {
  if (s['status'] == 'done') return 'Đã xoá ${s['deletedCount']} mục lúc ${_fmtTime(s['executedAt'] as String?)}';
  if (s['kind'] == 'chat') {
    final n = s['deletedCount'] as num? ?? 0;
    return 'Đang áp dụng từ ${_fmtTime(s['runAt'] as String?)}${n > 0 ? ' (đã xoá $n mục)' : ''}';
  }
  return 'Sẽ xoá lúc ${_fmtTime(s['runAt'] as String?)}';
}

class _DeletionSchedulesState extends State<DeletionSchedules> {
  List<Map<String, dynamic>> _schedules = [];
  List<CustomerRec> _customers = [];
  bool _loading = true;
  String _error = '';
  String _success = '';
  bool _saving = false;

  late String _customer = widget.customerName;
  String _dateFrom = '';
  String _dateTo = '';
  String _repeat = 'none'; // none | 1w | 10d | 1m | custom
  final _customN = TextEditingController(text: '2');
  String _customUnit = 'day';
  final _keep = TextEditingController(text: '0');
  final _password = TextEditingController();
  DateTime _runAt = DateTime.now().add(const Duration(days: 1));
  bool _runAtTouched = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customN.dispose();
    _keep.dispose();
    _password.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _repeatValue {
    switch (_repeat) {
      case '1w':
        return {'every': 1, 'unit': 'week'};
      case '10d':
        return {'every': 10, 'unit': 'day'};
      case '1m':
        return {'every': 1, 'unit': 'month'};
      case 'custom':
        return {'every': int.tryParse(_customN.text.trim()) ?? 0, 'unit': _customUnit};
      default:
        return null;
    }
  }

  void _defaultRunAt() {
    if (_runAtTouched) return;
    final r = _repeatValue;
    final now = DateTime.now();
    final every = r != null && (r['every'] as int) > 0 ? r['every'] as int : 1;
    final unit = r?['unit'] ?? 'day';
    _runAt = switch (unit) {
      'week' => now.add(Duration(days: 7 * every)),
      'month' => DateTime(now.year, now.month + every, now.day, now.hour, now.minute),
      _ => now.add(Duration(days: r == null ? 1 : every)),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final s = await widget.api.get('/me/deletion-schedules') as Map;
      final c = await widget.api.get('/me/customers') as Map;
      _schedules = [for (final x in (s['schedules'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      _customers = [for (final x in (c['customers'] as List? ?? const [])) CustomerRec.fromJson(Map<String, dynamic>.from(x as Map))];
    } on ApiError catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Không tải được lịch xoá';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickRunAt() async {
    final d = await showDatePicker(context: context, initialDate: _runAt, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), cancelText: 'Huỷ', confirmText: 'Chọn');
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_runAt), cancelText: 'Huỷ', confirmText: 'Chọn');
    if (t == null) return;
    setState(() {
      _runAtTouched = true;
      _runAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _error = '';
      _success = '';
    });
    final repeat = _repeatValue;
    if (_repeat == 'custom' && (repeat!['every'] as int < 1 || repeat['every'] as int > 365)) {
      return setState(() => _error = 'Chu kỳ lặp phải từ 1 đến 365');
    }
    final keep = int.tryParse(_keep.text.trim()) ?? 0;
    if (keep < 0 || keep > 3650) return setState(() => _error = 'Số ngày giữ lại phải từ 0 đến 3650');
    if (_password.text.isEmpty) return setState(() => _error = 'Nhập mật khẩu đăng nhập để xác nhận');
    final body = <String, dynamic>{
      'kind': 'data',
      'customerName': ?(_customer.isNotEmpty ? _customer : null),
      'runAt': _runAt.toUtc().toIso8601String(),
      'repeat': ?repeat,
      if (repeat == null && _dateFrom.isNotEmpty) 'dateFrom': _dateFrom,
      if (repeat == null && _dateTo.isNotEmpty) 'dateTo': _dateTo,
      if (keep > 0) 'keepDays': keep,
    };
    setState(() => _saving = true);
    try {
      // Step 1: the server describes exactly what would be deleted and when.
      final preview = await widget.api.post('/me/deletion-schedules', body) as Map;
      final lines = <String>['CẢNH BÁO: ${preview['scopeText'] ?? ''}'];
      final scope = '${preview['scopeText'] ?? ''}';
      if (!RegExp('lần đầu|lúc \\d').hasMatch(scope)) lines.add('Thời điểm xoá${repeat != null ? ' lần đầu' : ''}: ${_fmtTime((preview['runAt'] ?? body['runAt']) as String?)}.');
      if (preview['willDeleteNow'] is num && !RegExp('xoá ngay|xóa ngay|chạy ngay', caseSensitive: false).hasMatch(scope)) {
        lines.add('Nếu chạy ngay bây giờ sẽ xoá ${preview['willDeleteNow']} số liệu.');
      }
      lines.add('Bạn có thể huỷ lịch trước thời điểm này.');
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xác nhận lịch xoá dữ liệu'),
          content: SingleChildScrollView(child: Text(lines.join('\n\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: ctx.badColor, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Đặt lịch xoá')),
          ],
        ),
      );
      if (ok != true) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      // Step 2: confirmed.
      await widget.api.post('/me/deletion-schedules', {...body, 'confirm': true, 'password': _password.text});
      _password.clear();
      _success = 'Đã đặt lịch xoá.';
      await _load();
    } on ApiError catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Không đặt được lịch xoá';
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _cancel(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Huỷ lịch xoá'),
        content: Text('Huỷ lịch này? ${describeSchedule(s)}. Dữ liệu đã bị xoá trước đó sẽ không được khôi phục.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Huỷ lịch')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/me/deletion-schedules/${s['id']}');
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final names = _customers.map((c) => c.name).toList();
    if (_customer.isNotEmpty && !names.contains(_customer)) names.add(_customer);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Hệ thống tự xóa số liệu theo lịch, một lần hoặc lặp lại. Dữ liệu đã xóa không thể khôi phục. Bạn sẽ thấy cảnh báo về phạm vi xóa và thời điểm trước khi xác nhận.', style: t.bodySmall?.copyWith(color: context.mutedColor)),
            if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error, style: TextStyle(color: context.badColor))),
            if (_success.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_success, style: TextStyle(color: context.okColor))),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Lịch mới', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('c${names.length}$_customer'),
                    initialValue: _customer,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Khách hàng'),
                    items: [const DropdownMenuItem(value: '', child: Text('Tất cả khách hàng')), for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _customer = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _repeat,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Lặp lại'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Không lặp (chỉ một lần)')),
                      DropdownMenuItem(value: '1w', child: Text('Mỗi 1 tuần')),
                      DropdownMenuItem(value: '10d', child: Text('Mỗi 10 ngày')),
                      DropdownMenuItem(value: '1m', child: Text('Mỗi 1 tháng')),
                      DropdownMenuItem(value: 'custom', child: Text('Tuỳ chọn')),
                    ],
                    onChanged: (v) => setState(() {
                      _repeat = v ?? 'none';
                      if (_repeat != 'none') {
                        _dateFrom = '';
                        _dateTo = '';
                      }
                      _defaultRunAt();
                    }),
                  ),
                  if (_repeat == 'custom') ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextField(controller: _customN, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Mỗi (số)'), onChanged: (_) => setState(_defaultRunAt))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _customUnit,
                          decoration: const InputDecoration(labelText: 'Đơn vị'),
                          items: [for (final e in _unitText.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                          onChanged: (v) => setState(() {
                            _customUnit = v ?? 'day';
                            _defaultRunAt();
                          }),
                        ),
                      ),
                    ]),
                  ],
                  if (_repeat == 'none') ...[
                    const SizedBox(height: 10),
                    DateField(label: 'Từ ngày (tuỳ chọn)', value: _dateFrom, clearable: true, onChanged: (v) => setState(() => _dateFrom = v)),
                    const SizedBox(height: 10),
                    DateField(label: 'Đến ngày (tuỳ chọn)', value: _dateTo, clearable: true, onChanged: (v) => setState(() => _dateTo = v)),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: _keep, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giữ lại N ngày gần nhất (tuỳ chọn)')),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _pickRunAt,
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: _repeat == 'none' ? 'Thời điểm xoá' : 'Thời điểm xoá lần đầu', suffixIcon: const Icon(Icons.schedule, size: 18)),
                      child: Text(_fmtTime(_runAt.toIso8601String())),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu đăng nhập')),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Đang xử lý...' : 'Đặt lịch xoá')),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text('Các lịch xoá', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            else if (_schedules.isEmpty)
              Text('Chưa có lịch xoá nào.', style: TextStyle(color: context.mutedColor))
            else
              for (final s in _schedules)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(describeSchedule(s), style: const TextStyle(fontSize: 14)),
                    subtitle: Text([
                      scheduleStatus(s),
                      if (s['repeat'] is Map) 'Lặp mỗi ${(s['repeat'] as Map)['every']} ${_unitText[(s['repeat'] as Map)['unit']] ?? ''}, đã chạy ${s['runCount'] ?? 0} lần, xoá tổng ${s['deletedCount'] ?? 0} số liệu',
                      if (s['kind'] == 'chat' && s['setByMe'] == false) 'Do bạn bè đặt',
                    ].join('\n')),
                    isThreeLine: s['repeat'] is Map,
                    trailing: s['status'] == 'pending' ? IconButton(tooltip: 'Huỷ lịch', icon: Icon(Icons.close, color: context.badColor), onPressed: () => _cancel(s)) : null,
                  ),
                ),
    ]);
  }
}
