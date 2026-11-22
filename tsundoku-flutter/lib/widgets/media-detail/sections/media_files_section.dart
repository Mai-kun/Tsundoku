/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/MediaFilesSection.svelte`.
///
/// Вложения тайтла: прикрепление (file-picker за фасадом), открытие в
/// системной программе, скачивание (saveFile-фасад), удаление через
/// confirmDialog. Drag&drop-зона ⏭️ (фасад дропа — долг, решение #51).
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/platform/platform.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../../../shared/ui/confirm_dialog.dart';
import '../../../shared/ui/toast.dart';

/// Файловая секция (1-в-1 с MediaFilesSection.svelte).
class MediaFilesSection extends ConsumerStatefulWidget {
  final String mediaId;
  final List<MediaAttachment> attachments;

  /// После мутации — родитель перечитывает карточку.
  final void Function()? onChanged;

  const MediaFilesSection({
    super.key,
    required this.mediaId,
    required this.attachments,
    this.onChanged,
  });

  @override
  ConsumerState<MediaFilesSection> createState() => _MediaFilesSectionState();
}

class _MediaFilesSectionState extends ConsumerState<MediaFilesSection> {
  bool _uploading = false;
  String? _busyId;
  bool _isDragging = false;

  // BOOK_FILE_RE / ARCHIVE_RE / DOCUMENT_RE — 1-в-1 с <script module>.
  static final RegExp _bookFileRe =
      RegExp(r'\.(epub|fb2|fb2\.zip|mobi|azw3?|djvu?)$', caseSensitive: false);
  static final RegExp _archiveRe =
      RegExp(r'\.(zip|rar|7z|cbz|cbr|tar|gz)$', caseSensitive: false);
  static final RegExp _documentRe =
      RegExp(r'\.(pdf|docx?|odt|rtf|txt)$', caseSensitive: false);

  IconData _iconFor(String name) {
    if (_bookFileRe.hasMatch(name)) return LucideIcons.bookOpen;
    if (_archiveRe.hasMatch(name)) return LucideIcons.archive;
    if (_documentRe.hasMatch(name)) return LucideIcons.fileText;
    return LucideIcons.paperclip;
  }

  Future<void> _upload({String? name, List<int>? bytes}) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await ref
          .read(apiClientProvider)
          .attachMediaFile(widget.mediaId, Uint8List.fromList(bytes ?? []),
              fileName: name ?? 'file');
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.filesAttached'),
          description: t.tr('toast.descCreated'),
        ),
      );
      widget.onChanged?.call();
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.filesAttachFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await platformService.pickFile();
    if (picked == null) return;
    await _upload(name: picked.name, bytes: picked.bytes);
  }

  Future<void> _open(MediaAttachment attachment) async {
    if (_busyId != null) return;
    setState(() => _busyId = attachment.id);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await ref
          .read(apiClientProvider)
          .openMediaFile(widget.mediaId, attachment.id);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.filesOpened'),
          description: t.tr('toast.descOpened'),
        ),
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.filesOpenFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _download(MediaAttachment attachment) async {
    // Браузерный anchor download в Svelte; во Flutter: байты через dio →
    // saveFile-фасад (Content-Disposition не нужен — имя приходит в
    // attachment.fileName).
    final bytes = await ref
        .read(apiClientProvider)
        .downloadMediaFile(widget.mediaId, attachment.id);
    await platformService.saveFile(
      suggestedName: attachment.fileName,
      bytes: bytes,
    );
  }

  Future<void> _remove(MediaAttachment attachment) async {
    if (_busyId != null) return;
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    if (!(await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-media-file',
        title: t.tf('detail.filesDeleteConfirm', [attachment.fileName]),
        confirmLabel: ref.read(tProvider).tr('common.delete'),
        danger: true,
      ),
    ))) {
      return;
    }
    setState(() => _busyId = attachment.id);
    try {
      await ref
          .read(apiClientProvider)
          .detachMediaFile(widget.mediaId, attachment.id);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.filesDeleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );
      widget.onChanged?.call();
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.filesDeleteFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return PlatformDropZone(
      enabled: !_uploading,
      onHoverChanged: (hovering) => setState(() => _isDragging = hovering),
      onFilesDropped: (files) async {
        for (final file in files) {
          await _upload(name: file.name, bytes: file.bytes);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20), // p-5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(
            color: _isDragging
                ? th.accentSoft
                : Colors.white.withAlpha(15), // /[0.06]
          ),
          color: _isDragging ? th.bgCard : th.bgSurface, // panel-line
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.paperclip,
                  size: 16, color: th.accentSoft), // text-accent-soft
              const SizedBox(width: 8), // gap-2
              Expanded(
                child: Text(
                  t.tr('detail.filesTitle'),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: 0.6, // tracking-wider
                    color: Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
              ),
              if (widget.attachments.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2), // px-2 py-0.5
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999), // rounded-full
                    color: Colors.white.withAlpha(26), // bg-white/10
                  ),
                  child: Text(
                    '${widget.attachments.length}',
                    style: const TextStyle(
                      fontSize: 10, // text-[10px]
                      fontWeight: FontWeight.w700, // font-bold
                      color: Color(0xFFCBD5E1), // text-slate-300
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              _AttachButton(
                uploading: _uploading,
                label: t.tr('detail.filesAttach'),
                th: th,
                onTap: _pickAndUpload,
              ),
            ],
          ),
          const SizedBox(height: 12), // space-y-3
          if (widget.attachments.isEmpty)
            Text(
              t.tr('detail.filesEmpty'),
              style: TextStyle(
                fontSize: 14, // text-sm
                color: th.textMuted, // text-muted
              ),
            )
          else
            Column(
              children: [
                for (final attachment in widget.attachments)
                  _FileRow(
                    attachment: attachment,
                    th: th,
                    busy: _busyId == attachment.id,
                    openLabel: t.tr('detail.filesOpen'),
                    downloadLabel: t.tr('detail.filesDownload'),
                    deleteLabel: t.tr('detail.filesDelete'),
                    icon: _iconFor(attachment.fileName),
                    sizeText: t.tf('detail.filesSize', [attachment.fileSizeBytes]),
                    onOpen: () => _open(attachment),
                    onDownload: () => _download(attachment),
                    onDelete: () => _remove(attachment),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
  }
}

/// Кнопка прикрепления: size-8, спиннер при загрузке.
class _AttachButton extends StatefulWidget {
  final bool uploading;
  final String label;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _AttachButton({
    required this.uploading,
    required this.label,
    required this.th,
    required this.onTap,
  });

  @override
  State<_AttachButton> createState() => _AttachButtonState();
}

class _AttachButtonState extends State<_AttachButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.uploading ? null : widget.onTap,
            child: Container(
              width: 32, // size-8
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                  color: _hovered
                      ? widget.th.accent // hover:border-accent
                      : Colors.white.withAlpha(26), // border-white/10
                ),
                color: _hovered
                    ? widget.th.accent.withAlpha(51) // hover:bg-accent/20
                    : Colors.white.withAlpha(13), // bg-white/5
              ),
              child: Center(
                child: widget.uploading
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFCBD5E1)),
                      )
                    : Icon(
                        LucideIcons.plus,
                        size: 16,
                        color: _hovered
                            ? Colors.white // hover:text-white
                            : const Color(0xFFCBD5E1), // text-slate-300
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка вложения: иконка по расширению, имя/размер, open/download/delete.
class _FileRow extends StatefulWidget {
  final MediaAttachment attachment;
  final TsundokuTheme th;
  final bool busy;
  final String openLabel;
  final String downloadLabel;
  final String deleteLabel;
  final IconData icon;
  final String sizeText;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _FileRow({
    required this.attachment,
    required this.th,
    required this.busy,
    required this.openLabel,
    required this.downloadLabel,
    required this.deleteLabel,
    required this.icon,
    required this.sizeText,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8), // space-y-2
        padding: const EdgeInsets.all(12), // p-3
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(
            color: _hovered
                ? Colors.white.withAlpha(26) // hover:border-white/10
                : Colors.white.withAlpha(13), // border-white/5
          ),
          color: const Color(0xFF151A26), // bg-[#151a26]
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 16, color: th.accentSoft),
            const SizedBox(width: 12), // gap-3
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w500, // font-medium
                      color: Color(0xFFE2E8F0), // text-slate-200
                    ),
                  ),
                  Text(
                    widget.sizeText,
                    style: const TextStyle(
                      fontSize: 11, // text-[11px]
                      color: Color(0xFF94A3B8), // text-slate-400
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _FileIconButton(
              icon: widget.busy
                  ? null // спиннер
                  : LucideIcons.eye,
              busy: widget.busy,
              tooltip: widget.openLabel,
              th: th,
              onTap: widget.busy ? null : widget.onOpen,
            ),
            const SizedBox(width: 6), // gap-1.5
            _FileIconButton(
              icon: LucideIcons.download,
              busy: false,
              tooltip: widget.downloadLabel,
              th: th,
              onTap: widget.onDownload,
            ),
            const SizedBox(width: 6),
            _FileIconButton(
              icon: LucideIcons.trash2,
              busy: widget.busy,
              tooltip: widget.deleteLabel,
              danger: true,
              th: th,
              onTap: widget.busy ? null : widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Иконочная кнопка вложения: size-8, border-white/5, danger-вариант.
class _FileIconButton extends StatefulWidget {
  final IconData? icon; // null → busy-спиннер
  final bool busy;
  final String tooltip;
  final bool danger;
  final TsundokuTheme th;
  final VoidCallback? onTap;

  const _FileIconButton({
    required this.icon,
    required this.busy,
    required this.tooltip,
    required this.th,
    this.danger = false,
    required this.onTap,
  });

  @override
  State<_FileIconButton> createState() => _FileIconButtonState();
}

class _FileIconButtonState extends State<_FileIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 32, // size-8
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                  color: widget.danger && _hovered
                      ? const Color(0x33F43F5E) // hover:border-rose-500/20
                      : Colors.white.withAlpha(13), // border-white/5
                ),
                color: _hovered
                    ? (widget.danger
                        ? const Color(0x1AF43F5E) // hover:bg-rose-500/10
                        : Colors.white.withAlpha(26)) // hover:bg-white/10
                    : Colors.white.withAlpha(8), // bg-white/[0.03]
              ),
              child: Center(
                child: widget.busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF94A3B8)),
                      )
                    : Icon(
                        widget.icon,
                        size: 14,
                        color: widget.danger
                            ? const Color(0xFFF87171) // text-rose-400
                            : _hovered
                                ? Colors.white // hover:text-white
                                : const Color(0xFF94A3B8), // text-slate-400
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
