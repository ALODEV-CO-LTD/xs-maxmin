import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/admin_session.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'settings_appversion.dart';
import 'settings_backups.dart';
import 'settings_forms.dart';
import 'settings_logic.dart';
import 'settings_security.dart';
import 'settings_ui.dart';

/// Admin - Cài đặt. Body only (the admin shell draws the AppBar and drawer). Sections are pill buttons, shown per right:
/// settings.manage (Thanh toán, Giá gói, Giới hạn ID, Khoá khác), security.view, security.policy, backups.manage.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late final AdminSession _s = context.read<AdminSession>();
  late final bool _settings = _s.can('settings.manage');
  String? _tab;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _raw = {};
  int _epoch = 0; // bumped on pull-to-refresh so the sections reload

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_settings) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().get('/admin/settings');
      if (!mounted) return;
      setState(() {
        _raw = Map<String, dynamic>.from(res as Map);
        _epoch++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không thể tải cài đặt'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = settingsSections(
      settings: _settings,
      security: _s.can('security.view'),
      policy: _s.can('security.policy'),
      backups: _s.can('backups.manage'),
      hasOtherKeys: otherSettingKeys(_raw).isNotEmpty,
    );
    final tab = sections.any((x) => x.key == _tab) ? _tab! : (sections.isEmpty ? '' : sections.first.key);
    // The generic-store sections need /admin/settings; the others load themselves.
    final needsRaw = const {'payment', 'limits', 'other'}.contains(tab);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (sections.isEmpty)
            const Placeholder2('Tài khoản không có quyền cài đặt nào')
          else ...[
            PillBar<String>(items: [for (final x in sections) (x.key, x.label)], value: tab, onChanged: (v) => setState(() => _tab = v)),
            const SizedBox(height: 12),
            if (_error != null) Banner2(_error!),
            if (_loading && needsRaw) const Placeholder2('', busy: true) else KeyedSubtree(key: ValueKey('$tab-$_epoch'), child: _section(tab)),
          ],
        ],
      ),
    );
  }

  Widget _section(String tab) {
    switch (tab) {
      case 'payment':
        return BankSection(raw: _raw, onRaw: (r) => _raw = r);
      case 'limits':
        return MaxIdsSection(raw: _raw, onRaw: (r) => _raw = r);
      case 'prices':
        return const PackagesSection();
      case 'appversion':
        return const AppVersionSection();
      case 'security':
        return const SecurityEventsSection();
      case 'policy':
        return const SecurityPolicySection();
      case 'backups':
        return const BackupsSection();
      case 'other':
        final keys = otherSettingKeys(_raw);
        return SectionCard(
          title: 'Các khoá cài đặt khác',
          children: [
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(k, style: TextStyle(color: context.mutedColor, fontSize: 13)),
                    ),
                    Expanded(flex: 3, child: Text('${_raw[k]}')),
                  ],
                ),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
