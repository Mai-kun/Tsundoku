/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/ExternalDetailModal.svelte`.
///
/// Превью внешнего тайтла (поиск → карточка): детали подгружаются поверх
/// search-hit (поле-за-полем, stripEmpty), слева постер + характеристики,
/// справа DetailHeader + список эпизодов; снизу — actions-слот (кнопки
/// «в библиотеку» принадлежат вызывающему поиску).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/genre_label.dart';
import '../../features/prefetch-details/external_detail_prefetch.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/models.dart';
import '../../shared/ui/media_cover_placeholder.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/toast.dart';
import '../../shared/ui/tsundoku_image.dart';
import '../../shared/ui/tsundoku_scroll.dart';
import 'detail_formatters.dart' show joinOriginalTitle;
import 'detail_header.dart';

/// lg-граница Tailwind: раскладка строкой и постер на всю ширину aside.
const double _lgBreakpoint = 1024;

/// Превью-модалка внешнего тайтла.
class ExternalDetailModal extends ConsumerStatefulWidget {
  /// The search hit. Rendered immediately, then enriched by the full details.
  final ExternalMedia item;

  /// Aggregator category. `anime` is a search-only type, so it comes from the
  /// caller.
  final String type;
  final VoidCallback onClose;

  /// Add-to-library / open-in-library buttons, owned by the search modal.
  final Widget actions;

  const ExternalDetailModal({
    super.key,
    required this.item,
    required this.type,
    required this.onClose,
    required this.actions,
  });

  @override
  ConsumerState<ExternalDetailModal> createState() =>
      _ExternalDetailModalState();
}

class _ExternalDetailModalState extends ConsumerState<ExternalDetailModal> {
  ExternalMedia? _details;
  bool _loading = false;
  Object? _loadError;

  bool _synopsisExpanded = false;
  bool _isSynopsisTranslated = false;
  bool _translatingSynopsis = false;
  String? _translatedSynopsis;
  bool _imgError = false;

  /// Ключ открытого hit'а ($effect-зависимость из Svelte): при смене —
  /// полный сброс и перезагрузка, поздний ответ не перезапишет чужой тайтл.
  String _hitKey(ExternalMedia item) =>
      '${widget.type}:${item.externalSource ?? ''}:${item.externalId}';

  /// Details win field by field (stripEmpty из Svelte).
  ExternalMedia get _media {
    final details = _details;
    if (details == null) return widget.item;
    return _mergeNonEmpty(widget.item, details);
  }

  /// Соединяет item с деталями: непустые поля деталей побеждают (1-в-1 с
  /// `{...item, ...stripEmpty(details)}`).
  ExternalMedia _mergeNonEmpty(ExternalMedia base, ExternalMedia source) {
    String? nz(String? v) => (v != null && v.isNotEmpty) ? v : null;
    return ExternalMedia(
      externalId: nz(source.externalId) ?? base.externalId,
      externalSource: nz(source.externalSource) ?? base.externalSource,
      title: nz(source.title) ?? base.title,
      originalTitle: nz(source.originalTitle) ?? base.originalTitle,
      romajiTitle: nz(source.romajiTitle) ?? base.romajiTitle,
      coverUrl: nz(source.coverUrl) ?? base.coverUrl,
      description: nz(source.description) ?? base.description,
      trailerVideoId: nz(source.trailerVideoId) ?? base.trailerVideoId,
      releaseYear: source.releaseYear ?? base.releaseYear,
      releaseDate: nz(source.releaseDate) ?? base.releaseDate,
      endDate: nz(source.endDate) ?? base.endDate,
      releaseStatus: nz(source.releaseStatus) ?? base.releaseStatus,
      format: nz(source.format) ?? base.format,
      runtimeMinutes: source.runtimeMinutes ?? base.runtimeMinutes,
      type: nz(source.type) ?? base.type,
      author: nz(source.author) ?? base.author,
      studio: nz(source.studio) ?? base.studio,
      isbn: nz(source.isbn) ?? base.isbn,
      covers: (source.covers?.isNotEmpty ?? false) ? source.covers : base.covers,
      totalCount: source.totalCount ?? base.totalCount,
      chapters: source.chapters ?? base.chapters,
      volumes: source.volumes ?? base.volumes,
      mangaFormat: nz(source.mangaFormat) ?? base.mangaFormat,
      countryOfOrigin: nz(source.countryOfOrigin) ?? base.countryOfOrigin,
      platform: nz(source.platform) ?? base.platform,
      rating: source.rating ?? base.rating,
      ratingVotes: source.ratingVotes ?? base.ratingVotes,
      ratings: (source.ratings?.isNotEmpty ?? false) ? source.ratings : base.ratings,
      episodes: (source.episodes?.isNotEmpty ?? false) ? source.episodes : base.episodes,
      genres: (source.genres?.isNotEmpty ?? false) ? source.genres : base.genres,
      tags: (source.tags?.isNotEmpty ?? false) ? source.tags : base.tags,
      synonyms: (source.synonyms?.isNotEmpty ?? false) ? source.synonyms : base.synonyms,
      isDirectUrl: source.isDirectUrl ?? base.isDirectUrl,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDetails();
    });
  }

  @override
  void didUpdateWidget(covariant ExternalDetailModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect-аналог: смена открытого hit'а — сброс стейта и повторная загрузка.
    if (_hitKey(oldWidget.item) != _hitKey(widget.item)) {
      _imgError = false;
      _synopsisExpanded = false;
      _translatingSynopsis = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDetails();
      });
    } else if (oldWidget.item.coverUrl != widget.item.coverUrl) {
      setState(() => _imgError = false); // $effect(void media.coverUrl)
    }
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _synopsisExpanded = false;
      _isSynopsisTranslated = false;
      _translatedSynopsis = null;
    });
    try {
      final loaded = await loadExternalDetailsCore(
        ref.read(externalDetailsCacheProvider),
        ref.read(apiClientProvider),
        widget.type,
        widget.item,
      );
      if (!mounted) return;
      setState(() {
        _details = loaded;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _toggleTranslateSynopsis() async {
    final synopsisText = _media.description?.trim() ?? '';
    if (synopsisText.isEmpty || _translatingSynopsis) return;

    if (_isSynopsisTranslated) {
      setState(() => _isSynopsisTranslated = false);
      return;
    }
    if (_translatedSynopsis != null) {
      setState(() => _isSynopsisTranslated = true);
      return;
    }

    setState(() => _translatingSynopsis = true);
    final t = ref.read(tProvider);
    final locale = ref.read(i18nProvider);
    try {
      final target = locale.wire == 'en' ? 'en' : 'ru';
      final res = await ref
          .read(apiClientProvider)
          .translateText(synopsisText, targetLanguage: target);
      if (res.isNotEmpty) {
        setState(() {
          _translatedSynopsis = res;
          _isSynopsisTranslated = true;
        });
      }
    } catch (error) {
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _translatingSynopsis = false);
    }
  }

  String _typeLabel(I18nDictionary t) {
    return widget.type == 'anime'
        ? t.tr('navigation.anime')
        : t.tr('types.${widget.type}');
  }

  List<RatingBadge> _ratings(ExternalMedia media) {
    final list = <RatingBadge>[];
    final seen = <String>{};

    for (final r in media.ratings ?? const <ExternalRating>[]) {
      final source = r.source.trim();
      if (source.isEmpty) continue;
      final key = source.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      list.add(RatingBadge(
        source: source,
        score: r.rating > 0 ? r.rating : null,
        votes: r.votes,
      ));
    }

    // Источник с одним score без массива рейтингов тоже получает бейдж.
    if (list.isEmpty &&
        media.rating != null &&
        media.rating! > 0 &&
        media.externalSource != null) {
      list.add(RatingBadge(
        source: media.externalSource!,
        score: media.rating,
        votes: media.ratingVotes,
      ));
    }

    return list;
  }

  List<String> _tags(ExternalMedia media, I18nDictionary t) {
    final list = <String>[_typeLabel(t)];
    if (media.mangaFormat != null && media.mangaFormat!.isNotEmpty) {
      // Формат через i18n detail.mangaFormats.
      try {
        list.add(t.tr('detail.mangaFormats.${media.mangaFormat}'));
      } on ArgumentError {
        // Неизвестный формат — пропускаем (Svelte: formats[key] ?? "").
      }
    }
    if (media.platform?.isNotEmpty ?? false) list.add(media.platform!);
    if (media.studio?.isNotEmpty ?? false) list.add(media.studio!);
    if (media.author?.isNotEmpty ?? false) list.add(media.author!);
    return list.where((v) => v.isNotEmpty).toSet().toList();
  }

  String _formatDate(String? value, int? year, I18nDictionary t, Locale locale) {
    if (value != null && value.isNotEmpty) return value;
    if (year != null && year > 0) {
      return locale.wire == 'ru' ? '$year год' : '$year';
    }
    return t.tr('detailModal.dateEmpty');
  }

  String _countLabel(String type, I18nDictionary t) {
    switch (type) {
      case 'manga':
        return t.tr('detail.chaptersLabel');
      case 'book':
        return t.tr('detail.pagesLabel');
      case 'game':
        return t.tr('detail.hoursLabel');
      default:
        return t.tr('detail.episodesLabel');
    }
  }

  String? _countValue(ExternalMedia media, String type, I18nDictionary t) {
    if (type == 'manga') {
      final chapters = media.chapters ?? media.totalCount;
      final volumes = media.volumes;
      if (chapters == null && volumes == null) return null;
      return [
        chapters != null ? '$chapters' : null,
        volumes != null ? '${t.tr('detail.volumesLabel')}: $volumes' : null,
      ]
          .where((v) => v != null && v.isNotEmpty)
          .join(' · ');
    }
    if (type == 'game') {
      return media.totalCount != null ? '${media.totalCount}' : null;
    }
    final total = media.totalCount ?? media.episodes?.length;
    return total != null ? '$total' : null;
  }

  /// Release status приходит сырой строкой провайдера — матч по подстроке.
  String _releaseStatusLabel(ExternalMedia media, I18nDictionary t) {
    final raw = media.releaseStatus?.trim().toUpperCase();
    if (raw == null || raw.isEmpty) return t.tr('detailModal.valueEmpty');
    if (raw.contains('CANCEL')) return t.tr('detail.releaseStatuses.cancelled');
    if (raw.contains('HIATUS') || raw.contains('ПАУЗ')) {
      return t.tr('detail.releaseStatuses.hiatus');
    }
    if (raw.contains('NOT_YET') ||
        raw.contains('UPCOMING') ||
        raw.contains('ANNOUNCE') ||
        raw.contains('СКОРО')) {
      return t.tr('detail.releaseStatuses.notYetReleased');
    }
    if (raw.contains('RELEASING') ||
        raw.contains('CURRENT') ||
        raw.contains('ONGOING') ||
        raw.contains('ВЫПУСК') ||
        raw.contains('ЭФИР')) {
      return t.tr('detail.releaseStatuses.releasing');
    }
    return t.tr('detail.releaseStatuses.finished');
  }

  /// Провайдеры шлют список или строку через запятую — оба показываем.
  List<String> _list(Object? value) {
    if (value is List) return value.map((v) => v.toString()).toList();
    if (value is String && value.isNotEmpty) {
      return value.split(',').map((part) => part.trim()).toList();
    }
    return const <String>[];
  }

  List<({String label, String value})> _specRows(
      ExternalMedia media, String type, I18nDictionary t, Locale locale) {
    final empty = t.tr('detail.previewModal.noData');
    final rows = <({String label, String value})>[];

    if (type == 'game') {
      rows.add((
        label: t.tr('detail.releaseDateLabel'),
        value: _formatDate(media.releaseDate, media.releaseYear, t, locale),
      ));
    } else {
      rows.add((
        label: t.tr('detail.startDateLabel'),
        value: _formatDate(media.releaseDate, media.releaseYear, t, locale),
      ));
      rows.add((
        label: t.tr('detail.endDateLabel'),
        value: media.endDate != null
            ? _formatDate(media.endDate, null, t, locale)
            : t.tr('detailModal.dateEmpty'),
      ));
    }

    rows.add((label: t.tr('status.label'), value: _releaseStatusLabel(media, t)));

    final count = _countValue(media, type, t);
    if (count != null) rows.add((label: _countLabel(type, t), value: count));

    if (media.runtimeMinutes != null && media.runtimeMinutes! > 0) {
      rows.add((
        label: t.tr('detail.durationLabel'),
        value: type == 'movie'
            ? t.tf('card.movie', [media.runtimeMinutes!])
            : '${media.runtimeMinutes} ${t.tr('detail.minPerEp')}',
      ));
    }

    if (media.studio?.isNotEmpty ?? false) {
      rows.add((label: t.tr('detailModal.studio'), value: media.studio!));
    }
    if (media.author?.isNotEmpty ?? false) {
      rows.add((label: t.tr('detailModal.author'), value: media.author!));
    }
    if ((media.platform?.isNotEmpty ?? false) && type != 'game') {
      rows.add((label: t.tr('detailModal.platform'), value: media.platform!));
    }

    final genres = formatGenresList(_list(media.genres), t, locale).join(', ');
    rows.add((
      label: t.tr('detail.genresLabel'),
      value: genres.isEmpty ? empty : genres,
    ));
    final tags = _list(media.tags).join(', ');
    rows.add((label: t.tr('detail.tagsLabel'), value: tags.isEmpty ? empty : tags));

    rows.add((
      label: t.tr('detail.source'),
      value: media.externalSource?.isNotEmpty ?? false
          ? media.externalSource!
          : empty,
    ));

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final media = _media;
    final isDesktop = MediaQuery.sizeOf(context).width >= _lgBreakpoint;
    final loadingFirst = _loading && _details == null;

    final originalTitle =
        joinOriginalTitle(media.title, media.originalTitle, media.romajiTitle);
    final synopsisText = media.description?.trim() ?? '';
    final synopsisExpandable = synopsisText.length > 280;

    return TsundokuModal(
      isOpen: true,
      onClose: widget.onClose,
      size: ModalSize.lg,
      contentPadding: EdgeInsets.zero,
      child: ConstrainedBox(
        // max-h-[88vh]: панель сжимается под контент, но не выше 88vh.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Stack(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.fromLTRB(24, 20, 24, 20), // px-6 pt-5 pb-5
                    child: loadingFirst
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 64), // py-16
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF94A3B8)), // text-muted
                                  ),
                                  const SizedBox(width: 8), // gap-2
                                  Text(
                                    t.tr('common.loading'),
                                    style: TextStyle(
                                      fontSize: 14, // text-sm
                                      color: th.textMuted, // text-muted
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : TsundokuSmoothScrollView(
                            child: isDesktop
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // lg:w-64: Row даёт non-flex детям
                                      // unbounded width — aside должен быть
                                      // ограничен снаружи.
                                      SizedBox(
                                        width: 256,
                                        child: _buildAside(media, t, locale, th,
                                            posterFullWidth: true),
                                      ),
                                      const SizedBox(width: 24), // lg:gap-6
                                      Expanded(
                                        child: _buildRightColumn(
                                            media, t, locale, th,
                                            originalTitle: originalTitle,
                                            synopsisText: synopsisText,
                                            synopsisExpandable:
                                                synopsisExpandable),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildAside(media, t, locale, th,
                                          posterFullWidth: false),
                                      const SizedBox(height: 24), // gap-6
                                      _buildRightColumn(media, t, locale, th,
                                          originalTitle: originalTitle,
                                          synopsisText: synopsisText,
                                          synopsisExpandable: synopsisExpandable),
                                    ],
                                  ),
                          ),
                  ),
                  // X-кнопка закрытия (tap hover:bg-elevated hover:text-ink).
                  Positioned(
                    top: 16, // top-4
                    right: 16, // right-4
                    child: _CloseButton(
                      semanticLabel: t.tr('common.close'),
                      idleColor: th.textMuted,
                      hoverColor: th.textPrimary, // hover:text-ink
                      hoverBackground: th.bgElevated, // hover:bg-elevated
                      onClose: widget.onClose,
                    ),
                  ),
                ],
              ),
            ),
            // Actions live outside the scroller: a long episode list must never
            // push "add to library" off the bottom of the panel.
            if (!loadingFirst)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16), // px-6 py-4
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0x12FFFFFF)), // white/[0.07]
                  ),
                ),
                child: Wrap(
                  spacing: 8, // gap-2
                  crossAxisAlignment: WrapCrossAlignment.center, // items-center
                  children: [widget.actions],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// aside: постер (мобайл w-40 по центру, десктоп w-full) + характеристики.
  /// Ширина самого aside задаётся снаружи (SizedBox на desktop-ветке).
  Widget _buildAside(ExternalMedia media, I18nDictionary t, Locale locale,
      TsundokuTheme th,
      {required bool posterFullWidth}) {
    final poster = AspectRatio(
      aspectRatio: 2 / 3, // aspect-[2/3]
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border:
              Border.all(color: Colors.white.withAlpha(15)), // white/[0.06]
          color: th.bgSurface, // bg-[var(--color-panel-line)]
          boxShadow: const [
            // shadow-lg: 0 10px 15px -3px rgb(0 0 0/0.1), 0 4px 6px -4px rgb(0 0 0/0.1)
            BoxShadow(
              color: Color(0x1A000000),
              offset: Offset(0, 10),
              blurRadius: 15,
              spreadRadius: -3,
            ),
            BoxShadow(
              color: Color(0x1A000000),
              offset: Offset(0, 4),
              blurRadius: 6,
              spreadRadius: -4,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: media.coverUrl != null && !_imgError
            ? TsundokuImage(
                src: media.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_imgError) {
                      setState(() => _imgError = true);
                    }
                  });
                  return const MediaCoverPlaceholder();
                },
                placeholder: const MediaCoverPlaceholder(),
              )
            : const MediaCoverPlaceholder(),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16), // space-y-4
          child: posterFullWidth
              ? poster // lg:w-full — заполняет aside
              : Center(
                  child: SizedBox(width: 160, child: poster)), // w-40 mx-auto
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tr('detail.detailsTitle').toUpperCase(),
              style: const TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w700, // font-bold
                letterSpacing: 0.6, // tracking-wider
                color: Color(0xFFE2E8F0), // text-slate-200
              ),
            ),
            const SizedBox(height: 8), // mb-2
            Container(
              padding: const EdgeInsets.all(16), // .panel: p-4
              decoration: BoxDecoration(
                color: th.bgSurface, // bg-panel-line
                borderRadius: BorderRadius.circular(12), // rounded-xl
                border: Border.all(
                    color: Colors.white.withAlpha(15)), // white/[0.06]
                boxShadow: const [
                  // .panel: 0 4px 12px rgb(0 0 0 / 0.35)
                  BoxShadow(
                    color: Color(0x59000000),
                    offset: Offset(0, 4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: _SpecRowsList(
                rows: _specRows(media, widget.type, t, locale),
                labelColor: th.textMuted, // text-muted
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRightColumn(
      ExternalMedia media, I18nDictionary t, Locale locale, TsundokuTheme th,
      {required String? originalTitle,
      required String synopsisText,
      required bool synopsisExpandable}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailHeader(
          title: media.title,
          originalTitle: originalTitle,
          tags: _tags(media, t),
          ratings: _ratings(media),
          synopsisText: synopsisText,
          synopsisExpanded: _synopsisExpanded,
          synopsisExpandable: synopsisExpandable,
          synopsisTranslated: _isSynopsisTranslated,
          translatedSynopsis: _translatedSynopsis,
          translatingSynopsis: _translatingSynopsis,
          onToggleTranslate: () => unawaited(_toggleTranslateSynopsis()),
          onToggleExpand: () =>
              setState(() => _synopsisExpanded = !_synopsisExpanded),
        ),
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 20), // space-y-5
            child: Semantics(
              liveRegion: true, // role="alert"
              child: Text(
                errorMessage(_loadError!, locale),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  color: Color(0xFFFDA4AF), // rose-300
                ),
              ),
            ),
          ),
        if (media.episodes != null && media.episodes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20), // space-y-5
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tf('detail.previewModal.episodesList', [
                    media.episodes!.length,
                  ]).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    letterSpacing: 0.6, // tracking-wider
                    color: th.textMuted, // text-muted
                  ),
                ),
                const SizedBox(height: 8), // mt-2
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 224), // max-h-56
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4), // pr-1
                    child: TsundokuSmoothScrollView(
                      child: Column(
                        children: [
                          for (final ep in media.episodes!)
                            Container(
                              margin:
                                  const EdgeInsets.only(bottom: 6), // space-y-1.5
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6), // px-2.5 py-1.5
                              decoration: BoxDecoration(
                                color: th.bgElevated
                                    .withAlpha(128), // bg-elevated/50
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'E${ep.number}',
                                    style: TextStyle(
                                      fontSize: 12, // text-xs
                                      fontWeight: FontWeight.w500, // font-medium
                                      color: th.textMuted, // text-muted
                                    ),
                                  ),
                                  const SizedBox(width: 12), // gap-3
                                  Expanded(
                                    child: Text(
                                      ep.title.isNotEmpty
                                          ? ep.title
                                          : t.tf('detail.episodeTitle',
                                              [ep.number]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12, // text-xs
                                        color:
                                            th.textPrimary, // text-ink
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// `dl.divide-y.divide-white/5.text-sm`: строки «метка — значение» с
/// разделителями между ними (divide-y = border-top на всех, кроме первой);
/// `py-2.5 first:pt-0 last:pb-0`.
class _SpecRowsList extends StatelessWidget {
  final List<({String label, String value})> rows;
  final Color labelColor;

  const _SpecRowsList({required this.rows, required this.labelColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : 10, // py-2.5 first:pt-0
              bottom: i == rows.length - 1 ? 0 : 10, // last:pb-0
            ),
            decoration: i > 0
                ? const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0x0DFFFFFF)), // divide-white/5
                    ),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, // items-start
              children: [
                Text(
                  rows[i].label,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w500, // font-medium
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 12), // gap-3
                Expanded(
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.right, // text-right
                    style: const TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w500, // font-medium
                      color: Colors.white, // text-white
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// X-кнопка закрытия: hover bg-elevated + текст-инк (1-в-1 с классами Svelte).
class _CloseButton extends StatefulWidget {
  final String semanticLabel;
  final Color idleColor;
  final Color hoverColor;
  final Color hoverBackground;
  final VoidCallback onClose;

  const _CloseButton({
    required this.semanticLabel,
    required this.idleColor,
    required this.hoverColor,
    required this.hoverBackground,
    required this.onClose,
  });

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel, // aria-label common.close
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: 32, // h-8 w-8
            height: 32,
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(8), // rounded-lg
            ),
            child: Icon(
              LucideIcons.x, // X size={18}
              size: 18,
              color: _hovered ? widget.hoverColor : widget.idleColor,
            ),
          ),
        ),
      ),
    );
  }
}
