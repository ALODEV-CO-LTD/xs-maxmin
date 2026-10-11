import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/app_version.dart';
import 'settings_ui.dart';

/// Phiên bản ứng dụng (A17): newest version, oldest version still allowed, download link, release notes.
/// Display-only until "Sửa" (then Huỷ / Lưu), like the other settings forms. `GET/PUT /admin/app-version`.
class AppVersionSection extends StatefulWidget {
  const AppVersionSection({super.key});
  @override
  State<AppVersionSection> createState() => _AppVersionSectionState();
}

class _AppVersionSectionState extends State<AppVersionSection> {
  final _latest = TextEditingController(), _min = TextEditingController(), _url = TextEditingController(), _notes = TextEditingController();
  late final EditSession<AppVersionInfo> _edit = EditSession(const AppVersionInfo());
  bool _loading = true, _saving = false, _saved = false;
  String? _error;

  AppVersionInfo get _form => AppVersionInfo(latest: _latest.text.trim(), min: _min.text.trim(), downloadUrl: _url.text.trim(), notes: _notes.text);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_latest, _min, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(AppVersionInfo v) {
    _latest.text = v.latest;
    _min.text = v.min;
    _url.text = v.downloadUrl;
    _notes.text = v.notes;
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().get('/admin/app-version');
      final v = AppVersionInfo.fromJson(Map<String, dynamic>.from(res as Map));
      if (!mounted) return;
      setState(() {
        _edit.reset(v);
        _fill(v);
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được cấu hình phiên bản'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final bad = validateAppVersionForm(_form);
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
      final res = await context.read<ApiClient>().put('/admin/app-version', _form.toBody());
      final v = AppVersionInfo.fromJson(Map<String, dynamic>.from(res as Map));
      if (!mounted) return;
      setState(() {
        _edit.commit(v);
        _fill(v);
        _saved = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không lưu được'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Placeholder2('', busy: true);
    final on = _edit.editing;
    return SectionCard(
      title: 'Phiên bản ứng dụng',
      subtitle: 'App hỏi thông tin này mỗi lần mở. Thấp hơn phiên bản mới nhất: nhắc cập nhật. Thấp hơn phiên bản tối thiểu: chặn dùng cho tới khi cập nhật. Để trống ô nào thì không áp dụng.',
      children: [
        if (_error != null) Banner2(_error!),
        if (_saved) const Banner2('Đã lưu phiên bản ứng dụng', error: false),
        TextField(controller: _latest, enabled: on, decoration: const InputDecoration(labelText: 'Phiên bản mới nhất', hintText: 'Ví dụ 1.3.0')),
        const SizedBox(height: 10),
        TextField(controller: _min, enabled: on, decoration: const InputDecoration(labelText: 'Phiên bản tối thiểu còn được dùng', hintText: 'Để trống nếu không chặn')),
        const SizedBox(height: 10),
        TextField(controller: _url, enabled: on, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Đường dẫn tải ứng dụng (https)', hintText: 'https://...')),
        const SizedBox(height: 10),
        TextField(controller: _notes, enabled: on, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Có gì mới', hintText: 'Hiện trong hộp nhắc cập nhật')),
        const SizedBox(height: 10),
        if (!on)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _edit.begin();
                _saved = false;
              }),
              child: const Text('Sửa'),
            ),
          )
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _fill(_edit.cancel());
                          _error = null;
                        }),
                child: const Text('Huỷ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton(onPressed: _saving || !_edit.dirty(_form) ? null : _save, child: Text(_saving ? 'Đang lưu...' : 'Lưu'))),
          ]),
      ],
    );
  }
}
