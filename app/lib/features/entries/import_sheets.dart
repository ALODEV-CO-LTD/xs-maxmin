import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/bet_types.dart';
import '../../core/theme.dart';
import 'dialogs.dart';
import 'entries_controller.dart';
import 'message_parser.dart';
import 'ocr_service.dart';

enum ImportMode { paste, photo }

/// "Nhập từ tin nhắn" / "Nhập từ ảnh": parse -> PREVIEW (uncertain lines highlighted and unticked) -> the user edits,
/// ticks and confirms -> only then is anything stored. Nothing is ever saved automatically.
Future<void> showImportSheet(BuildContext context, EntriesController c, ImportMode mode) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<EntriesController>.value(value: c, child: _ImportSheet(mode: mode)),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.mode});
  final ImportMode mode;
  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _text = TextEditingController();
  final _aliases = TextEditingController();
  final _markers = TextEditingController(text: defaultStakeMarkers.join(', '));
  String _defaultType = '';
  bool _templateOpen = false;
  String _templateMsg = '';
  List<RowDraft> _drafts = [];
  List<String> _ignored = [];
  String _error = '';
  bool _saving = false;

  // photo
  String? _photoPath;
  bool _reading = false;
  final _picker = ImagePicker();

  EntriesController get c => context.read<EntriesController>();

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _text.dispose();
    _aliases.dispose();
    _markers.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _loadDraft() {
    final cfg = c.savedTemplate?.config;
    _defaultType = cfg?.defaultType ?? '';
    _aliases.text = aliasesToText(cfg?.typeAliases);
    _markers.text = (cfg != null && cfg.stakeMarkers.isNotEmpty ? cfg.stakeMarkers : defaultStakeMarkers).join(', ');
  }

  SyntaxTemplate _draftConfig() => SyntaxTemplate(
        defaultType: _defaultType,
        typeAliases: textToAliases(_aliases.text, c.betTypes),
        stakeMarkers: textToMarkers(_markers.text),
      );

  void _setDrafts(List<ParsedRow> parsed) {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts = [for (final r in parsed) RowDraft(type: r.type, value: r.value, score: r.score, selected: !r.uncertain, reasons: r.reasons, raw: r.raw)];
  }

  void _analyze(String text, {required bool photo}) {
    setState(() {
      _error = '';
      if (photo) {
        _ignored = [];
        _setDrafts(suggestionsFromOcr(text, betTypes: c.betTypes, template: _draftConfig()));
        if (_drafts.isEmpty) _error = 'Không tìm thấy số nào trong ảnh.';
      } else {
        final res = parseMessage(text, betTypes: c.betTypes, template: _draftConfig());
        _ignored = res.ignored;
        _setDrafts(res.rows);
        if (_drafts.isEmpty) _error = 'Không tìm thấy số nào trong tin nhắn.';
      }
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final f = await _picker.pickImage(source: source, maxWidth: 2200, imageQuality: 90);
      if (f == null) return;
      setState(() {
        _photoPath = f.path;
        _reading = true;
        _error = '';
        _text.clear();
      });
      final text = await recognizeImageText(f.path);
      if (!mounted) return;
      _text.text = text.trim();
      setState(() => _reading = false);
      _analyze(_text.text, photo: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _reading = false;
          _error = describeOcrError(e);
        });
      }
    }
  }

  List<RowDraft> get _picked => _drafts.where((d) => d.selected).toList();

  Future<void> _save() async {
    final picked = _picked;
    if (c.selectedName.isEmpty) return setState(() => _error = 'Chọn khách hàng trước khi lưu.');
    if (picked.isEmpty) return setState(() => _error = 'Chưa chọn dòng nào để lưu.');
    if (!picked.every((d) => d.isComplete)) return setState(() => _error = 'Các dòng đã chọn cần đủ Hạng mục, Số và Điểm vào.');
    final unsure = picked.where((d) => d.uncertain).length;
    final ok = await confirmDialog(
      context,
      title: 'Lưu số liệu',
      message: 'Lưu ${picked.length} số liệu cho khách hàng "${c.selectedName}", ngày ${c.entryDate}?'
          '${unsure > 0 ? ' Trong đó $unsure dòng chưa chắc chắn, hãy chắc là đã kiểm tra.' : ''}',
      confirmText: 'Lưu',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final err = await c.saveDrafts(picked, onSaved: (d) {
      _drafts.remove(d);
      d.dispose();
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = err;
    });
    if (_drafts.isEmpty && err.isEmpty) {
      showSnack(context, 'Đã lưu ${picked.length} số liệu');
      Navigator.pop(context);
    }
  }

  void _toForm() {
    final picked = _picked;
    if (picked.isEmpty) return;
    c.addRowsFromDrafts(picked);
    for (final d in picked) {
      _drafts.remove(d);
      d.dispose();
    }
    setState(() {});
    if (_drafts.isEmpty) Navigator.pop(context);
  }

  Future<void> _saveTemplate() async {
    final ok = await confirmDialog(
      context,
      title: 'Lưu mẫu cú pháp',
      message: 'Lưu cách viết này làm mẫu riêng cho khách hàng "${c.selectedName}"? Lần sau dán tin nhắn của khách này sẽ được phân tích theo mẫu.',
      confirmText: 'Lưu mẫu',
    );
    if (!ok) return;
    final msg = await c.saveTemplate(_draftConfig());
    if (mounted) setState(() => _templateMsg = msg);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<EntriesController>();
    final photo = widget.mode == ImportMode.photo;
    final types = ctl.betTypes;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(photo ? 'Nhập từ ảnh' : 'Nhập từ tin nhắn', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          photo
              ? 'Chọn ảnh có số liệu. Ảnh được đọc ngay trên máy, không gửi đi đâu. Kết quả chỉ là gợi ý: hãy kiểm tra lại trước khi lưu.'
              : 'Dán tin nhắn của khách rồi bấm Phân tích để xem trước. Dòng chưa chắc chắn được tô màu và chưa được chọn. Chỉ khi bạn bấm Lưu mới ghi vào dữ liệu.',
          style: TextStyle(fontSize: 13, color: context.mutedColor),
        ),
        const SizedBox(height: 12),
        if (photo) ...[
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _reading ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Chụp ảnh'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _reading ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Chọn ảnh'))),
          ]),
          if (_reading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (_photoPath != null && !_reading) ...[
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(_photoPath!), height: 160, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())),
            const SizedBox(height: 12),
            TextField(controller: _text, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Văn bản đọc được (để đối chiếu, có thể sửa)')),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: () => _analyze(_text.text, photo: true), child: const Text('Phân tích lại'))),
          ],
        ] else ...[
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nội dung tin nhắn', hintText: 'Vd:\nde 12 34 56 x 10\nlo 45 78 con 3'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: _text.text.trim().isEmpty ? null : () => _analyze(_text.text, photo: false), child: const Text('Phân tích')),
            OutlinedButton(
              onPressed: () => setState(() => _templateOpen = !_templateOpen),
              child: Text('Mẫu cú pháp của khách này ${ctl.savedTemplate != null ? '(đã lưu)' : '(chưa lưu)'}'),
            ),
          ]),
          if (_templateOpen) _templateBox(ctl, types),
        ],
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: InfoBox(_error)),
        if (_drafts.isNotEmpty) ..._previewSection(ctl, types),
      ]),
    );
  }

  Widget _templateBox(EntriesController ctl, List<String> types) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Mô tả cách khách này hay viết để phân tích đúng hơn. Mẫu chỉ được lưu khi bạn bấm Lưu mẫu, hệ thống không tự học thêm.', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: types.contains(_defaultType) ? _defaultType : '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Hạng mục mặc định'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Không đặt (dòng không ghi hạng mục sẽ bị đánh dấu)', overflow: TextOverflow.ellipsis)),
            for (final t in types) DropdownMenuItem(value: t, child: Text(betTypeLabel(t))),
          ],
          onChanged: (v) => setState(() => _defaultType = v ?? ''),
        ),
        const SizedBox(height: 10),
        TextField(controller: _aliases, decoration: const InputDecoration(labelText: 'Cách viết hạng mục', hintText: 'vd: dd=de, l=lo')),
        const SizedBox(height: 10),
        TextField(controller: _markers, decoration: const InputDecoration(labelText: 'Dấu ngăn điểm', hintText: 'vd: x, con, =')),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: ctl.selectedName.isEmpty ? null : _saveTemplate, child: Text('Lưu mẫu cho ${ctl.selectedName}')),
          if (ctl.savedTemplate != null)
            TextButton(
              onPressed: () async {
                final msg = await ctl.deleteTemplate();
                if (mounted) setState(() => _templateMsg = msg);
              },
              child: const Text('Xoá mẫu'),
            ),
        ]),
        if (_templateMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_templateMsg, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  List<Widget> _previewSection(EntriesController ctl, List<String> types) {
    final uncertain = _drafts.where((d) => d.uncertain).length;
    return [
      const SizedBox(height: 16),
      Text(
        'Đã chọn ${_picked.length}/${_drafts.length} dòng${uncertain > 0 ? ', $uncertain dòng chưa chắc chắn (tô vàng)' : ''}.',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      for (final d in _drafts) _previewRow(d, types),
      if (_ignored.isNotEmpty) Text('Bỏ qua ${_ignored.length} dòng không có số: ${_ignored.join(' / ')}', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _saving || !ctl.canAdd || _picked.isEmpty ? null : _save, child: Text(_saving ? 'Đang lưu...' : 'Xác nhận và lưu ${_picked.length} dòng')),
        OutlinedButton(onPressed: _picked.isEmpty ? null : _toForm, child: const Text('Đưa vào bảng nhập để sửa')),
        TextButton(
          onPressed: () => setState(() {
            _setDrafts(const []);
            _ignored = [];
            _error = '';
          }),
          child: const Text('Bỏ xem trước'),
        ),
      ]),
    ];
  }

  Widget _previewRow(RowDraft d, List<String> types) {
    final warn = d.uncertain;
    final typeList = types.contains(d.type) ? types : [...types, d.type];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
      decoration: BoxDecoration(
        color: warn ? Brand.warning.withValues(alpha: 0.14) : null,
        border: Border.all(color: warn ? Brand.warning.withValues(alpha: 0.7) : Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Checkbox(value: d.selected, onChanged: (v) => setState(() => d.selected = v ?? false)),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: d.type,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [for (final t in typeList) DropdownMenuItem(value: t, child: Text(betTypeLabel(t), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => d.type = v ?? d.type),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: TextField(controller: d.value, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, hintText: 'Số'), onChanged: (_) => setState(() {}))),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: TextField(controller: d.score, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(isDense: true, hintText: 'Điểm'), onChanged: (_) => setState(() {}))),
        ]),
        if (warn)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
            child: Text('Chưa chắc chắn: ${d.reasons.join('; ')}${d.raw.isNotEmpty ? ' (dòng gốc: ${d.raw})' : ''}', style: const TextStyle(fontSize: 12.5)),
          ),
      ]),
    );
  }
}
