/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/FillMissingModal.svelte`.
///
/// Дополнение пустых полей из внешнего источника: выбор источника
/// (SOURCES_BY_TYPE по типу тайтла), предпросмотр «найдено/нет данных»,
/// подтверждение onFill(source) — сам запрос делает родитель.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/genre_label.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/popover_menu.dart';

// Tailwind-литералы (вне ThemeExtension).
const Color _kTrackFaint = Color(0xFF161A22); // --color-track-faint
const Color _kEmerald300 = Color(0xFF6EE7B7);
const Color _kEmerald400 = Color(0xFF34D399);
const Color _kSlate300 = Color(0xFFCBD5E1);
const Color _kRose300 = Color(0xFFFDA4AF);
const Color _kAccentSoft = Color(0xFFA5B4FC); // --color-accent-soft

/// Проверка одного поля: пусто ли в тайтле и что даст источник.
class _EmptyFieldCheck {
  final String id;
  final String label;
  final bool isEmpty;
  final String? Function(ExternalMedia ext) getPreviewValue;

  const _EmptyFieldCheck({
    required this.id,
    required this.label,
    required this.isEmpty,
    required this.getPreviewValue,
  });
}

/// Модалка дополнения данных (1-в-1 с FillMissingModal.svelte).
class FillMissingModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final bool busy;

  /// null → предпросмотр недоступен (только выбор источника).
  final MediaDetail? media;

  /// wire-строка типа ('game'|'movie'|...|'anime' — как TS-union).
  final String mediaType;
  final String? currentSource;

  /// Сам запрос выполняет родитель (MediaDetailView/App).
  final void Function(String source) onFill;
  final VoidCallback onClose;

  const FillMissingModal({
    super.key,
    required this.isOpen,
    required this.busy,
    this.media,
    required this.mediaType,
    this.currentSource,
    required this.onFill,
    required this.onClose,
  });

  @override
  ConsumerState<FillMissingModal> createState() => _FillMissingModalState();
}

class _FillMissingModalState extends ConsumerState<FillMissingModal> {
  List<SourceInfo> _sources = const <SourceInfo>[];
  bool _sourcesLoaded = false;
  String _source = '';
  String? _loadError;

  bool _previewLoading = false;
  ExternalMedia? _previewData;
  CancelToken? _previewToken;
  String _lastPreviewKey = '';

  // SOURCES_BY_TYPE — 1-в-1 с <script>.
  static const Map<String, List<String>> _sourcesByType = <String, List<String>>{
    'game': <String>['rawg', 'steam'],
    'movie': <String>['tmdb', 'kinopoisk', 'simkl'],
    'tvshow': <String>['tmdb', 'kinopoisk', 'simkl'],
    'anime': <String>['anilist', 'mangadex', 'shikimori', 'sociallib'],
    'manga': <String>['anilist', 'mangadex', 'shikimori', 'sociallib'],
    'book': <String>['sociallib', 'shikimori', 'anilist', 'kitsu', 'openlibrary'],
  };

  bool get _isRu => ref.read(i18nProvider).wire == 'ru';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadSources();
      _maybeFetchPreview();
    });
  }

  @override
  void didUpdateWidget(covariant FillMissingModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadSources();
      _maybeFetchPreview();
    });
  }

  @override
  void dispose() {
    _previewToken?.cancel();
    super.dispose();
  }

  /// $effect: при открытии и пустом списке — getSources (enabled-фильтр).
  Future<void> _maybeLoadSources() async {
    if (!widget.isOpen || _sourcesLoaded) return;
    _sourcesLoaded = true;
    try {
      final list = await ref.read(apiClientProvider).getSources();
      if (!mounted) return;
      setState(() => _sources = list.where((s) => s.isEnabled).toList());
      // selectedValue производен от sources — $effect предпросмотра
      // перезапускается, как только источник определён.
      await _maybeFetchPreview();
    } catch (_) {
      // Svelte пишет errorMessage, но рендерит фиксированную i18n-строку.
      if (mounted) setState(() => _loadError = 'failed');
    }
  }

  List<({String value, String label})> get _options {
    final allowed = _sourcesByType[widget.mediaType.toLowerCase()] ??
        const <String>[];
    return _sources
        .where((entry) => entry.isEnabled && allowed.contains(entry.id))
        .map((entry) => (value: entry.id, label: entry.name))
        .toList();
  }

  String get _selectedValue {
    final options = _options;
    for (final o in options) {
      if (o.value.toLowerCase() == _source.toLowerCase()) return o.value;
    }
    for (final o in options) {
      final cs = (widget.currentSource ?? '').toLowerCase();
      if (o.value.toLowerCase() == cs || o.label.toLowerCase() == cs) {
        return o.value;
      }
    }
    return options.isEmpty ? '' : options.first.value;
  }

  List<_EmptyFieldCheck> get _candidateFields {
    final media = widget.media;
    if (media == null) return const <_EmptyFieldCheck>[];
    final type = media.type.wire.toLowerCase();
    final isRu = _isRu;
    final list = <_EmptyFieldCheck>[
      _EmptyFieldCheck(
        id: 'cover',
        label: isRu ? 'Обложка' : 'Cover',
        isEmpty: media.coverUrl == null || media.coverUrl!.isEmpty,
        getPreviewValue: (ext) =>
            ext.coverUrl != null ? (isRu ? 'найдено' : 'found') : null,
      ),
      _EmptyFieldCheck(
        id: 'description',
        label: isRu ? 'Синопсис' : 'Synopsis',
        isEmpty: media.description?.trim().isEmpty ?? true,
        getPreviewValue: (ext) =>
            (ext.description?.trim().isNotEmpty ?? false)
                ? (isRu ? 'найдено' : 'found')
                : null,
      ),
      _EmptyFieldCheck(
        id: 'genres',
        label: isRu ? 'Жанры' : 'Genres',
        isEmpty: media.genres == null || media.genres!.isEmpty,
        getPreviewValue: (ext) {
          final genres = ext.genres;
          if (genres != null && genres.isNotEmpty) {
            final t = ref.read(tProvider);
            final locale = ref.read(i18nProvider);
            return formatGenresList(genres, t, locale).take(3).join(', ');
          }
          return null;
        },
      ),
    ];

    // Studio / Author / Director.
    if (type == 'game') {
      list.add(_EmptyFieldCheck(
        id: 'studio',
        label: isRu ? 'Разработчик' : 'Developer',
        isEmpty: media.studio?.trim().isEmpty ?? true,
        getPreviewValue: (ext) => ext.studio?.trim().isNotEmpty ?? false
            ? ext.studio!.trim()
            : null,
      ));
    } else if (type == 'book' || type == 'manga') {
      list.add(_EmptyFieldCheck(
        id: 'author',
        label: isRu ? 'Автор' : 'Author',
        isEmpty: media.author?.trim().isEmpty ?? true,
        getPreviewValue: (ext) => ext.author?.trim().isNotEmpty ?? false
            ? ext.author!.trim()
            : null,
      ));
    } else {
      list.add(_EmptyFieldCheck(
        id: 'studio',
        label: isRu ? 'Студия' : 'Studio',
        isEmpty: media.studio?.trim().isEmpty ?? true,
        getPreviewValue: (ext) => ext.studio?.trim().isNotEmpty ?? false
            ? ext.studio!.trim()
            : null,
      ));
      if (type == 'movie') {
        list.add(_EmptyFieldCheck(
          id: 'director',
          label: isRu ? 'Режиссёр' : 'Director',
          isEmpty: media.director?.trim().isEmpty ?? true,
          // Svelte берёт author внешнего ответа.
          getPreviewValue: (ext) => ext.author?.trim().isNotEmpty ?? false
              ? ext.author!.trim()
              : null,
        ));
      }
    }

    // Release Date.
    list.add(_EmptyFieldCheck(
      id: 'releaseDate',
      label: isRu ? 'Дата выхода' : 'Release Date',
      isEmpty: media.releaseDate == null && media.releaseYear == null,
      getPreviewValue: (ext) =>
          ext.releaseDate ?? (ext.releaseYear?.toString()),
    ));

    // End Date.
    if (type == 'tvshow' ||
        type == 'manga' ||
        (type == 'movie' && (media.isAnime ?? false))) {
      list.add(_EmptyFieldCheck(
        id: 'endDate',
        label: isRu ? 'Дата окончания' : 'End Date',
        isEmpty: media.endDate == null,
        getPreviewValue: (ext) => ext.endDate,
      ));
    }

    // Duration / Count.
    if (type == 'movie') {
      list.add(_EmptyFieldCheck(
        id: 'duration',
        label: isRu ? 'Хронометраж' : 'Duration',
        isEmpty:
            media.durationMinutes == null || media.durationMinutes! <= 0,
        getPreviewValue: (ext) =>
            ext.runtimeMinutes != null || ext.totalCount != null
                ? '${ext.runtimeMinutes ?? ext.totalCount} ${isRu ? "мин." : "min"}'
                : null,
      ));
    } else if (type == 'book') {
      list.add(_EmptyFieldCheck(
        id: 'totalPages',
        label: isRu ? 'Количество страниц' : 'Page Count',
        isEmpty: media.totalPages == null || media.totalPages! <= 0,
        getPreviewValue: (ext) => ext.totalCount != null
            ? '${ext.totalCount} ${isRu ? "стр." : "p."}'
            : null,
      ));
    } else if (type == 'manga') {
      list.add(_EmptyFieldCheck(
        id: 'totalChapters',
        label: isRu ? 'Количество глав' : 'Chapter Count',
        isEmpty: media.totalChapters == null || media.totalChapters! <= 0,
        getPreviewValue: (ext) =>
            ext.chapters != null || ext.totalCount != null
                ? '${ext.chapters ?? ext.totalCount} ${isRu ? "гл." : "ch."}'
                : null,
      ));
    }

    // Trailer.
    list.add(_EmptyFieldCheck(
      id: 'trailer',
      label: isRu ? 'Трейлер' : 'Trailer',
      isEmpty: media.trailerVideoId?.trim().isEmpty ?? true,
      getPreviewValue: (ext) => (ext.trailerVideoId?.trim().isNotEmpty ?? false)
          ? (isRu ? 'найдено' : 'found')
          : null,
    ));

    // Cast.
    if (type == 'movie' || type == 'tvshow') {
      list.add(_EmptyFieldCheck(
        id: 'cast',
        label: isRu ? 'Актёры' : 'Cast',
        isEmpty: media.cast == null || media.cast!.isEmpty,
        // В исходнике — заглушка (ext.episodes ? null : null) → всегда null.
        getPreviewValue: (ext) => null,
      ));
    }

    return list;
  }

  /// $effect: предпросмотр с отменой предыдущего запроса (AbortController →
  /// CancelToken); getExternalDetails сам глотает ошибки → null.
  Future<void> _maybeFetchPreview() async {
    final media = widget.media;
    final selectedValue = _selectedValue;
    final key =
        '${widget.isOpen}|${media?.id ?? ''}|${media?.type.wire ?? ''}|$selectedValue';
    if (key == _lastPreviewKey) return;
    _lastPreviewKey = key;

    _previewToken?.cancel();
    if (!widget.isOpen || media == null || selectedValue.isEmpty) {
      if (mounted) {
        setState(() {
          _previewData = null;
          _previewLoading = false;
        });
      }
      return;
    }

    final token = CancelToken();
    _previewToken = token;
    if (mounted) setState(() => _previewLoading = true);

    final data = await ref.read(apiClientProvider).getExternalDetails(
          media.type.wire,
          media.externalId ?? '',
          media.title,
          source: selectedValue,
          cancelToken: token,
        );

    if (token.isCancelled || !mounted) return;
    setState(() {
      _previewData = data;
      _previewLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final options = _options;
    final selectedValue = _selectedValue;
    final selectedLabel = options
            .where((o) => o.value == selectedValue)
            .map((o) => o.label)
            .firstOrNull ??
        '';
    final isRu = _isRu;

    return TsundokuModal(
      isOpen: widget.isOpen,
      onClose: widget.onClose,
      size: ModalSize.md,
      contentPadding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header ----
          Padding(
            padding: const EdgeInsets.all(20), // p-5
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.sparkles,
                        size: 16, color: _kAccentSoft),
                    const SizedBox(width: 8), // gap-2
                    Text(
                      t.tr('detail.fillMissingTitle'),
                      style: const TextStyle(
                        fontSize: 16, // text-base
                        fontWeight: FontWeight.w600, // font-semibold
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6), // mt-1.5
                  child: Text(
                    t.tr('detail.fillMissingHint'),
                    style: TextStyle(
                      fontSize: 14, // text-sm
                      color: th.textMuted, // text-muted
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ---- Source picker ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20), // p-5
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
            ),
            child: Row(
              children: [
                Text(
                  t.tr('detail.fillMissingSource'),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: th.textMuted, // text-muted
                  ),
                ),
                const Spacer(),
                if (options.isNotEmpty)
                  TsundokuPopoverMenu<String>(
                    id: 'fill-missing-${widget.mediaType}',
                    options: [
                      for (final o in options)
                        PopoverOption(value: o.value, label: o.label),
                    ],
                    selected: selectedValue,
                    onSelect: (value) {
                      setState(() => _source = value);
                      // selectedValue производен от source — $effect
                      // перезапускается на смене выбора.
                      unawaited(_maybeFetchPreview());
                    },
                    label: t.tr('detail.fillMissingSource'),
                    placement: PopoverPlacement.bottomEnd,
                    openOnHover: true,
                    closeDelay: 220,
                    optionClass: 'text-xs',
                    trigger: (context, ctx) => IgnorePointer(
                      child: _Hover(
                        builder: (context, hovered) => Container(
                          constraints: const BoxConstraints(
                              maxWidth: 220), // max-w-[220px]
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6), // px-2.5 py-1.5
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(8), // rounded-lg
                            border: Border.all(
                                color: Colors.white
                                    .withAlpha(21)), // /[0.08]
                            color: hovered
                                ? _kTrackFaint // hover:bg-track-faint
                                : th.bgSurface, // bg-[var(--color-field)]
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  selectedLabel,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis, // truncate
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white),
                                ),
                              ),
                              AnimatedRotation(
                                // has-[:popover-open]:rotate-180
                                turns: ctx.isOpen ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  LucideIcons.chevronDown,
                                  size: 13,
                                  color: ctx.isOpen
                                      ? Colors.white
                                      : th.textMuted, // text-muted
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    '—',
                    style: TextStyle(
                        fontSize: 12, color: th.textMuted), // text-muted text-xs
                  ),
              ],
            ),
          ),

          // ---- Preview ----
          _buildPreview(t, th, isRu),

          // ---- Sources load error ----
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), // px-5 pb-3
              child: Text(
                t.tr('detail.fillMissingSourcesFailed'),
                style: const TextStyle(
                    fontSize: 12, color: _kRose300), // text-xs text-rose-300
              ),
            ),

          // ---- Footer ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20), // p-5
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Hover(
                    builder: (context, hovered) {
                      final disabled = widget.busy || options.isEmpty;
                      return MouseRegion(
                        cursor: disabled
                            ? SystemMouseCursors.wait // disabled:cursor-wait
                            : MouseCursor.defer,
                        child: GestureDetector(
                          onTap: disabled ? null : () => widget.onFill(selectedValue),
                          child: Opacity(
                            opacity: disabled ? 0.6 : 1, // disabled:opacity-60
                            child: Container(
                              height: 42, // px-4 py-2.5 (text-sm)
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(8), // rounded-lg
                                color: hovered && !disabled
                                    ? th.accentHover // hover:bg-accent-hover
                                    : th.accent, // bg-accent
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.busy) ...[
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(width: 8), // gap-2
                                  ],
                                  Text(
                                    widget.busy
                                        ? t.tr('detail.fillMissingRunning')
                                        : t.tr('detail.fillMissing'),
                                    style: const TextStyle(
                                      fontSize: 14, // text-sm
                                      fontWeight:
                                          FontWeight.w500, // font-medium
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8), // gap-2
                _Hover(
                  builder: (context, hovered) => GestureDetector(
                    onTap: widget.busy ? null : widget.onClose,
                    child: Opacity(
                      opacity: widget.busy ? 0.6 : 1, // disabled:opacity-60
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10), // px-4 py-2.5
                        child: Text(
                          t.tr('common.cancel'),
                          style: TextStyle(
                            fontSize: 14, // text-sm
                            color: hovered && !widget.busy
                                ? Colors.white // hover:text-white
                                : th.textMuted, // text-muted
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(I18nDictionary t, TsundokuTheme th, bool isRu) {
    final emptyFields =
        _candidateFields.where((f) => f.isEmpty).toList();
    // Скелетон: min(emptyFields.length || 3, 4) строк.
    final skeletonRows = (emptyFields.isEmpty ? 3 : emptyFields.length) < 4
        ? (emptyFields.isEmpty ? 3 : emptyFields.length)
        : 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20), // p-5
      decoration: const BoxDecoration(
        border: Border(
            top: BorderSide(color: Color(0x14FFFFFF))), // /[0.08]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                (isRu ? 'Предпросмотр данных' : 'Preview missing fields')
                    .toUpperCase(),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w700, // font-bold
                  letterSpacing: 0.6, // tracking-wider
                  color: _kSlate300, // text-slate-300
                ),
              ),
              if (_previewLoading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kAccentSoft),
                    ),
                    const SizedBox(width: 6), // gap-1.5
                    Text(
                      isRu ? 'Проверка источника...' : 'Checking source...',
                      style: TextStyle(
                          fontSize: 12, color: th.textMuted), // text-muted
                    ),
                  ],
                ),
            ],
          ),

          if (_previewLoading) ...[
            const SizedBox(height: 12), // space-y-3
            for (var i = 0; i < skeletonRows; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8), // space-y-2
                child: Container(
                  height: 28, // h-7
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10), // bg-white/[0.04]
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                  ),
                ),
              ),
          ] else if (emptyFields.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(
                    color: _kEmerald400.withAlpha(51)), // border-emerald-500/20
                color: _kEmerald400.withAlpha(26), // bg-emerald-500/10
              ),
              child: Text(
                isRu
                    ? '✓ Все основные поля тайтла уже заполнены.'
                    : '✓ All main fields are already filled.',
                style: const TextStyle(
                    fontSize: 12, color: _kEmerald300), // text-emerald-300
              ),
            )
          else ...[
            const SizedBox(height: 12), // space-y-3
            // max-h-52 overflow-y-auto: скролл внутри модалки.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 208), // max-h-52
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final field in emptyFields)
                      Padding(
                        padding: const EdgeInsets.only(top: 6), // space-y-1.5
                        child: _PreviewRow(
                          field: field,
                          value: _previewData != null
                              ? field.getPreviewValue(_previewData!)
                              : null,
                          isRu: isRu,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Одна строка предпросмотра (li).
class _PreviewRow extends StatelessWidget {
  final _EmptyFieldCheck field;
  final String? value;
  final bool isRu;

  const _PreviewRow({
    required this.field,
    required this.value,
    required this.isRu,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // px-2.5 py-1.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        border: Border.all(
          color: hasValue
              ? _kEmerald400.withAlpha(64) // border-emerald-500/25
              : Colors.white.withAlpha(10), // border-white/[0.04]
        ),
        color: hasValue
            ? _kEmerald400.withAlpha(26) // bg-emerald-500/10
            : Colors.white.withAlpha(5), // bg-white/[0.02]
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                if (hasValue) ...[
                  const Text(
                    '✓',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kEmerald400), // text-emerald-400
                  ),
                  const SizedBox(width: 8), // gap-2
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: field.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600, // font-semibold
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: ' — $value',
                            style: TextStyle(
                              fontSize: 12,
                              color: _kEmerald300.withAlpha(204), // text-emerald-300/80
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  Text('—',
                      style: TextStyle(
                          fontSize: 12,
                          color: TsundokuTheme.of(context).textMuted)),
                  const SizedBox(width: 8), // gap-2
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: field.label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kSlate300, // text-slate-300
                            ),
                          ),
                          TextSpan(
                            text: ' — ${isRu ? "нет данных в источнике" : "no data in source"}',
                            style: TextStyle(
                              fontSize: 11, // text-[11px]
                              color: TsundokuTheme.of(context).textMuted, // text-muted
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasValue) ...[
            const SizedBox(width: 8), // gap-2
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // px-1.5 py-0.5
              decoration: BoxDecoration(
                border: Border.all(
                    color: _kEmerald400
                        .withAlpha(77)), // border-emerald-500/30
                color: _kEmerald400.withAlpha(51), // bg-emerald-500/20
                borderRadius: BorderRadius.circular(4), // rounded
              ),
              child: Text(
                isRu ? 'будет заполнено' : 'will fill',
                style: const TextStyle(
                  fontSize: 10, // text-[10px]
                  fontWeight: FontWeight.w700, // font-bold
                  color: _kEmerald300,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// MouseRegion-hover helper: builder получает hovered-флаг.
class _Hover extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;

  const _Hover({required this.builder});

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
