/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/tabs/OverviewTab.svelte`.
///
/// Лестница блоков: две независимые колонки при lg (каждая — по высоте
/// контента), ниже lg — один поток в порядке order-1..9. Диспетчеры
/// прогресс-блока по типу медиа.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../detail_types.dart';
import '../progress_stepper.dart';
import '../sections/book_edition_section.dart';
import '../sections/book_progress_section.dart';
import '../sections/cast_section.dart';
import '../sections/creator_section.dart';
import '../sections/game_detail_section.dart';
import '../sections/linked_sources_section.dart';
import '../sections/manga_progress_section.dart';
import '../sections/media_files_section.dart';
import '../sections/movie_status_section.dart';
import '../sections/notes_section.dart';
import '../sections/quick_facts_section.dart';
import '../sections/quotes_section.dart';
import '../sections/tv_show_progress_section.dart';
import '../sections/trailer_section.dart';

/// Таб «Обзор» (1-в-1 с OverviewTab.svelte).
class OverviewTab extends ConsumerWidget {
  final MediaDetail media;

  /// Null, когда тип не ведёт счётчик (просмотренный фильм).
  final ProgressInfo? support;
  final int progressValue;
  final double progressPercent;
  final Object? progressError;
  final void Function(int delta) onStep;

  /// Игровой счётчик; дебаунс-запись — в родителе.
  final void Function(int value) onCounterChange;
  final List<GameAchievementItem> achievements;
  final int achievementsTotal;
  final bool achievementsLoading;
  final bool achievementsBusy;
  final bool achievementsTruncated;
  final Map<String, String> unlockedAchievementNames;
  final Future<void> Function(String name) onToggleAchievement;
  final Future<void> Function() onToggleAllAchievements;
  final void Function(MediaItem item) onOpenMedia;
  final void Function(String query) onSearch;
  final VoidCallback onEdit;

  /// Открывает relink-модал (смена основного источника).
  final VoidCallback? onOpenRelink;

  /// После мутации linked-sources/files — родитель перечитывает карточку.
  final VoidCallback? onChanged;
  final void Function(MediaStatus status)? onChangeStatus;

  const OverviewTab({
    super.key,
    required this.media,
    required this.support,
    required this.progressValue,
    required this.progressPercent,
    required this.progressError,
    required this.onStep,
    required this.onCounterChange,
    required this.achievements,
    required this.achievementsTotal,
    required this.achievementsLoading,
    required this.achievementsBusy,
    required this.achievementsTruncated,
    required this.unlockedAchievementNames,
    required this.onToggleAchievement,
    required this.onToggleAllAchievements,
    required this.onOpenMedia,
    required this.onSearch,
    required this.onEdit,
    this.onOpenRelink,
    this.onChanged,
    this.onChangeStatus,
  });

  ({String name, CreatorRole role, String label})? _creator(I18nDictionary t) {
    final media = this.media;
    final typeWire = media.type.wire;
    if (typeWire == 'movie') {
      final isAnime = (media.isAnime ?? false) || typeWire == 'anime';
      if (isAnime && (media.studio?.trim().isNotEmpty ?? false)) {
        return (
          name: media.studio!.trim(),
          role: CreatorRole.studio,
          label: t.tr('creator.studio'),
        );
      }
      if (media.director?.trim().isNotEmpty ?? false) {
        return (
          name: media.director!.trim(),
          role: CreatorRole.director,
          label: t.tr('creator.director'),
        );
      }
      if (media.studio?.trim().isNotEmpty ?? false) {
        return (
          name: media.studio!.trim(),
          role: CreatorRole.studio,
          label: t.tr('creator.studio'),
        );
      }
    } else if (typeWire == 'tvshow') {
      if (media.studio?.trim().isNotEmpty ?? false) {
        return (
          name: media.studio!.trim(),
          role: CreatorRole.studio,
          label: t.tr('creator.studio'),
        );
      }
      if (media.network?.trim().isNotEmpty ?? false) {
        return (
          name: media.network!.trim(),
          role: CreatorRole.studio,
          label: t.tr('creator.network'),
        );
      }
    } else if (typeWire == 'book' || typeWire == 'manga') {
      if (media.author?.trim().isNotEmpty ?? false) {
        return (
          name: media.author!.trim(),
          role: CreatorRole.author,
          label: typeWire == 'manga'
              ? t.tr('creator.mangaka')
              : t.tr('creator.author'),
        );
      }
    } else if (typeWire == 'game' &&
        (media.studio?.trim().isNotEmpty ?? false)) {
      return (
        name: media.studio!.trim(),
        role: CreatorRole.studio,
        label: t.tr('creator.developer'),
      );
    }
    return null;
  }

  String get _categoryKey =>
      (media.type == MediaType.tvshow || media.type == MediaType.movie) &&
              (media.isAnime ?? false)
          ? 'anime'
          : media.type.wire;

  String get _linkedSourcesType {
    // Источники регистрируются как anime/manga/book: аниме-сериалы и фильмы
    // отдаются им как «anime», иначе ссылки уходят в /manga/.
    final typeWire = media.type.wire;
    if (typeWire == 'tvshow' || typeWire == 'movie') {
      return (media.isAnime ?? false) ? 'anime' : typeWire;
    }
    return typeWire;
  }

  String _statusLabel(I18nDictionary t) {
    switch (media.status) {
      case MediaStatus.planned:
        return t.tr('status.planned');
      case MediaStatus.inProgress:
        return t.tr('status.inProgress');
      case MediaStatus.completed:
        return t.tr('status.completed');
      case MediaStatus.onHold:
        return t.tr('status.paused');
      case MediaStatus.dropped:
        return t.tr('status.dropped');
    }
  }

  bool get _hasCast =>
      (media.type == MediaType.movie ||
          media.type == MediaType.tvshow ||
          media.type == MediaType.manga) &&
      (media.cast?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024; // lg:

    final isBook = media.type == MediaType.book;
    final isManga = media.type == MediaType.manga;
    final isMovie = media.type == MediaType.movie;
    final isTvShow = media.type == MediaType.tvshow;
    final hasQuotes =
        media.quotesJson != null && media.quotesJson != '[]';
    final showQuotes = isBook || isManga || hasQuotes;
    final creator = _creator(t);
    final staff = media.staff ?? const <StaffMember>[];
    final statusLabel = _statusLabel(t);

    Widget progressBlock() {
      final support = this.support;
      if (media.type == MediaType.game) {
        return GameDetailSection(
          progressValue: progressValue,
          progressLabel: support?.label ?? t.tr('detail.hoursLabel'),
          progressError: progressError,
          onCounterChange: onCounterChange,
          achievements: achievements,
          achievementsTotal: achievementsTotal,
          achievementsLoading: achievementsLoading,
          achievementsBusy: achievementsBusy,
          achievementsTruncated: achievementsTruncated,
          unlockedNames: unlockedAchievementNames.keys.toSet(),
          onToggleAchievement: onToggleAchievement,
          onToggleAllAchievements: onToggleAllAchievements,
        );
      }
      if (isBook && support != null) {
        return BookProgressSection(
          totalPages: media.totalPages ?? 0,
          currentPage: media.currentPage ?? 0,
          format: media.format,
          totalChapters: media.totalChapters,
          currentChapter: media.currentChapter,
          finishedAt: media.finishedAt,
          progress: support,
          value: progressValue,
          percent: progressPercent,
          error: progressError,
          onStep: onStep,
          onCounterChange: onCounterChange,
        );
      }
      if (isManga && support != null) {
        return MangaProgressSection(
          media: media,
          totalChapters: media.totalChapters ?? 0,
          currentChapter: media.currentChapter ?? 0,
          progress: support,
          value: progressValue,
          percent: progressPercent,
          error: progressError,
          onStep: onStep,
          onCounterChange: onCounterChange,
        );
      }
      if (isTvShow && support != null) {
        return TvShowProgressSection(
          media: media,
          totalEpisodes: media.totalEpisodesCount ?? 0,
          watchedEpisodes: progressValue,
          progress: support,
          value: progressValue,
          percent: progressPercent,
          error: progressError,
          onStep: onStep,
          onCounterChange: onCounterChange,
        );
      }
      if (isMovie) {
        return MovieStatusSection(
          media: media,
          statusLabel: statusLabel,
          onEdit: onEdit,
          onChangeStatus: onChangeStatus,
        );
      }
      if (support != null && support.editable) {
        return ProgressStepper(
          progress: support,
          value: progressValue,
          percent: progressPercent,
          error: progressError,
          onStep: onStep,
          onCounterChange: onCounterChange,
        );
      }
      // Плоская плашка статуса.
      return Container(
        padding: const EdgeInsets.all(20), // p-5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(color: Colors.white.withAlpha(15)),
          color: th.bgSurface, // panel-line
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tr('status.label'),
              style: TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w700, // font-bold
                letterSpacing: 0.6, // tracking-wider
                color: th.textMuted, // text-muted
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4), // mt-1
              child: Text(
                statusLabel,
                style: const TextStyle(
                  fontSize: 18, // text-lg
                  fontWeight: FontWeight.w700, // font-bold
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget creatorBlock() {
      if (creator != null || staff.isNotEmpty) {
        return CreatorSection(
          creatorName: creator?.name ?? '',
          role: creator?.role ?? CreatorRole.author,
          mediaType: media.type.wire,
          label: creator?.label,
          imageUrl: media.creatorImageUrl,
          staff: staff,
          category: _categoryKey,
          currentMediaId: media.id,
          onOpenMedia: onOpenMedia,
          onSearch: onSearch,
        );
      }
      return Container(
        padding: const EdgeInsets.all(20), // p-5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(15)),
          color: th.bgSurface,
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                t.tr('creator.noCreator'),
                style: TextStyle(
                  fontSize: 14, // text-sm
                  color: th.textMuted, // text-muted
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Лестница: две независимые колонки (lg) / один поток (order-1..9).
    final leftColumn = <Widget>[
      progressBlock(),
      if (showQuotes)
        QuotesSection(media: media, onQuotesJsonChanged: null),
      if (media.trailerVideoId != null && media.trailerVideoId!.isNotEmpty)
        TrailerSection(
            trailerVideoId: media.trailerVideoId, title: media.title),
      NotesSection(notes: media.notes, onEdit: onEdit),
      MediaFilesSection(
        mediaId: media.id,
        attachments: media.attachments ?? const <MediaAttachment>[],
        onChanged: onChanged,
      ),
      LinkedSourcesSection(
        mediaId: media.id,
        mediaType: _linkedSourcesType,
        media: media,
        onOpenRelink: onOpenRelink,
        onChanged: onChanged,
      ),
    ];
    final rightColumn = <Widget>[
      if (_hasCast) CastSection(media: media),
      creatorBlock(),
      if (isBook) BookEditionSection(media: media),
    ];

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuickFactsSection(media: media),
          const SizedBox(height: 20), // space-y-5
          Row(
            crossAxisAlignment: CrossAxisAlignment.start, // items-start
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < leftColumn.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16), // gap-4
                      leftColumn[i],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16), // gap-4
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rightColumn.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16), // gap-4
                      rightColumn[i],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Мобайл: один поток в порядке order-1..9 (display: contents).
    // 1 Progress → 2 Cast → 3 Quotes → 4 Creator → 5 Trailer → 6 BookEdition
    // → 7 Notes → 8 Files → 9 LinkedSources.
    final mobileFlow = <Widget>[
      QuickFactsSection(media: media),
      progressBlock(),
      if (_hasCast) CastSection(media: media),
      if (showQuotes) QuotesSection(media: media, onQuotesJsonChanged: null),
      creatorBlock(),
      if (media.trailerVideoId != null && media.trailerVideoId!.isNotEmpty)
        TrailerSection(
            trailerVideoId: media.trailerVideoId, title: media.title),
      if (isBook) BookEditionSection(media: media),
      NotesSection(notes: media.notes, onEdit: onEdit),
      MediaFilesSection(
        mediaId: media.id,
        attachments: media.attachments ?? const <MediaAttachment>[],
        onChanged: onChanged,
      ),
      LinkedSourcesSection(
        mediaId: media.id,
        mediaType: _linkedSourcesType,
        media: media,
        onOpenRelink: onOpenRelink,
        onChanged: onChanged,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < mobileFlow.length; i++) ...[
          if (i > 0) const SizedBox(height: 20), // space-y-5
          mobileFlow[i],
        ],
      ],
    );
  }
}
