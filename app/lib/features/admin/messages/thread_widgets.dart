import 'dart:typed_data';
import '../../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../friends/chat_models.dart' show imageOnlyMessage, maxAttachmentBytes, sniffImageType;
import '../../friends/image_scrub.dart';
import 'admin_messages_logic.dart';

/// Pieces shared by the Admin's thread page and the customer's "Hỗ trợ từ Admin" page (same thread, two sides).

/// Picks a picture, checks type and size and strips its metadata. Null when the user cancelled; throws [Exception]
/// with a Vietnamese message when the file is not usable.
Future<Uint8List?> pickScrubbedImage(ImageSource source) async {
  final x = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
  if (x == null) return null;
  final raw = await x.readAsBytes();
  if (raw.isEmpty) throw Exception('Tệp trống');
  if (sniffImageType(raw) == null) throw Exception(imageOnlyMessage);
  final clean = await scrubImage(raw);
  if (clean.bytes.length > maxAttachmentBytes) throw Exception('Tệp quá lớn (tối đa 25 MB)');
  return clean.bytes;
}

class DayDivider extends StatelessWidget {
  const DayDivider(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}


/// One message bubble. [mine] puts it on the right in the accent colour; [attachmentPath] is the API path of its picture.
class ThreadBubble extends StatelessWidget {
  const ThreadBubble({super.key, required this.msg, required this.mine, required this.attachmentPath, this.senderLabel, this.onDelete});
  final AdminMsg msg;
  final bool mine;
  final String attachmentPath;
  final String? senderLabel;

  /// When set (the admin's thread) a small trash button sits beside the time and deletes this message.
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = mine ? cs.primary : cs.surfaceContainerHighest;
    final fg = mine ? Colors.white : cs.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (senderLabel != null) Text(senderLabel!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: mine ? fg : cs.primary)),
              if (msg.content.isNotEmpty) SelectableText(msg.content, style: TextStyle(color: fg)),
              if (msg.attachment != null) ...[
                if (msg.content.isNotEmpty) const SizedBox(height: 6),
                AttachmentView(att: msg.attachment!, path: attachmentPath, color: fg),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(timeLabel(msg.createdAt), style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
              if (onDelete != null)
                InkResponse(
                  key: const Key('delete-message'),
                  onTap: onDelete,
                  radius: 18,
                  child: Padding(padding: const EdgeInsets.fromLTRB(10, 4, 4, 4), child: SvgIcon(AppSvg.delete, size: 14, color: Brand.danger)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The message box at the bottom of a thread: error line, picture waiting to be sent, picture button, field, send.
class ThreadComposer extends StatelessWidget {
  const ThreadComposer({super.key, required this.draft, required this.pending, required this.sending, required this.error, required this.hint, required this.onPick, required this.onRemovePending, required this.onSend, this.maxLength});
  final TextEditingController draft;
  final int? maxLength;
  final Uint8List? pending;
  final bool sending;
  final String? error;
  final String hint;
  final VoidCallback onPick;
  final VoidCallback onRemovePending;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: ListenableBuilder(
        listenable: draft,
        builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
          if (error != null) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 6, bottom: 4), child: Text(error!, style: TextStyle(color: cs.error, fontSize: 13)))),
          if (pending != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Stack(children: [
                Padding(padding: const EdgeInsets.all(6), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(pending!, height: 72, fit: BoxFit.cover))),
                Positioned(right: 0, top: 0, child: InkWell(onTap: onRemovePending, child: CircleAvatar(radius: 11, backgroundColor: cs.error, child: const SvgIcon(AppSvg.close, size: 14, color: Colors.white)))),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(tooltip: 'Gửi ảnh (JPG, PNG, WebP)', onPressed: sending ? null : onPick, icon: const SvgIcon(AppSvg.photoAdd)),
            Expanded(
              child: TextField(
                controller: draft,
                enabled: !sending,
                minLines: 1,
                maxLines: 5,
                maxLength: maxLength,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: hint, isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Gửi',
              onPressed: sending || (draft.text.trim().isEmpty && pending == null) ? null : onSend,
              icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const SvgIcon(AppSvg.send),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// An attachment inside a bubble: images are fetched with the session token (ApiClient.blob) and shown from memory;
/// tap opens full size. Other types (the server only accepts pictures) show name and size.
class AttachmentView extends StatefulWidget {
  const AttachmentView({super.key, required this.att, required this.path, this.color});
  final MsgAttachment att;
  final String path;
  final Color? color;
  @override
  State<AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<AttachmentView> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.att.isImage) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _failed = false);
    try {
      final b = await context.read<ApiClient>().blob(widget.path);
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.att;
    if (a.isImage && _bytes != null) {
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(children: [
              Center(child: InteractiveViewer(child: Image.memory(_bytes!))),
              SafeArea(child: IconButton(color: Colors.white, icon: const SvgIcon(AppSvg.close), onPressed: () => Navigator.of(context).pop())),
            ]),
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_bytes!, width: 220, fit: BoxFit.cover, semanticLabel: a.name, errorBuilder: (_, _, _) => const SvgIcon(AppSvg.photoAdd))),
      );
    }
    if (a.isImage && !_failed) return const SizedBox(width: 220, height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    return InkWell(
      onTap: a.isImage ? _fetch : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SvgIcon(_failed ? AppSvg.alertCircle : AppSvg.attach, size: 18, color: _failed ? Brand.danger : widget.color),
        const SizedBox(width: 6),
        Flexible(child: Text(_failed ? 'Không tải được ảnh, chạm để thử lại' : '${a.name} (${formatSize(a.size)})', style: TextStyle(color: widget.color))),
      ]),
    );
  }
}
