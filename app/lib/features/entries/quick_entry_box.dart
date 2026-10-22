import 'dart:io';
import '../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bet_types.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import '../calc/calc_screen.dart';
import 'dialogs.dart';
import 'entries_controller.dart';
import 'message_parser.dart';
import 'ocr_service.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/keyboard.dart';

/// Picks a picture and returns its path (null = cancelled). Replaceable in tests.
typedef PickImagePath = Future<String?> Function(ImageSource source);

Future<String?> _pickImagePath(ImageSource source) async => (await ImagePicker().pickImage(source: source, maxWidth: 2200, imageQuality: 90))?.path;

/// "Nhập nhanh" (web: the smart box of EntriesView.vue): ONE auto-growing box for a pasted message or a picture of it.
/// A picture is read on the phone (ML Kit) and its text joins the box, then both go through the same "Phân tích" preview
/// (uncertain lines highlighted and unticked) -> the user edits, ticks and confirms -> only then is anything stored.
/// Nothing is ever saved automatically.
/// Width share of a "Số" field: a single number needs little, a xiên ("33 23 45") grows with how many numbers it holds so they all show.
int valueFieldFlex(String text) {
  final n = text.trim().isEmpty ? 1 : text.trim().split(RegExp(r'\s+')).length;
  return n <= 1 ? 2 : (n == 2 ? 3 : 4);
}

class QuickEntryBox extends StatefulWidget {
  const QuickEntryBox({super.key, required this.controller, this.recognize = recognizeImageText, this.pickPath = _pickImagePath, this.goToScoring});
  final EntriesController controller;

  /// After numbers that came from a chat are all saved: open Tính điểm on [customer] and [date] (default: the router).
  final void Function(BuildContext context, String customer, String date, int added)? goToScoring;
  final Future<String> Function(String path) recognize;
  final PickImagePath pickPath;
  @override
  State<QuickEntryBox> createState() => _QuickEntryBoxState();
}

class _QuickEntryBoxState extends State<QuickEntryBox> {
  final _text = TextEditingController();
  final _aliases = TextEditingController();
  final _markers = TextEditingController(text: defaultStakeMarkers.join(', '));
  String _defaultType = '';
  bool _templateOpen = false;
  String _templateMsg = '';
  List<RowDraft> _drafts = [];
  List<String> _ignored = [];
  String _error = '';
  String _ocrError = '';
  bool _saving = false;

  // the picture that was read
  String? _photoPath;
  bool _reading = false;

  EntriesController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    c.addListener(_onController);
    _takeChatText();
  }

  // Text handed over from the chat ("Dùng cho Nhập số"): into the box, then analysed like a pasted message.
  void _takeChatText() {
    final t = c.takeBoxPrefill();
    if (t == null) return;
    _text.text = t;
    _analyze();
  }

  // The customer was changed: the template of the new one fills the template fields and a preview made for the old
  // customer is dropped (it must not be saved for the new one by mistake).
  String _loadedFor = '';
  void _onController() {
    if (_loadedFor != c.selectedName) {
      _loadDraft();
      if (!mounted) return;
      setState(() {
        _setDrafts(const []);
        _ignored = [];
        _error = '';
        _templateMsg = '';
      });
    }
    if (mounted) _takeChatText();
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _text.dispose();
    _aliases.dispose();
    _markers.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _loadDraft() {
    _loadedFor = c.selectedName;
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

  void _analyze() {
    setState(() {
      _error = '';
      final res = parseMessage(_text.text, betTypes: c.betTypes, template: _draftConfig(), kindSymbols: kindSymbolsFor(c.accountRates, c.customer?.scoringRates, c.regionId));
      _ignored = res.ignored;
      _setDrafts(res.rows);
      if (_drafts.isEmpty) _error = 'Không tìm thấy số nào trong tin nhắn.';
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final path = await widget.pickPath(source);
      if (path == null) return;
      setState(() {
        _photoPath = path;
        _reading = true;
        _ocrError = '';
        _error = '';
      });
      final read = (await widget.recognize(path)).trim();
      if (!mounted) return;
      if (read.isEmpty) {
        setState(() {
          _reading = false;
          _ocrError = 'Không đọc được chữ nào từ ảnh. Hãy chụp rõ hơn hoặc nhập tay.';
        });
        return;
      }
      // The text of the picture joins the box and is analysed like a pasted message.
      final before = _text.text.trim();
      _text.text = before.isEmpty ? read : '$before\n$read';
      setState(() => _reading = false);
      _analyze();
      if (_drafts.isEmpty) {
        // Nothing like "loại số x điểm": the numbers read become rows of the manual list to check there.
        final guess = suggestionsFromOcr(read, betTypes: c.betTypes, template: _draftConfig());
        c.addRowsFromDrafts([for (final r in guess) RowDraft(type: r.type, value: r.value, score: r.score)]);
        setState(() => _error = guess.isEmpty ? _error : 'Không thấy dạng "loại số x điểm" trong ảnh: các số đọc được đã thêm vào danh sách bên dưới để bạn kiểm tra.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reading = false;
          _ocrError = describeOcrError(e);
        });
      }
    }
  }

  void _clearPhoto() => setState(() {
        _photoPath = null;
        _ocrError = '';
      });

  void _zoomPhoto() {
    final path = _photoPath;
    if (path == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          Center(child: InteractiveViewer(maxScale: 6, child: Image.file(File(path), errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.white)))),
          SafeArea(child: IconButton(tooltip: 'Đóng', color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop())),
        ]),
      ),
    );
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
    final savedCount = picked.where((d) => !_drafts.contains(d)).length;
    setState(() {
      _saving = false;
      _error = err;
      if (_drafts.isEmpty) {
        _text.clear();
        _ignored = [];
        _photoPath = null;
      }
    });
    // Numbers that came from a chat: once they are all saved, go to Tính điểm on that customer and day (web: fromChat).
    if (c.fromChat && savedCount > 0 && err.isEmpty && _drafts.isEmpty) {
      c.fromChat = false;
      final go = widget.goToScoring ?? _goToScoring;
      go(context, c.selectedName.trim(), c.entryDate, savedCount);
    }
  }

  static void _goToScoring(BuildContext context, String customer, String date, int added) {
    GoRouter.maybeOf(context)?.go(calcLocation('scoring', customer: customer, date: date, added: added));
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
    final cs = Theme.of(context).colorScheme;
    final types = c.betTypes;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _text,
          minLines: 2,
          maxLines: null,
          enabled: !_reading,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nhập nhanh: tin nhắn hoặc ảnh của khách',
            alignLabelWithHint: true,
            hintText: 'Dán tin nhắn của khách, hoặc bấm Chọn ảnh\nVd: de 12 34 56 x 10\n      lo 45 78 con 3',
          ),
        ),
        const SizedBox(height: 4),
        Text('Ảnh được đọc ngay trên máy, không gửi đi đâu. Chỉ khi bạn bấm Lưu mới ghi vào dữ liệu.', style: TextStyle(fontSize: 12, color: context.mutedColor)),
        if (_ocrError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBox(_ocrError)),
        if (_photoPath != null) _photoRow(context),
        const SizedBox(height: 8),
        // One compact row: Phân tích takes the free width, the photo / camera / template actions are icon buttons (the label is their tooltip).
        Row(children: [
          Expanded(child: AppButton(label: 'Phân tích', variant: AppButtonVariant.primary, onPressed: _text.text.trim().isEmpty || _reading ? null : _analyze)),
          const SizedBox(width: 6),
          AppButton.icon(label: 'Chọn ảnh', variant: AppButtonVariant.secondary, svg: AppSvg.photoAdd, loading: _reading, onPressed: _reading ? null : () => _pick(ImageSource.gallery)),
          const SizedBox(width: 6),
          AppButton.icon(label: 'Chụp ảnh', variant: AppButtonVariant.secondary, svg: AppSvg.camera, onPressed: _reading ? null : () => _pick(ImageSource.camera)),
          const SizedBox(width: 6),
          AppButton.icon(label: 'Mẫu cú pháp của khách này ${c.savedTemplate != null ? '(đã lưu)' : '(chưa lưu)'}', variant: _templateOpen ? AppButtonVariant.secondary : AppButtonVariant.ghost, icon: c.savedTemplate != null ? Icons.bookmark : Icons.bookmark_border, onPressed: () => setState(() => _templateOpen = !_templateOpen)),
        ]),
        if (_reading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_templateOpen) _templateBox(types),
        if (_error.isNotEmpty && _drafts.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: InfoBox(_error)),
        if (_drafts.isNotEmpty) ..._previewSection(types),
      ]),
    );
  }

  Widget _photoRow(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          InkWell(
            key: const ValueKey('photo-thumb'),
            borderRadius: BorderRadius.circular(8),
            onTap: _zoomPhoto,
            child: Tooltip(
              message: 'Bấm để xem ảnh lớn',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_photoPath!), width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72, child: Icon(Icons.image_outlined))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_reading ? 'Đang đọc ảnh...' : 'Văn bản đọc từ ảnh đã đưa vào ô trên.', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
              Wrap(children: [
                AppButton(label: 'Xem ảnh', variant: AppButtonVariant.ghost, onPressed: _zoomPhoto),
                AppButton(label: 'Xoá ảnh', variant: AppButtonVariant.ghost, onPressed: _reading ? null : _clearPhoto),
              ]),
            ]),
          ),
        ]),
      );

  Widget _templateBox(List<String> types) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Mô tả cách khách này hay viết để phân tích đúng hơn. Mẫu chỉ được lưu khi bạn bấm Lưu mẫu, hệ thống không tự học thêm.', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
        const SizedBox(height: 10),
        AppDropdown<String>(
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
          AppButton(label: 'Lưu mẫu cho ${c.selectedName}', variant: AppButtonVariant.secondary, onPressed: c.selectedName.isEmpty ? null : _saveTemplate),
          if (c.savedTemplate != null)
            AppButton(label: 'Xoá mẫu', variant: AppButtonVariant.ghost, onPressed: () async {
                final msg = await c.deleteTemplate();
                if (mounted) setState(() => _templateMsg = msg);
              }),
        ]),
        if (_templateMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_templateMsg, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  List<Widget> _previewSection(List<String> types) {
    final uncertain = _drafts.where((d) => d.uncertain).length;
    return [
      const SizedBox(height: 14),
      Text(
        'Đã chọn ${_picked.length}/${_drafts.length} dòng${uncertain > 0 ? ', $uncertain dòng chưa chắc chắn (tô vàng)' : ''}.',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      for (final d in _drafts) _previewRow(d, types),
      if (_ignored.isNotEmpty) Text('Bỏ qua ${_ignored.length} dòng không có số: ${_ignored.join(' / ')}', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
      const SizedBox(height: 10),
      // Next to the save button: above the preview list the notice was off screen when the person pressed save.
      if (_error.isNotEmpty) ScrollIntoView(key: ValueKey('quick-err-$_error'), child: InfoBox(_error)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppButton(label: 'Xác nhận và lưu ${_picked.length} dòng', variant: AppButtonVariant.primary, loading: _saving, onPressed: _saving || !c.canAdd || _picked.isEmpty ? null : _save),
        AppButton(label: 'Đưa vào bảng nhập để sửa', variant: AppButtonVariant.secondary, onPressed: _picked.isEmpty ? null : _toForm),
        AppButton(label: 'Bỏ xem trước', variant: AppButtonVariant.ghost, onPressed: () => setState(() {
            _setDrafts(const []);
            _ignored = [];
            _error = '';
          })),
      ]),
    ];
  }

  // keeps the "Số" field (and its focus) when a line switches between the one-line and the stacked layout while typing
  final Map<Object, GlobalKey> _valueKeys = {};

  /// Hạng mục, Số and Điểm of one preview line. A xiên with 3+ numbers puts "Số" on its own full-width line so every number shows.
  Widget _previewFields(RowDraft d, List<String> typeList) {
    final stacked = valueFieldFlex(d.value.text) > 3;
    final type = AppDropdown<String>(
      initialValue: d.type,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: [for (final t in typeList) DropdownMenuItem(value: t, child: Text(betTypeLabel(t), overflow: TextOverflow.ellipsis))],
      onChanged: (v) => setState(() => d.type = v ?? d.type),
    );
    final value = TextField(key: _valueKeys.putIfAbsent(d, () => GlobalKey()), controller: d.value, keyboardType: kNumbersKeyboard, inputFormatters: kNumberCharsOnly, decoration: const InputDecoration(isDense: true, hintText: 'Số'), onChanged: (_) => setState(() {}));
    final score = SizedBox(width: 72, child: TextField(controller: d.score, keyboardType: kNumbersKeyboard, inputFormatters: kNumberCharsOnly, decoration: const InputDecoration(isDense: true, hintText: 'Điểm'), onChanged: (_) => setState(() {})));
    final tick = Checkbox(value: d.selected, onChanged: (v) => setState(() => d.selected = v ?? false));
    if (stacked) {
      return Column(children: [
        Row(children: [tick, Expanded(child: type), const SizedBox(width: 6), score]),
        Padding(padding: const EdgeInsets.only(left: 48, bottom: 4), child: value),
      ]);
    }
    return Row(children: [
      tick,
      Expanded(flex: 4, child: type),
      const SizedBox(width: 6),
      Expanded(flex: valueFieldFlex(d.value.text), child: value),
      const SizedBox(width: 6),
      score,
    ]);
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
        _previewFields(d, typeList),
        if (warn)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
            child: Text('Chưa chắc chắn: ${d.reasons.join('; ')}${d.raw.isNotEmpty ? ' (dòng gốc: ${d.raw})' : ''}', style: const TextStyle(fontSize: 12.5)),
          ),
      ]),
    );
  }
}
