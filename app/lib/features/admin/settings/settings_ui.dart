import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';

/// Shared bits for the payments / notices / settings admin screens.

/// User-facing message of an error ([ApiError] already carries a Vietnamese one).
String errText(Object e, String fallback) => e is ApiError ? e.message : fallback;

/// Row of pill buttons (one selected).
class PillBar<T> extends StatelessWidget {
  const PillBar({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [for (final it in items) ChoiceChip(key: ValueKey('pill-${it.$1}'), label: Text(it.$2), selected: it.$1 == value, showCheckmark: false, onSelected: (_) => onChanged(it.$1))],
  );
}

/// Inline error / success banner.
class Banner2 extends StatelessWidget {
  const Banner2(this.text, {super.key, this.error = true});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = error ? context.badColor : context.okColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: c)),
    );
  }
}

/// Centered empty / loading placeholder inside a list.
class Placeholder2 extends StatelessWidget {
  const Placeholder2(this.text, {super.key, this.busy = false});
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: busy
          ? const CircularProgressIndicator()
          : Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mutedColor),
            ),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, required String confirmText, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.badColor) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Writes [bytes] to the temp folder and opens the system share sheet (save to Files / Drive / send).
Future<void> saveAndShareFile(Uint8List bytes, String filename, {String? mime}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(f.path, mimeType: mime, name: filename)],
      subject: filename,
    ),
  );
}

/// Section card with a title.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children, this.subtitle});
  final String? title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: TextStyle(color: context.mutedColor, fontSize: 13)),
            ),
          if (title != null) const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

/// Generic edit-mode bookkeeping for "display-only, Sửa, Huỷ/Lưu" forms: remembers the saved snapshot so
/// Huỷ restores it and [dirty] says whether Lưu is worth enabling.
class EditSession<T> {
  EditSession(T initial) : _saved = initial;
  T _saved;
  bool editing = false;
  T get saved => _saved;

  void begin() => editing = true;

  /// Leaves edit mode; returns the snapshot the form must be reset to.
  T cancel() {
    editing = false;
    return _saved;
  }

  /// A successful save: [value] becomes the new snapshot and edit mode ends.
  void commit(T value) {
    _saved = value;
    editing = false;
  }

  /// Server data reloaded: new snapshot, edit mode unchanged unless [leave].
  void reset(T value, {bool leave = true}) {
    _saved = value;
    if (leave) editing = false;
  }

  bool dirty(T current) => current != _saved;
}
