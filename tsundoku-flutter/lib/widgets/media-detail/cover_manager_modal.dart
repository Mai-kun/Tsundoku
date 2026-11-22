/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/CoverManagerModal.svelte`.
///
/// Управление обложками: добавление по URL/файлом (за фасадом §1.3), загрузка
/// обложек томов (manga), выбор активной, удаление с inline-подтверждением.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/cover_url.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/platform/platform.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/toast.dart';

// Tailwind-литералы (вне ThemeExtension — как в детальных секциях).
const Color _kIndigo600 = Color(0xFF4F46E5);
const Color _kIndigo500 = Color(0xFF6366F1);
const Color _kIndigo300 = Color(0xFFA5B4FC);
const Color _kEmerald500 = Color(0xFF10B981);
const Color _kEmerald600 = Color(0xFF059669);
const Color _kRose300 = Color(0xFFFDA4AF);
const Color _kRose600 = Color(0xFFE11D48);
const Color _kSlate300 = Color(0xFFCBD5E1);
const Color _kSlate400 = Color(0xFF94A3B8);
const Color _kSlate500 = Color(0xFF64748B);
const Color _kInputBg = Color(0xFF1C202B); // bg-[#1c202b]

enum _AddMode { url, file }

/// Модалка обложек (1-в-1 с CoverManagerModal.svelte).
class CoverManagerModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final MediaDetail media;
  final VoidCallback onClose;

  /// Родитель (MediaDetailView/App) подменяет detail на обновлённый.
  final void Function(MediaDetail updated) onUpdate;

  const CoverManagerModal({
    super.key,
    required this.isOpen,
    required this.media,
    required this.onClose,
    required this.onUpdate,
  });

  @override
  ConsumerState<CoverManagerModal> createState() => _CoverManagerModalState();
}

class _CoverManagerModalState extends ConsumerState<CoverManagerModal> {
  _AddMode _addMode = _AddMode.url;
  final TextEditingController _urlController = TextEditingController();
  ({String name, Uint8List bytes})? _selectedFile;
  bool _setAsActive = true;

  bool _busy = false;
  bool _fetchingVolumes = false;
  String? _actionId;
  Object? _error;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    // disabled={busy} на input'ах — пересборка на каждую букву URL.
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // isActiveCover: сравнение до query-string или вхождение id.
  bool _isActiveCover(MediaCoverItem cover) {
    final coverUrl = widget.media.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) return false;
    final cleanMedia = coverUrl.split('?')[0];
    final cleanCover = cover.thumbUrl.split('?')[0];
    return cleanMedia == cleanCover || cleanMedia.contains(cover.id);
  }

  Future<void> _addByUrl() async {
    final trimmed = _urlController.text.trim();
    if (trimmed.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = ref.read(tProvider);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .addCoverByUrl(widget.media.id, trimmed, setAsActive: _setAsActive);
      _urlController.clear();
      widget.onUpdate(updated);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('coversModal.coverAdded'),
          description: t.tr('toast.descCreated'),
        ),
      );
    } catch (err) {
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addByFile() async {
    final file = _selectedFile;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = ref.read(tProvider);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .addCoverByFile(widget.media.id, file.bytes,
              fileName: file.name, setAsActive: _setAsActive);
      setState(() => _selectedFile = null);
      widget.onUpdate(updated);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('coversModal.coverUploaded'),
          description: t.tr('toast.descCreated'),
        ),
      );
    } catch (err) {
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(String coverId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionId = coverId;
      _error = null;
    });
    final t = ref.read(tProvider);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .selectCover(widget.media.id, coverId);
      widget.onUpdate(updated);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('coversModal.coverSelected'),
          description: t.tr('toast.descSaved'),
        ),
      );
    } catch (err) {
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionId = null;
        });
      }
    }
  }

  Future<void> _delete(String coverId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionId = coverId;
      _error = null;
    });
    final t = ref.read(tProvider);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .deleteCover(widget.media.id, coverId);
      setState(() => _deletingId = null);
      widget.onUpdate(updated);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('coversModal.coverDeleted'),
          description: t.tr('toast.descDeleted'),
        ),
      );
    } catch (err) {
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionId = null;
        });
      }
    }
  }

  Future<void> _fetchVolumes() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _fetchingVolumes = true;
      _error = null;
    });
    final t = ref.read(tProvider);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .fetchVolumeCovers(widget.media.id);
      widget.onUpdate(updated);
      showToast(
        ref,
        ToastOptions(
          title: t.tr('coversModal.volumesLoaded'),
          description: t.tr('toast.descCreated'),
        ),
      );
    } catch (err) {
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _fetchingVolumes = false;
        });
      }
    }
  }

  /// `<img src>` в браузере резолвится от origin; абсолютные URL — как есть
  /// (решение #25).
  String _resolveImage(String src) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    return src.startsWith('/') ? '$baseUrl$src' : src;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final covers = widget.media.covers ?? const <MediaCoverItem>[];

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: widget.onClose,
      size: ModalSize.lg,
      child: ConstrainedBox(
        // max-h-[85vh]: панель сжимается под контент, но не выше 85vh.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        // stretch: блочные дочерние элементы CSS-колонки на всю ширину.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(t, th, covers),
            _buildAddSection(t, th),
            Flexible(child: _buildGallery(t, covers)),
          ],
        ),
      ),
    );
  }

  // ---- Header ----

  Widget _buildHeader(
      I18nDictionary t, TsundokuTheme th, List<MediaCoverItem> covers) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF)), // border-white/[0.08]
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(LucideIcons.image, size: 18, color: _kIndigo300), // accent-soft
          const SizedBox(width: 8), // gap-2
          Flexible(
            child: Text(
              t.tr('coversModal.title'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16, // text-base
                fontWeight: FontWeight.w700, // font-bold
                color: Colors.white,
              ),
            ),
          ),
          if (covers.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(26), // bg-white/10
                borderRadius: BorderRadius.circular(999), // rounded-full
              ),
              child: Text(
                '${covers.length}',
                style: const TextStyle(
                    fontSize: 12, color: _kSlate300), // text-xs text-slate-300
              ),
            ),
          ],
          const Spacer(),
          _HoverCloseButton(onClose: widget.onClose, label: t.tr('common.close')),
        ],
      ),
    );
  }

  // ---- Add cover section ----

  Widget _buildAddSection(I18nDictionary t, TsundokuTheme th) {
    final isManga = widget.media.type == MediaType.manga;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0x33000000), // bg-black/20
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF)), // border-white/[0.08]
        ),
      ),
      padding: const EdgeInsets.all(16), // p-4
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ряд 1: переключатель режима + manga-кнопка + setAsActive.
          Padding(
            padding: const EdgeInsets.only(bottom: 12), // pb-3
            child: Row(
              children: [
                Flexible(
                  child: Wrap(
                    spacing: 8, // gap-2
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2), // p-0.5
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.white.withAlpha(26)), // /10
                          color: Colors.white.withAlpha(13), // bg-white/5
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SegmentButton(
                              icon: LucideIcons.link2,
                              label: t.tr('coversModal.addByUrl'),
                              active: _addMode == _AddMode.url,
                              onTap: () => setState(() => _addMode = _AddMode.url),
                            ),
                            _SegmentButton(
                              icon: LucideIcons.upload,
                              label: t.tr('coversModal.uploadFile'),
                              active: _addMode == _AddMode.file,
                              onTap: () =>
                                  setState(() => _addMode = _AddMode.file),
                            ),
                          ],
                        ),
                      ),
                      if (isManga)
                        _FetchVolumesButton(
                          label: t.tr('coversModal.fetchVolumes'),
                          fetchingLabel: t.tr('coversModal.fetchingVolumes'),
                          busy: _busy,
                          fetching: _fetchingVolumes,
                          tooltip: t.tr('coversModal.fetchVolumes'),
                          onTap: () => unawaited(_fetchVolumes()),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12), // gap-3
                // setAsActive: чекбокс + подпись (text-xs text-slate-300).
                GestureDetector(
                  onTap: () => setState(() => _setAsActive = !_setAsActive),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: _setAsActive,
                          onChanged: (value) =>
                              setState(() => _setAsActive = value ?? true),
                          activeColor: _kIndigo600, // text-indigo-600
                          checkColor: Colors.white,
                          side: const BorderSide(
                            color: Color(0x33FFFFFF), // border-white/20
                            width: 1,
                          ),
                          // bg-white/10 в unchecked-состоянии.
                          fillColor: WidgetStateProperty.resolveWith((states) =>
                              states.contains(WidgetState.selected)
                                  ? _kIndigo600
                                  : Colors.white.withAlpha(26)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8), // gap-2
                      Text(
                        t.tr('coversModal.setAsActive'),
                        style: const TextStyle(
                            fontSize: 12, color: _kSlate300), // text-xs
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Ряд 2: форма добавления.
          if (_addMode == _AddMode.url) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36, // h-9
                    child: TextField(
                      controller: _urlController,
                      enabled: !_busy,
                      onSubmitted: (_) => unawaited(_addByUrl()),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white), // text-xs
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12), // px-3
                        hintText: t.tr('coversModal.urlPlaceholder'),
                        hintStyle: const TextStyle(color: _kSlate500),
                        filled: true,
                        fillColor: _kInputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), // rounded-lg
                          borderSide: BorderSide(
                              color: Colors.white.withAlpha(26)), // /10
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Colors.white.withAlpha(26)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: _kIndigo500
                                  .withAlpha(153)), // focus indigo-500/60
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8), // gap-2
                _AddSubmitButton(
                  label: t.tr('common.add'),
                  busyLabel: t.tr('coversModal.downloading'),
                  busy: _busy,
                  showSpinner: _busy && _actionId == null,
                  enabledIcon: LucideIcons.plus,
                  onTap: () => unawaited(_addByUrl()),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: PlatformDropZone(
                    enabled: !_busy,
                    onFilesDropped: (files) {
                      if (files.isNotEmpty && mounted) {
                        setState(() {
                          _selectedFile = (name: files.first.name, bytes: files.first.bytes);
                        });
                        unawaited(_addByFile());
                      }
                    },
                    child: _FileChooseField(
                      label:
                          _selectedFile?.name ?? t.tr('coversModal.chooseFile'),
                      busy: _busy,
                      onPick: () async {
                        final picked = await platformService.pickFile();
                        if (picked == null || !mounted) return;
                        setState(() => _selectedFile = picked);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _AddSubmitButton(
                  label: t.tr('common.add'),
                  busyLabel: t.tr('coversModal.uploading'),
                  busy: _busy,
                  showSpinner: _busy && _actionId == null,
                  enabledIcon: LucideIcons.upload,
                  onTap: () => unawaited(_addByFile()),
                ),
              ],
            ),
          ],

          // Ошибка (role=alert).
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8), // mt-2
              child: Text(
                errorMessage(_error!, ref.read(i18nProvider)),
                style: const TextStyle(
                    fontSize: 12, color: _kRose300), // text-xs text-rose-300
              ),
            ),
        ],
      ),
    );
  }

  // ---- Gallery grid ----

  Widget _buildGallery(I18nDictionary t, List<MediaCoverItem> covers) {
    final coverUrl = widget.media.coverUrl;
    final vw = MediaQuery.sizeOf(context).width;
    // grid-cols-2 sm:grid-cols-3 md:grid-cols-4 — брейкпоинты вьюпорта.
    final columns = vw >= 768 ? 4 : vw >= 640 ? 3 : 2;

    if (covers.isEmpty && (coverUrl == null || coverUrl.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.all(16), // p-4
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48), // py-12
              child: Column(
                children: [
                  Icon(LucideIcons.image,
                      size: 36, color: _kSlate500), // text-slate-500
                  const SizedBox(height: 8), // mb-2
                  Text(
                    t.tr('coversModal.noCovers'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14, // text-sm
                      fontWeight: FontWeight.w500,
                      color: _kSlate400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final tiles = <Widget>[
      if (covers.isEmpty && coverUrl != null && coverUrl.isNotEmpty)
        // Fallback: массив пуст, но есть легаси-обложка — одна активная
        // плитка с full-size rendition.
        _CoverTile(
          imageUrl: _resolveImage(fullSizeCoverUrl(coverUrl)),
          alt: widget.media.title,
          active: true,
          busy: _busy,
          actionId: null,
          deleting: false,
          selectLabel: t.tr('coversModal.select'),
          deleteLabel: t.tr('coversModal.delete'),
          activeBadgeLabel: t.tr('coversModal.activeBadge'),
          deleteConfirmLabel: '${t.tr('coversModal.delete')}?',
          deleteButtonLabel: t.tr('common.delete'),
          cancelButtonLabel: t.tr('common.cancel'),
          onSelect: null, // активная не выбирается
          onRequestDelete: null, // легаси-обложка не удаляется из галереи
          onCancelDelete: () {},
          onDelete: () {},
        )
      else
        ...covers.map((cover) {
          final active = _isActiveCover(cover);
          return _CoverTile(
            key: ValueKey(cover.id), // keyed each (cover.id)
            imageUrl: _resolveImage(cover.thumbUrl),
            alt: cover.source ?? widget.media.title,
            active: active,
            busy: _busy,
            actionId: _actionId,
            deleting: _deletingId == cover.id,
            selectLabel: t.tr('coversModal.select'),
            deleteLabel: t.tr('coversModal.delete'),
            activeBadgeLabel: t.tr('coversModal.activeBadge'),
            deleteConfirmLabel: '${t.tr('coversModal.delete')}?',
            deleteButtonLabel: t.tr('common.delete'),
            cancelButtonLabel: t.tr('common.cancel'),
            source: cover.source,
            onSelect: active ? null : () => unawaited(_select(cover.id)),
            onRequestDelete: () => setState(() => _deletingId = cover.id),
            onCancelDelete: () => setState(() => _deletingId = null),
            onDelete: () => unawaited(_delete(cover.id)),
          );
        }),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16), // p-4
        child: LayoutBuilder(
          builder: (context, constraints) {
            // gap-4 = 16px; ширина плитки из остатка.
            final tileWidth =
                (constraints.maxWidth - 16 * (columns - 1)) / columns;
            return Wrap(
              spacing: 16, // gap-4
              runSpacing: 16,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: tileWidth,
                    child: tile,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- Header close button ----

class _HoverCloseButton extends StatefulWidget {
  final VoidCallback onClose;
  final String label;

  const _HoverCloseButton({required this.onClose, required this.label});

  @override
  State<_HoverCloseButton> createState() => _HoverCloseButtonState();
}

class _HoverCloseButtonState extends State<_HoverCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Semantics(
      button: true,
      label: widget.label, // aria-label
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: 32, // size-8 (h-8 w-8)
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
              color: _hovered
                  ? Colors.white.withAlpha(13) // hover:bg-white/5
                  : Colors.transparent,
            ),
            child: Icon(
              LucideIcons.x,
              size: 16,
              // text-muted → hover:text-ink
              color: _hovered ? th.textPrimary : th.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Segment toggle button (URL / Файл) ----

class _SegmentButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // px-3 py-1.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            color: widget.active
                ? _kIndigo600 // bg-indigo-600 text-white
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.active
                    ? Colors.white
                    : _hovered
                        ? Colors.white // hover:text-white
                        : _kSlate400, // text-slate-400
              ),
              const SizedBox(width: 6), // gap-1.5
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: widget.active
                      ? Colors.white
                      : _hovered
                          ? Colors.white
                          : _kSlate400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Manga «Обложки томов» ----

class _FetchVolumesButton extends StatefulWidget {
  final String label;
  final String fetchingLabel;
  final bool busy;
  final bool fetching;
  final String tooltip;
  final VoidCallback onTap;

  const _FetchVolumesButton({
    required this.label,
    required this.fetchingLabel,
    required this.busy,
    required this.fetching,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_FetchVolumesButton> createState() => _FetchVolumesButtonState();
}

class _FetchVolumesButtonState extends State<_FetchVolumesButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.busy;
    final activeBg = _hovered && !disabled;
    return Semantics(
      button: true,
      label: widget.tooltip, // title
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: disabled ? null : widget.onTap,
          child: Opacity(
            opacity: disabled ? 0.5 : 1, // disabled:opacity-50
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6), // px-3 py-1.5
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                  color: _kIndigo500.withAlpha(77), // border-indigo-500/30
                ),
                color: activeBg
                    ? _kIndigo500.withAlpha(51) // hover:bg-indigo-500/20
                    : _kIndigo500.withAlpha(26), // bg-indigo-500/10
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.fetching) ...[
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kIndigo300, // text-indigo-300
                      ),
                    ),
                    const SizedBox(width: 6), // gap-1.5
                    Text(
                      widget.fetchingLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _hovered && !disabled
                            ? Colors.white // hover:text-white
                            : _kIndigo300,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      LucideIcons.bookOpen,
                      size: 13,
                      color: _hovered && !disabled ? Colors.white : _kIndigo300,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _hovered && !disabled ? Colors.white : _kIndigo300,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Файловое поле «Выберите изображение» ----

class _FileChooseField extends StatefulWidget {
  final String label;
  final bool busy;
  final Future<void> Function() onPick;

  const _FileChooseField({
    required this.label,
    required this.busy,
    required this.onPick,
  });

  @override
  State<_FileChooseField> createState() => _FileChooseFieldState();
}

class _FileChooseFieldState extends State<_FileChooseField> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // input disabled={busy}: тап ничего не делает при busy.
        onTap: widget.busy ? null : () => unawaited(widget.onPick()),
        child: Container(
          height: 36, // h-9
          padding: const EdgeInsets.symmetric(horizontal: 12), // px-3
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            border: Border.all(
              color: _hovered
                  ? Colors.white.withAlpha(51) // hover:border-white/20
                  : Colors.white.withAlpha(26), // border-white/10
            ),
            color: _kInputBg,
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // truncate
            style: const TextStyle(fontSize: 12, color: _kSlate300),
          ),
        ),
      ),
    );
  }
}

// ---- Primary submit-кнопка (indigo-600) ----

class _AddSubmitButton extends StatefulWidget {
  final String label;
  final String busyLabel;
  final bool busy;
  final bool showSpinner;
  final IconData enabledIcon;
  final VoidCallback onTap;

  const _AddSubmitButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.showSpinner,
    required this.enabledIcon,
    required this.onTap,
  });

  @override
  State<_AddSubmitButton> createState() => _AddSubmitButtonState();
}

class _AddSubmitButtonState extends State<_AddSubmitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // disabled={busy || !urlInput.trim()} гвардится в обработчике; визуально —
    // opacity-50 при busy.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onTap,
        child: Opacity(
          opacity: widget.busy ? 0.5 : 1, // disabled:opacity-50
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6), // px-3 py-1.5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), // rounded-lg
              color: _hovered && !widget.busy
                  ? _kIndigo500 // hover:bg-indigo-500
                  : _kIndigo600, // bg-indigo-600
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showSpinner) ...[
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6), // gap-1.5
                  Text(
                    widget.busyLabel,
                    style: const TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600, // font-semibold
                      color: Colors.white,
                    ),
                  ),
                ] else ...[
                  Icon(widget.enabledIcon, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Плитка обложки ----

class _CoverTile extends StatefulWidget {
  final String imageUrl;
  final String alt;
  final bool active;
  final bool busy;
  final String? actionId;
  final bool deleting;
  final String selectLabel;
  final String deleteLabel;
  final String activeBadgeLabel;
  final String deleteConfirmLabel;
  final String deleteButtonLabel;
  final String cancelButtonLabel;
  final String? source;
  final VoidCallback? onSelect;
  final VoidCallback? onRequestDelete;
  final VoidCallback onCancelDelete;
  final VoidCallback onDelete;

  const _CoverTile({
    super.key,
    required this.imageUrl,
    required this.alt,
    required this.active,
    required this.busy,
    required this.actionId,
    required this.deleting,
    required this.selectLabel,
    required this.deleteLabel,
    required this.activeBadgeLabel,
    required this.deleteConfirmLabel,
    required this.deleteButtonLabel,
    required this.cancelButtonLabel,
    this.source,
    required this.onSelect,
    required this.onRequestDelete,
    required this.onCancelDelete,
    required this.onDelete,
  });

  @override
  State<_CoverTile> createState() => _CoverTileState();
}

class _CoverTileState extends State<_CoverTile> {
  bool _hovered = false;
  bool _selectHovered = false;
  bool _deleteHovered = false;

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    final active = widget.active;

    final tile = AspectRatio(
      aspectRatio: 2 / 3, // aspect-[2/3]
      child: Stack(
        fit: StackFit.expand,
        children: [
          // object-cover + group-hover:scale-105.
          ClipRect(
            child: AnimatedScale(
              scale: _hovered ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 200), // duration-200
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.cover,
                semanticLabel: widget.alt, // alt
                errorBuilder: (context, error, stackTrace) =>
                    const ColoredBox(color: Color(0xFF12151C)),
              ),
            ),
          ),

          // Whole-image click selects an inactive cover.
          if (!active)
            Positioned.fill(
              child: GestureDetector(
                // SizedBox.expand не «клеймит» хиты (deferToChild) —
                // opaque: вся плитка кликабельна, как <button> в Svelte.
                behavior: HitTestBehavior.opaque,
                onTap: busy ? null : widget.onSelect,
                child: const SizedBox.expand(),
              ),
            ),

          // Active badge (top-left).
          if (active)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6), // rounded-md
                  color: _kEmerald600.withAlpha(242), // bg-emerald-600/95
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.check,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4), // gap-1
                    Text(
                      widget.activeBadgeLabel,
                      style: const TextStyle(
                        fontSize: 11, // text-[11px]
                        fontWeight: FontWeight.w700, // font-bold
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // Select button (top-left, on hover).
            Positioned(
              top: 8,
              left: 8,
              child: MouseRegion(
                onEnter: (_) => setState(() => _selectHovered = true),
                onExit: (_) => setState(() => _selectHovered = false),
                child: Semantics(
                  button: true,
                  label: widget.selectLabel, // title/aria-label
                  child: GestureDetector(
                    onTap: busy ? null : widget.onSelect,
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0, // group-hover:opacity-100
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 32, // size-8
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectHovered
                                ? _kIndigo500 // hover:border-indigo-500
                                : Colors.white.withAlpha(51), // white/20
                          ),
                          color: _selectHovered
                              ? _kIndigo600 // hover:bg-indigo-600
                              : Colors.black.withAlpha(179), // bg-black/70
                        ),
                        child: busy && widget.actionId != null
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.check,
                                size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Delete (top-right, on hover).
          Positioned(
            top: 8,
            right: 8,
            child: MouseRegion(
              onEnter: (_) => setState(() => _deleteHovered = true),
              onExit: (_) => setState(() => _deleteHovered = false),
              child: Semantics(
                button: true,
                label: widget.deleteLabel, // title/aria-label
                child: GestureDetector(
                  // stopPropagation — вложенный GestureDetector выигрывает
                  // арену, whole-image select не срабатывает.
                  onTap: busy ? null : widget.onRequestDelete,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _deleteHovered
                              ? _kRose500 // hover:border-rose-500
                              : Colors.white.withAlpha(51),
                        ),
                        color: _deleteHovered
                            ? _kRose600.withAlpha(230) // bg-rose-600/90
                            : Colors.black.withAlpha(179),
                      ),
                      child: Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: _deleteHovered
                            ? Colors.white // hover:text-white
                            : _kSlate300, // text-slate-300
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Delete confirmation (alertdialog).
          if (widget.deleting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withAlpha(217), // bg-black/85
                child: Padding(
                  padding: const EdgeInsets.all(12), // p-3
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.deleteConfirmLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          fontWeight: FontWeight.w600, // font-semibold
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8), // gap-2
                      // Wrap: на узких плитках кнопки переносятся (Svelte-flex
                      // переполнялся бы так же — перенос прагматичнее).
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8, // gap-2
                        runSpacing: 8,
                        children: [
                          GestureDetector(
                            onTap: busy ? null : widget.onDelete,
                            child: Opacity(
                              opacity: busy ? 0.5 : 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4), // px-2.5 py-1
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(6), // rounded-md
                                  color: _kRose600.withAlpha(
                                      230), // bg-rose-600/90 (hover 500/90)
                                ),
                                child: busy && widget.actionId != null
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        widget.deleteButtonLabel,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700, // font-bold
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onCancelDelete,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: Colors.white.withAlpha(26), // white/10
                              ),
                              child: Text(
                                widget.cancelButtonLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600, // font-semibold
                                  color: _kSlate200, // text-slate-200
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Source label (bottom, on hover).
          if (widget.source != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 32, 12, 12), // p-3 pt-8
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: [0, 0.4, 1], // from-90 via-60 to-transparent
                        colors: [
                          Color(0xE6000000), // from-black/90
                          Color(0x99000000), // via-black/60
                          Color(0x00000000),
                        ],
                      ),
                    ),
                    child: Text(
                      widget.source!,
                      maxLines: 2, // line-clamp-2
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        // aspect-[2/3] rounded-xl overflow-hidden + active: emerald ring.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(
            color: active
                ? _kEmerald500.withAlpha(204) // border-emerald-500/80
                : Colors.transparent, // border-2 border-transparent
            width: 2,
          ),
          boxShadow: active
              ? const [
                  // ring-2 ring-emerald-500/40 — спред 2, без blur.
                  BoxShadow(
                    color: Color(0x6610B981),
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10), // 12 - 2 (border внутри)
          child: tile,
        ),
      ),
    );
  }
}

const Color _kRose500 = Color(0xFFF43F5E);
const Color _kSlate200 = Color(0xFFE2E8F0);
