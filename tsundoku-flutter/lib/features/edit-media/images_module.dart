/// Порт `mediatracker-ui/src/features/edit-media/modules/ImagesModule.svelte`.
///
/// Block 6 — управление обложками и изображениями. Без media id (новая
/// запись) — прямое поле cover-URL; для существующего тайтла — полное
/// управление через серверные эндпоинты: вставка URL (по одному на строку),
/// загрузка локальных файлов и выбор активной обложки. Каждый серверный
/// ответ возвращается через `onCoversChange` — превью синхронизирует
/// вызывающий.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/cover_url.dart';
import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/platform/platform.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_image.dart';

class ImagesModule extends ConsumerStatefulWidget {
  final bool flat;
  final bool showLabel;

  /// null — новая запись (cover-URL едет прямо в payload).
  final String? mediaId;
  final String coverUrl;
  final ValueChanged<String>? onCoverUrlChange;

  /// Alt-текст превью: редактируемый тайтл.
  final String title;
  final List<MediaCoverItem> covers;
  final void Function(MediaDetail updated)? onCoversChange;

  const ImagesModule({
    super.key,
    this.flat = false,
    this.showLabel = true,
    required this.mediaId,
    required this.coverUrl,
    required this.onCoverUrlChange,
    required this.title,
    required this.covers,
    required this.onCoversChange,
  });

  @override
  ConsumerState<ImagesModule> createState() => _ImagesModuleState();
}

class _ImagesModuleState extends ConsumerState<ImagesModule> {
  bool _busy = false;
  String? _actionId;
  Object? _error;
  final TextEditingController _urlDraft = TextEditingController();
  bool _setAsActive = true;

  @override
  void initState() {
    super.initState();
    // Реактивный disabled-state кнопки добавления (в т.ч. для enterText
    // из тестов — onChanged у TextField не вызывается при программной
    // правке контроллера).
    _urlDraft.addListener(() {
      if (mounted) setState(() {});
    });
  }

  List<String> _splitUrls(String raw) => raw
      .split('\n')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  int get _urlDraftCount => _splitUrls(_urlDraft.text).length;

  Future<void> _addUrls() async {
    final urls = _splitUrls(_urlDraft.text).where(isValidCoverUrl).toList();
    final mediaId = widget.mediaId;
    if (mediaId == null || urls.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      MediaDetail? updated;
      for (final url in urls) {
        updated = await ref.read(apiClientProvider).addCoverByUrl(
            mediaId,
            url,
            source: null,
            setAsActive: _setAsActive,
          );
      }
      if (updated != null) {
        widget.onCoverUrlChange?.call(updated.coverUrl ?? widget.coverUrl);
        widget.onCoversChange?.call(updated);
      }
      _urlDraft.clear();
    } catch (err) {
      setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadFile(dynamic bytes, String name) async {
    final mediaId = widget.mediaId;
    if (mediaId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      MediaDetail? updated;
      updated = await ref.read(apiClientProvider).addCoverByFile(
            mediaId,
            bytes,
            fileName: name,
            source: null,
            setAsActive: _setAsActive,
          );
      widget.onCoverUrlChange?.call(updated.coverUrl ?? widget.coverUrl);
      widget.onCoversChange?.call(updated);
    } catch (err) {
      setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadFiles() async {
    final picked = await platformService.pickFile();
    if (picked == null) return;
    await _uploadFile(picked.bytes, picked.name);
  }

  Future<void> _handleSelect(MediaCoverItem cover) async {
    final mediaId = widget.mediaId;
    if (mediaId == null || _busy) return;
    setState(() {
      _busy = true;
      _actionId = cover.id;
      _error = null;
    });
    try {
      final updated =
          await ref.read(apiClientProvider).selectCover(mediaId, cover.id);
      widget.onCoverUrlChange?.call(updated.coverUrl ?? widget.coverUrl);
      widget.onCoversChange?.call(updated);
    } catch (err) {
      setState(() => _error = err);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionId = null;
        });
      }
    }
  }

  Future<void> _handleDelete(MediaCoverItem cover) async {
    final mediaId = widget.mediaId;
    if (mediaId == null || _busy) return;
    setState(() {
      _busy = true;
      _actionId = cover.id;
      _error = null;
    });
    try {
      final updated =
          await ref.read(apiClientProvider).deleteCover(mediaId, cover.id);
      widget.onCoversChange?.call(updated);
    } catch (err) {
      setState(() => _error = err);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionId = null;
        });
      }
    }
  }

  bool _isActiveCover(MediaCoverItem cover) {
    if (widget.coverUrl.isEmpty) return false;
    String strip(String url) => url.split('?').first;
    return strip(widget.coverUrl) == strip(cover.thumbUrl) ||
        widget.coverUrl.contains(cover.id);
  }

  @override
  void dispose() {
    _urlDraft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    return ModuleCard(
      flat: widget.flat,
      showLabel: widget.showLabel,
      title: t.tr('createModal.modules.images'),
      count: widget.mediaId != null ? widget.covers.length : null,
      icon: const Icon(LucideIcons.image, size: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.mediaId == null) ...[
            // Новая запись: обложка едет в payload как простой URL.
            Text(
              t.tr('createModal.fields.coverUrl'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: th.textPrimary,
              ),
            ),
            const SizedBox(height: 6), // space-y-1.5
            CreateTextField(
              value: widget.coverUrl,
              hint: t.tr('coversModal.urlPlaceholder'),
              onChange: (v) => widget.onCoverUrlChange?.call(v),
            ),
            const SizedBox(height: 12),
            Text(
              t.tr('createModal.imagesModule.createModeHint'),
              style: TextStyle(
                fontSize: 12, // text-xs
                color: th.textMuted.withAlpha(178), // text-muted/70
              ),
            ),
          ] else ...[
            // Существующая запись: полный менеджмент обложек.
            Text(
              t.tr('coversModal.addByUrl'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: th.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _urlDraft,
              maxLines: 2,
              minLines: 2,
              onChanged: (_) => setState(() {}),
              style: createFieldTextStyle(th),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: th.bgSurface, // bg-field
                contentPadding: const EdgeInsets.all(10), // p-2.5
                border: createFieldBorder(th),
                enabledBorder: createFieldBorder(th),
                focusedBorder: createFieldBorder(th, focused: true),
                hintText: t.tr('createModal.imagesModule.multiUrlsPlaceholder'),
                hintStyle: TextStyle(color: th.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Чекбокс «Сделать активной».
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _setAsActive = !_setAsActive),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14, // h-3.5 w-3.5
                        height: 14,
                        child: Checkbox(
                          value: _setAsActive,
                          onChanged: (v) =>
                              setState(() => _setAsActive = v ?? true),
                          activeColor: th.accent,
                        ),
                      ),
                      const SizedBox(width: 8), // gap-2
                      Text(
                        t.tr('coversModal.setAsActive'),
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Кнопка «Добавить обложку (N)».
                GestureDetector(
                  onTap: _busy || _urlDraftCount == 0 ? null : _addUrls,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6), // px-3 py-1.5
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: _busy || _urlDraftCount == 0
                          ? th.accent.withAlpha(128)
                          : th.accent,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_busy) ...[
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4), // mr-1
                        ],
                        Text(
                          _urlDraftCount > 1
                              ? '${t.tr('coversModal.addCover')} ($_urlDraftCount)'
                              : t.tr('coversModal.addCover'),
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Дроп-зона загрузки (drop / клик → pickFile).
            PlatformDropZone(
              enabled: !_busy,
              onFilesDropped: (files) async {
                for (final file in files) {
                  await _uploadFile(file.bytes, file.name);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : _uploadFiles,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 16), // px-3 py-4
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withAlpha(26)), // border-white/10
                  ),
                  child: Column(
                    children: [
                      Icon(LucideIcons.upload, size: 16, color: th.textMuted),
                      const SizedBox(height: 6), // gap-1.5
                      Text(
                        t.tr('createModal.imagesModule.dropHere'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  errorMessage(_error!, ref.read(i18nProvider)),
                  style: const TextStyle(
                    fontSize: 12, // text-xs
                    color: Color(0xFFFDA4AF), // text-rose-300
                  ),
                ),
              ),
            if (widget.covers.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Сетка 3/4 колонки (grid-cols-3 sm:4 → ширина окна).
              LayoutBuilder(builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 640 ? 4 : 3; // sm:grid-cols-4
                final gap = 8.0; // gap-2
                final tileWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final cover in widget.covers)
                      _CoverTile(
                        cover: cover,
                        title: widget.title,
                        active: _isActiveCover(cover),
                        busy: _busy,
                        actionId: _actionId,
                        width: tileWidth,
                        onSelect: () => _handleSelect(cover),
                        onDelete: () => _handleDelete(cover),
                        t: t,
                      ),
                  ],
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

/// Плитка обложки: aspect 2/3, active — emerald border + бейдж, select/delete.
class _CoverTile extends StatelessWidget {
  final MediaCoverItem cover;
  final String title;
  final bool active;
  final bool busy;
  final String? actionId;
  final double width;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final I18nDictionary t;

  const _CoverTile({
    required this.cover,
    required this.title,
    required this.active,
    required this.busy,
    required this.actionId,
    required this.width,
    required this.onSelect,
    required this.onDelete,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return SizedBox(
      width: width,
      height: width * 3 / 2, // aspect-[2/3]
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: active
                  ? const Color(0xCC10B981) // border-emerald-500/80
                  : Colors.white.withAlpha(26), // border-white/10
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Превью-картинка (thumbUrl через MediaCover — baseUrl-склейка
              // уже в провайдере покрывающем images; здесь сырой URL).
              TsundokuImage(
                imageUrl: cover.thumbUrl,
                fit: BoxFit.cover,
                errorWidget: Container(color: th.bgSurface),
              ),
              if (active)
                Positioned(
                  left: 4, // top-1 left-1
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2), // px-1 py-0.5
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: const Color(0xF2059669), // bg-emerald-600/95
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check,
                            size: 10,
                            color: Colors.white), // strokeWidth 3 ≈ bold
                        const SizedBox(width: 2), // gap-0.5
                        Text(
                          t.tr('coversModal.activeBadge'),
                          style: const TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Выбор активной обложки.
                Tooltip(
                  message: t.tr('coversModal.select'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: busy ? null : onSelect,
                    child: Container(
                      color: busy && actionId == cover.id
                          ? Colors.black.withAlpha(102) // group-hover:bg-black/40
                          : Colors.transparent,
                      alignment: Alignment.center,
                      child: busy && actionId == cover.id
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              // Кнопка удаления (top-1 right-1, size-6).
              Positioned(
                right: 4,
                top: 4,
                child: _CoverDeleteButton(
                  busy: busy,
                  tooltip: t.tr('coversModal.delete'),
                  onDelete: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverDeleteButton extends StatefulWidget {
  final bool busy;
  final String tooltip;
  final VoidCallback onDelete;

  const _CoverDeleteButton({
    required this.busy,
    required this.tooltip,
    required this.onDelete,
  });

  @override
  State<_CoverDeleteButton> createState() => _CoverDeleteButtonState();
}

class _CoverDeleteButtonState extends State<_CoverDeleteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.busy ? null : widget.onDelete,
          child: Container(
            width: 24, // size-6
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              border: Border.all(color: Colors.white.withAlpha(51)), // border-white/20
              color: Colors.black.withAlpha(179), // bg-black/70
            ),
            alignment: Alignment.center,
            child: Icon(
              LucideIcons.trash2,
              size: 12,
              color: _hovered
                  ? const Color(0xFFFDA4AF) // hover:text-rose-300
                  : const Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
        ),
      ),
    );
  }
}
