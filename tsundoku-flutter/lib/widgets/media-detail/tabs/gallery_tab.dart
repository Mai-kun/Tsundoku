/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/tabs/GalleryTab.svelte`.
///
/// Галерея скриншотов: загрузка (pick за фасадом; Ctrl+V-paste ⏭️ — window-
/// событие браузера, см. решение #52), светбокс, context-menu
/// (view/reveal/copy-image/copy-url/download/set-cover/delete), сетка 2/3/4.
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
import '../../../shared/ui/context_menu_controller.dart';
import '../../../shared/ui/lightbox.dart';
import '../../../shared/ui/toast.dart';

/// Скриншот в буфер: PNG-перекодирование при необходимости (Canvas ⏭️ —
/// decode→PNG-кадр делает dart:ui; если данные уже PNG — как есть).

/// Таб «Галерея» (1-в-1 с GalleryTab.svelte).
class GalleryTab extends ConsumerStatefulWidget {
  final String mediaId;
  final List<MediaGalleryItem> gallery;

  /// После мутации — родитель перечитывает карточку (и счётчик таба).
  final VoidCallback? onChanged;

  const GalleryTab({
    super.key,
    required this.mediaId,
    required this.gallery,
    this.onChanged,
  });

  @override
  ConsumerState<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<GalleryTab> {
  bool _uploading = false;
  String? _deletingId;

  static final RegExp _filenameExtRe = RegExp(r'\.[a-z0-9]+$', caseSensitive: false);

  Future<void> _upload({required String title, required Uint8List bytes}) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await ref
          .read(apiClientProvider)
          .uploadGalleryImage(widget.mediaId, bytes, title: title);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryScreenshotAdded'),
          description: t.tr('toast.descCreated'),
        ),
      );
      widget.onChanged?.call();
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryUploadFailed'),
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
    await _upload(title: picked.name, bytes: picked.bytes);
  }

  Future<void> _remove(MediaGalleryItem entry) async {
    if (_deletingId != null) return;
    final t = ref.read(tProvider);
    if (!(await confirmAction(
      ref,
      ConfirmRequest(
        key: 'delete-gallery-photo',
        title: t.tr('detail.galleryDeleteConfirm'),
        confirmLabel: t.tr('common.delete'),
        danger: true,
      ),
    ))) {
      return;
    }
    setState(() => _deletingId = entry.id);
    final locale = ref.read(i18nProvider);
    try {
      await ref
          .read(apiClientProvider)
          .deleteGalleryImage(widget.mediaId, entry.id);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryDeleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );
      widget.onChanged?.call();
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryDeleteFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _handleContextMenu(Offset position, MediaGalleryItem entry) {
    final t = ref.read(tProvider);
    openContextMenu(ref, position.dx, position.dy, [
      MenuItem(
        id: 'view',
        label: t.tr('detail.galleryViewFull'),
        icon: 'browser',
        action: () => ref
            .read(lightboxProvider.notifier)
            .openLightbox(entry.originalUrl),
      ),
      MenuItem(
        id: 'reveal',
        label: t.tr('detail.galleryReveal'),
        icon: 'folder',
        action: () => _reveal(entry),
      ),
      MenuItem(
        id: 'copy-image',
        label: t.tr('detail.galleryCopyImage'),
        icon: 'copy',
        action: () => _copyImage(entry),
      ),
      MenuItem(
        id: 'copy-url',
        label: t.tr('detail.galleryCopyUrl'),
        icon: 'link',
        action: () => _copyUrl(entry),
      ),
      MenuItem(
        id: 'download',
        label: t.tr('detail.galleryDownloadImage'),
        icon: 'download',
        action: () => _downloadImage(entry),
      ),
      MenuItem(
        id: 'set-cover',
        label: t.tr('detail.gallerySetCover'),
        icon: 'image',
        action: () => _setCover(entry),
      ),
      const MenuItem(id: 'sep', kind: 'separator'),
      MenuItem(
        id: 'delete',
        label: t.tr('detail.galleryDelete'),
        icon: 'delete',
        kind: 'danger',
        action: () => _remove(entry),
      ),
    ]);
  }

  /// Скриншоты живут на сервере: раскрыть папку в файловом менеджере.
  Future<void> _reveal(MediaGalleryItem entry) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await ref
          .read(apiClientProvider)
          .revealInExplorer('media/${widget.mediaId}/gallery/${entry.id}');
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryRevealFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    }
  }

  Future<void> _copyImage(MediaGalleryItem entry) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .downloadMediaFileBytes(entry.originalUrl);
      // Chromium кладёт на буфер только image/png — перекодирование через
      // dart:ui (Canvas-аналог #32); MediaFilesSection делает то же.
      await platformService.copyImagePng(bytes);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryImageCopied'),
          description: t.tr('toast.descCopied'),
        ),
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryCopyFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    }
  }

  Future<void> _copyUrl(MediaGalleryItem entry) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await platformService.copyText(entry.originalUrl);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryUrlCopied'),
          description: t.tr('toast.descCopied'),
        ),
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.galleryCopyFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    }
  }

  Future<void> _downloadImage(MediaGalleryItem entry) async {
    final name = entry.title != null &&
            _filenameExtRe.hasMatch(entry.title!)
        ? entry.title!
        : '${entry.title ?? 'screenshot'}.webp';
    final bytes = await ref
        .read(apiClientProvider)
        .downloadMediaFileBytes(entry.originalUrl);
    await platformService.saveFile(suggestedName: name, bytes: bytes);
  }

  Future<void> _setCover(MediaGalleryItem entry) async {
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      await ref
          .read(apiClientProvider)
          .setGalleryAsCover(widget.mediaId, entry.id);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.gallerySetCoverDone'),
          description: t.tr('toast.descSaved'),
        ),
      );
      // Сайдбар кэширует постер по URL: рефеч приносит cache-buster.
      widget.onChanged?.call();
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('detail.gallerySetCoverFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
          durationMs: 5000,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1024
        ? 4
        : width >= 640
            ? 3
            : 2;
    final gap = 12.0; // gap-3
    final cardWidth = ((width - 48 - gap * (columns - 1)) / columns)
        .clamp(120.0, 500.0);
    final cardHeight = cardWidth * 9 / 16; // aspect-video

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.tr('detail.galleryPasteHint'),
                style: TextStyle(
                  fontSize: 12, // text-xs
                  color: th.textMuted, // text-muted
                ),
              ),
            ),
            const SizedBox(width: 8), // gap-2
            _UploadButton(
              uploading: _uploading,
              uploadLabel: t.tr('detail.galleryUpload'),
              uploadingLabel: t.tr('detail.galleryUploading'),
              th: th,
              onTap: _pickAndUpload,
            ),
          ],
        ),
        const SizedBox(height: 16), // space-y-4
        if (widget.gallery.isEmpty)
          Container(
            padding: const EdgeInsets.all(40), // p-10
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12), // rounded-xl
              border: Border.all(
                  color: Colors.white
                      .withAlpha(26)), // border-dashed white/10 ⏭️
              color: th.bgSurface, // panel-line
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.image, size: 28, color: th.textMuted),
                const SizedBox(height: 8), // gap-2
                Text(
                  t.tr('detail.galleryEmpty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    color: th.textMuted, // text-muted
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final entry in widget.gallery)
                GestureDetector(
                  onTap: () => ref
                      .read(lightboxProvider.notifier)
                      .openLightbox(entry.originalUrl),
                  onSecondaryTapUp: (details) =>
                      _handleContextMenu(details.globalPosition, entry),
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12), // rounded-xl
                      border: Border.all(
                          color: Colors.white.withAlpha(15)), // /[0.06]
                      color: Colors.black.withAlpha(51), // bg-black/20
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Браузерный резолв /api/... от origin — явная
                        // склейка с baseUrl (решение #25).
                        Image.network(
                          '${ref.watch(apiBaseUrlProvider)}${entry.thumbUrl}',
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.black.withAlpha(51),
                          ),
                        ),
                        Positioned(
                          top: 8, // top-2
                          right: 8,
                          child: _DeleteOverlayButton(
                            entryId: entry.id,
                            deletingId: _deletingId,
                            deleteConfirmLabel:
                                t.tr('detail.galleryDeleteConfirm'),
                            th: th,
                            onTap: () => _remove(entry),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Кнопка загрузки: спиннер + «Загрузка…» / Upload + «Загрузить картинку».
class _UploadButton extends StatefulWidget {
  final bool uploading;
  final String uploadLabel;
  final String uploadingLabel;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _UploadButton({
    required this.uploading,
    required this.uploadLabel,
    required this.uploadingLabel,
    required this.th,
    required this.onTap,
  });

  @override
  State<_UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<_UploadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.uploading ? null : widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 4), // px-2.5 py-1
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(
              color: _hovered
                  ? const Color(0x806366F1) // hover:border-indigo-500/40
                  : Colors.white.withAlpha(26), // border-white/10
            ),
            color: Colors.white.withAlpha(10), // bg-white/[0.04]
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.uploading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFCBD5E1)),
                )
              else
                const Icon(LucideIcons.upload,
                    size: 14, color: Color(0xFFCBD5E1)), // text-slate-300
              const SizedBox(width: 6), // gap-1.5
              Text(
                widget.uploading
                    ? widget.uploadingLabel
                    : widget.uploadLabel,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: _hovered
                      ? Colors.white // hover:text-white
                      : const Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Delete-оверлей карточки: opacity-0 → group-hover.
class _DeleteOverlayButton extends StatefulWidget {
  final String entryId;
  final String? deletingId;
  final String deleteConfirmLabel;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _DeleteOverlayButton({
    required this.entryId,
    required this.deletingId,
    required this.deleteConfirmLabel,
    required this.th,
    required this.onTap,
  });

  @override
  State<_DeleteOverlayButton> createState() => _DeleteOverlayButtonState();
}

class _DeleteOverlayButtonState extends State<_DeleteOverlayButton> {
  bool _hovered = false;
  bool _parentHovered = false;

  @override
  Widget build(BuildContext context) {
    final busy = widget.deletingId == widget.entryId;
    return MouseRegion(
      onEnter: (_) => setState(() {
        _hovered = true;
        _parentHovered = true;
      }),
      onExit: (_) => setState(() {
        _hovered = false;
        _parentHovered = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: (_hovered || _parentHovered) ? 1.0 : 0.0, // group-hover
          child: Container(
            padding: const EdgeInsets.all(6), // p-1.5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
              border: Border.all(
                color: _hovered
                    ? const Color(0x80EF4444) // hover:border-red-500/50
                    : Colors.white.withAlpha(26), // border-white/10
              ),
              color: Colors.black.withAlpha(179), // bg-black/70
            ),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFE2E8F0)),
                  )
                : Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: _hovered
                        ? const Color(0xFFF87171) // hover:text-red-400
                        : const Color(0xFFE2E8F0), // text-slate-200
                  ),
          ),
        ),
      ),
    );
  }
}
