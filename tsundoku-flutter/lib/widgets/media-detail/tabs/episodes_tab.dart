/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/tabs/EpisodesTab.svelte`.
///
/// Таб эпизодов: сводная карточка (кольцо, счётчик, next-up, mark-all),
/// сезонный сегмент-бар (≤60) / пропорциональные бары, риббон сезонов,
/// фильтры/массовые действия (two-tap reset guard), список серий.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/api/api.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../../../shared/types/index.dart';
import '../detail_types.dart';

const int _kSegmentLimit = 60;
const double _kRingRadius = 36;
const Color _kPurple = Color(0xFF8B7CF6); // #8b7cf6
const Color _kPurpleDeep = Color(0xFF7C6CF6); // #7c6cf6
const Color _kSegmentIdle = Color(0xFF222536); // #222536
const List<int> _kPaceOptions = [1, 2, 3, 5];

/// Таб «Эпизоды» (1-в-1 с EpisodesTab.svelte).
class EpisodesTab extends ConsumerStatefulWidget {
  final List<TvSeason> seasons;
  final NextUp? nextUp;
  final ({int current, int total}) seriesEpisodes;
  final double seriesProgressPercent;
  final Object? episodeBusy;
  final Object? progressError;
  final String sortOrder; // asc | desc
  final VoidCallback onToggleSort;
  final Future<void> Function(String seasonId) onToggleSeasonCompleteOf;
  final Future<void> Function(String seasonId, int number) onToggleEpisodeOf;
  final Future<void> Function(String seasonId, int number) onSetSeasonProgressOf;
  final Future<void> Function(NextUp target) onWatchNextUp;
  final void Function(int value) onSetSeriesCounter;
  final Future<void> Function() onMarkAll;
  final Future<void> Function() onResetAll;
  final VoidCallback onOpenLists;
  final String? Function(String? value) formatDate;
  final String? startedAt;
  final String? finishedAt;

  /// Per-episode runtime (minutes) для caption'ов времени.
  final int episodeDuration;

  /// Серии по сезонам, ключ — season id.
  final List<({TvSeason season, List<EpisodeRow> episodes})> episodesBySeason;

  const EpisodesTab({
    super.key,
    required this.seasons,
    required this.nextUp,
    required this.seriesEpisodes,
    required this.seriesProgressPercent,
    required this.episodeBusy,
    required this.progressError,
    required this.sortOrder,
    required this.onToggleSort,
    required this.onToggleSeasonCompleteOf,
    required this.onToggleEpisodeOf,
    required this.onSetSeasonProgressOf,
    required this.onWatchNextUp,
    required this.onSetSeriesCounter,
    required this.onMarkAll,
    required this.onResetAll,
    required this.onOpenLists,
    required this.formatDate,
    this.startedAt,
    this.finishedAt,
    this.episodeDuration = 24,
    this.episodesBySeason = const [],
  });

  @override
  ConsumerState<EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends ConsumerState<EpisodesTab> {
  int _pace = 2;
  String _activeSeasonId = '';
  _EpisodeFilter _filter = _EpisodeFilter.all;
  bool _resetArmed = false;
  Timer? _resetTimer;

  bool _isFinished(TvSeason season) =>
      season.totalEpisodes > 0 &&
      season.currentEpisode >= season.totalEpisodes;

  bool get _seriesFinished =>
      widget.seasons.isNotEmpty &&
      widget.seasons.every(
          (season) => season.totalEpisodes <= 0 || _isFinished(season));

  double get _pct =>
      math.min(100, math.max(0, widget.seriesProgressPercent));

  String _heading(I18nDictionary t) {
    if (widget.seasons.length > 1) {
      return t.tf('episodes.seriesHeading', [widget.seasons.length]);
    }
    final first = widget.seasons.firstOrNull;
    return first != null ? t.tf('progress.seasonN', [first.seasonNumber]) : '';
  }

  int get _watchedMinutes =>
      widget.seriesEpisodes.current * widget.episodeDuration;
  int get _remainingEpisodes =>
      math.max(0, widget.seriesEpisodes.total - widget.seriesEpisodes.current);
  int get _remainingMinutes => _remainingEpisodes * widget.episodeDuration;

  String _formatDuration(int minutes, I18nDictionary t) {
    final hours = minutes ~/ 60;
    final mins = (minutes % 60).round();
    if (hours > 0 && mins > 0) return t.tf('progress.durationHM', [hours, mins]);
    if (hours > 0) return t.tf('progress.durationH', [hours]);
    return t.tf('progress.durationM', [mins]);
  }

  String? _finishEstimate(I18nDictionary t, Locale locale) {
    final days = _pace > 0 && _remainingEpisodes > 0
        ? (_remainingEpisodes / _pace).ceil()
        : null;
    if (days == null) return null;
    initializeDateFormatting(locale.wire, null);
    final label = DateFormat('d MMMM', locale.wire)
        .format(DateTime.now().add(Duration(days: days)));
    return t.tf('progress.finishAt', [label, days]);
  }

  /// Сегменты: ≤60 серий — по сегменту на эпизод.
  List<({String seasonId, int seasonNumber, int episode, int cumulative})>
      get _segments {
    if (widget.seriesEpisodes.total <= 0 ||
        widget.seriesEpisodes.total > _kSegmentLimit) {
      return const [];
    }
    final out = <({String seasonId, int seasonNumber, int episode, int cumulative})>[];
    var cumulative = 0;
    for (final season in widget.seasons) {
      if (season.totalEpisodes <= 0) continue;
      for (var episode = 1; episode <= season.totalEpisodes; episode += 1) {
        cumulative += 1;
        out.add((
          seasonId: season.id,
          seasonNumber: season.seasonNumber,
          episode: episode,
          cumulative: cumulative,
        ));
      }
    }
    return out;
  }

  List<TvSeason> get _seasonBars =>
      widget.seriesEpisodes.total > _kSegmentLimit
          ? widget.seasons.where((s) => s.totalEpisodes > 0).toList()
          : const [];

  void _clickSegment(
      ({String seasonId, int seasonNumber, int episode, int cumulative}) seg) {
    // Клик по последнему просмотренному — unwatch; иначе mark-through.
    final target = seg.cumulative == widget.seriesEpisodes.current
        ? seg.cumulative - 1
        : seg.cumulative;
    widget.onSetSeriesCounter(math.max(0, target));
  }

  TvSeason? get _activeSeason {
    return widget.seasons
            .where((season) => season.id == _activeSeasonId)
            .firstOrNull ??
        widget.seasons.firstOrNull;
  }

  List<EpisodeRow> get _activeRowsRaw {
    final active = _activeSeason;
    if (active == null) return const [];
    return widget.episodesBySeason
            .where((view) => view.season.id == active.id)
            .map((view) => view.episodes)
            .firstOrNull ??
        const [];
  }

  List<EpisodeRow> get _activeRows {
    final ordered =
        widget.sortOrder == 'asc' ? _activeRowsRaw : [..._activeRowsRaw].reversed.toList();
    switch (_filter) {
      case _EpisodeFilter.watched:
        return ordered.where((row) => row.watched).toList();
      case _EpisodeFilter.unwatched:
        return ordered.where((row) => !row.watched).toList();
      case _EpisodeFilter.all:
        return ordered;
    }
  }

  bool get _activeDatesVary {
    final dates = _activeRowsRaw
        .map((row) => row.airDate)
        .whereType<String>()
        .toList();
    return dates.isNotEmpty && dates.toSet().length > 1;
  }

  bool _isNextUp(EpisodeRow episode) =>
      widget.nextUp != null &&
      widget.nextUp!.seasonId == _activeSeason?.id &&
      widget.nextUp!.episodeNumber == episode.number;

  void _requestReset(I18nDictionary t) {
    if (!_resetArmed) {
      setState(() => _resetArmed = true);
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(milliseconds: 4000), () {
        if (mounted) setState(() => _resetArmed = false);
      });
      return;
    }
    _resetArmed = false;
    _resetTimer?.cancel();
    widget.onResetAll();
  }

  @override
  void didUpdateWidget(covariant EpisodesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect-аналог: active season — первый непросмотренный.
    if (widget.seasons.isNotEmpty &&
        !widget.seasons.any((season) => season.id == _activeSeasonId)) {
      final firstUnwatched = widget.seasons.firstWhereOrNull(
        (season) =>
            season.totalEpisodes > 0 &&
            season.currentEpisode < season.totalEpisodes,
      );
      _activeSeasonId = (firstUnwatched ?? widget.seasons.first).id;
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    if (widget.seasons.isEmpty) return const SizedBox.shrink();

    // Активный сезон (первый непросмотренный) — при первом билде.
    if (!widget.seasons.any((season) => season.id == _activeSeasonId)) {
      final firstUnwatched = widget.seasons.firstWhereOrNull(
        (season) =>
            season.totalEpisodes > 0 &&
            season.currentEpisode < season.totalEpisodes,
      );
      _activeSeasonId = (firstUnwatched ?? widget.seasons.first).id;
    }

    final heading = _heading(t);
    final busy = widget.episodeBusy != null;
    final segments = _segments;
    final seasonBars = _seasonBars;
    final activeRows = _activeRows;
    final activeAll = _activeRowsRaw.length;
    final activeWatched =
        _activeRowsRaw.where((row) => row.watched).length;
    final finishEstimate = _finishEstimate(t, locale);

    String cleanEpisodeTitle(String title) {
      final pattern = RegExp(
        r'^(?:Episode|Ep\.?|Серия|Эпизод)\s*\d+\s*[-–—:.]\s*',
        caseSensitive: false,
      );
      final cleaned = title.replaceFirst(pattern, '').trim();
      return cleaned.isNotEmpty ? cleaned : title;
    }

    final sections = <Widget>[
      // 1. Сводная карточка.
      Container(
        padding: const EdgeInsets.all(20), // p-5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(color: Colors.white.withAlpha(15)),
          color: th.bgSurface, // panel-line
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Кольцо 80px.
                SizedBox(
                  width: 80, // size-20
                  height: 80,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: const Size.square(80),
                        painter: _EpisodesRingPainter(percent: _pct),
                      ),
                      Center(
                        child: Text(
                          '${_pct.round()}%',
                          style: const TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w700, // font-bold
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16), // gap-4
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12, // text-xs
                          fontWeight: FontWeight.w700, // font-bold
                          letterSpacing: 0.6, // tracking-wider
                          color: Color(0xFFCBD5E1), // text-slate-300
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${widget.seriesEpisodes.current}',
                              style: const TextStyle(
                                fontSize: 30, // text-[30px]
                                height: 1.0, // leading-none
                                fontWeight: FontWeight.w800, // font-extrabold
                                color: Colors.white,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  / ${widget.seriesEpisodes.total} ${t.tr('progress.unitShortEp')}',
                              style: TextStyle(
                                fontSize: 18, // text-lg
                                fontWeight: FontWeight.w600, // font-semibold
                                color: th.textMuted, // text-muted
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Next-up / completed / mark all.
                Wrap(
                  spacing: 6, // gap-1.5
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.nextUp != null)
                      _NextUpButton(
                        label:
                            '${t.tr('detail.bannerNextEpisode')} S${widget.nextUp!.seasonNumber}E${widget.nextUp!.episodeNumber}',
                        tooltip: t.tr('detail.bannerNextEpisode'),
                        disabled: busy,
                        onTap: () =>
                            widget.onWatchNextUp(widget.nextUp!),
                      )
                    else if (_seriesFinished)
                      Container(
                        height: 36, // h-9
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12), // px-3
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  const Color(0x4D34D399)), // emerald-400/30
                          color:
                              const Color(0x1A34D399), // emerald-400/10
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.circleCheck,
                                size: 14, color: Color(0xFF6EE7B7)),
                            const SizedBox(width: 6), // gap-1.5
                            Text(
                              t.tr('detail.bannerCompleted'),
                              style: const TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w700, // font-bold
                                color: Color(0xFF6EE7B7), // emerald-300
                              ),
                            ),
                          ],
                        ),
                      ),
                    _MarkAllButton(
                      label: t.tr('episodes.markAll'),
                      disabled: _seriesFinished || busy,
                      onTap: widget.onMarkAll,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16), // space-y-4
            // Сегменты/бары сезонов.
            if (segments.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 16), // my-4
                child: Row(
                  children: [
                    for (final season in widget.seasons)
                      if (season.totalEpisodes > 0)
                        Expanded(
                          flex: season.totalEpisodes,
                          child: Row(
                            children: [
                              for (final seg in segments
                                  .where((s) => s.seasonId == season.id))
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _clickSegment(seg),
                                    child: Tooltip(
                                      message:
                                          'S${seg.seasonNumber}E${seg.episode}',
                                      child: Container(
                                        height: 10, // h-2.5
                                        margin: const EdgeInsets.only(
                                            right: 3), // gap-[3px]
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          color: seg.cumulative <=
                                                  widget.seriesEpisodes.current
                                              ? _kPurpleDeep
                                              : seg.cumulative ==
                                                      widget.seriesEpisodes
                                                          .current +
                                                          1
                                                  ? _kPurple
                                                      .withAlpha(128) // /50
                                                  : Colors.white.withAlpha(26), // bg-white/10 контрастный трек
                                          border: seg.cumulative ==
                                                  widget.seriesEpisodes
                                                      .current +
                                                      1
                                              ? Border.all(
                                                  color: _kPurple, width: 1.5)
                                              : null,
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
              )
            else if (seasonBars.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 16), // my-4
                child: Row(
                  children: [
                    for (final season in seasonBars)
                      Expanded(
                        flex: season.totalEpisodes,
                        child: _SeasonBar(
                          season: season,
                          finished: _isFinished(season),
                          t: t,
                          onTap: (value) {
                            if (value == season.currentEpisode) return;
                            widget.onSetSeasonProgressOf(
                                season.id, value);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            // Статистика.
            Wrap(
              spacing: 20, // gap-x-5
              runSpacing: 4, // gap-y-1
              children: [
                Text.rich(
                  TextSpan(
                    text: '${t.tr('progress.watchedVerb')} ',
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      color: th.textMuted, // text-muted
                    ),
                    children: [
                      TextSpan(
                        text: _formatDuration(_watchedMinutes, t),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600, // font-semibold
                          color: Color(0xFFE2E8F0), // text-slate-200
                        ),
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: '${t.tr('progress.remainingTimeLabel')} ',
                    style: TextStyle(
                      fontSize: 12,
                      color: th.textMuted,
                    ),
                    children: [
                      TextSpan(
                        text: _formatDuration(_remainingMinutes, t),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: '${t.tr('detail.startedLabel')}: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: th.textMuted,
                    ),
                    children: [
                      TextSpan(
                        text: widget.formatDate(widget.startedAt) ?? '—',
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.finishedAt != null)
                  Text.rich(
                    TextSpan(
                      text: '${t.tr('detail.endedLabel')}: ',
                      style: TextStyle(
                        fontSize: 12,
                        color: th.textMuted,
                      ),
                      children: [
                        TextSpan(
                          text: widget.formatDate(widget.finishedAt) ?? '—',
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.episodeDuration > 0)
                  Text(
                    '${widget.episodeDuration} ${t.tr('detail.minPerEp')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: th.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            if (_remainingEpisodes > 0)
              // Pace-прогноз — отдельная строка (tool, not a fact).
              Container(
                margin: const EdgeInsets.only(top: 12), // mt-3
                padding: const EdgeInsets.only(top: 12), // pt-3
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Color(0x0DFFFFFF))), // white/5
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(LucideIcons.clock,
                          size: 13, color: _kPurple), // #8b7cf6
                      const SizedBox(width: 6),
                      Text(
                        '${t.tr('progress.paceLabel')}:',
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted, // text-muted
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (final p in _kPaceOptions) ...[
                        _PaceChip(
                          value: p,
                          selected: _pace == p,
                          onTap: () => setState(() => _pace = p),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        t.tr('episodes.perDay'),
                        style: TextStyle(
                          fontSize: 12,
                          color: th.textMuted,
                        ),
                      ),
                      if (finishEstimate != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '→ $finishEstimate',
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            color: Color(0xFFCBD5E1), // text-slate-300
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      // 2. Риббон сезонов (только при >1).
      if (widget.seasons.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal, // overflow-x-auto
          child: Wrap(
            spacing: 8, // gap-2
            children: [
              for (final season in widget.seasons)
                _SeasonRibbonCard(
                  season: season,
                  active: season.id == _activeSeasonId,
                  finished: _isFinished(season),
                  t: t,
                  th: th,
                  onTap: () => setState(() => _activeSeasonId = season.id),
                ),
            ],
          ),
        ),
      // 3. Фильтры + массовые действия.
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10), // px-3.5 py-2.5
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12), // rounded-xl
          border: Border.all(color: Colors.white.withAlpha(15)),
          color: th.bgSurface, // panel-line
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final filterChips = <Widget>[
              for (final f in [
                (_EpisodeFilter.all, t.tr('episodes.filterAll'), activeAll),
                (
                  _EpisodeFilter.unwatched,
                  t.tr('episodes.filterUnwatched'),
                  activeAll - activeWatched
                ),
                (
                  _EpisodeFilter.watched,
                  t.tr('episodes.filterWatched'),
                  activeWatched
                ),
              ])
                _FilterChip(
                  label: '${f.$2} (${f.$3})',
                  selected: _filter == f.$1,
                  onTap: () => setState(() => _filter = f.$1),
                ),
            ];

            final actionButtons = <Widget>[
              _SortButton(
                label: widget.sortOrder == 'asc'
                    ? t.tr('episodes.sortOldFirst')
                    : t.tr('episodes.sortNewFirst'),
                tooltip: t.tr('episodes.sortTitle'),
                onToggle: widget.onToggleSort,
                th: th,
              ),
              if (_activeSeason != null && widget.seasons.length > 1)
                _SeasonToggleTextButton(
                  finished: _isFinished(_activeSeason!),
                  disabled: busy || _activeSeason!.totalEpisodes <= 0,
                  markLabel: t.tr('episodes.markSeason'),
                  unmarkLabel: t.tr('episodes.unmarkSeason'),
                  onTap: () => widget
                      .onToggleSeasonCompleteOf(_activeSeason!.id),
                ),
              if (_resetArmed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ConfirmResetButton(
                      disabled: widget.seriesEpisodes.current == 0 || busy,
                      label: t.tr('episodes.confirmReset'),
                      onTap: () => _requestReset(t),
                    ),
                    const SizedBox(width: 6), // gap-1.5
                    GestureDetector(
                      onTap: () => setState(() => _resetArmed = false),
                      child: Text(
                        t.tr('common.cancel'),
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted, // text-muted
                        ),
                      ),
                    ),
                  ],
                )
              else
                _ResetAllButton(
                  disabled: widget.seriesEpisodes.current == 0 || busy,
                  label: t.tr('episodes.resetAll'),
                  onTap: () => _requestReset(t),
                ),
            ];

            if (constraints.maxWidth >= 640) {
              return Row(
                children: [
                  Wrap(
                    spacing: 8, // gap-2
                    runSpacing: 8,
                    children: filterChips,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actionButtons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8), // gap-2
                        actionButtons[i],
                      ],
                    ],
                  ),
                ],
              );
            }

            return Wrap(
              spacing: 8, // gap-2
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...filterChips,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actionButtons.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8), // gap-2
                      actionButtons[i],
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
      // 4. Список серий активного сезона.
      Column(
        children: [
          if (activeRows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 24), // px-4 py-6
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12), // rounded-xl
                border: Border.all(color: Colors.white.withAlpha(15)),
                color: th.bgSurface, // panel-line
              ),
              child: Text(
                activeAll == 0
                    ? t.tr('episodes.noEpisodes')
                    : t.tr('common.noData'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14, // text-sm
                  color: th.textMuted, // text-muted
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints:
                  const BoxConstraints(maxHeight: 560), // max-h-[560px]
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final episode in activeRows)
                      _EpisodeRowWidget(
                        episode: episode,
                        watched: episode.watched,
                        next: _isNextUp(episode),
                        datesVary: _activeDatesVary,
                        busy: busy,
                        formatDate: widget.formatDate,
                        cleanTitle: cleanEpisodeTitle,
                        seasonId: _activeSeason?.id ?? '',
                        markUpToLabel: t.tr('episodes.markUpTo'),
                        nextBadgeLabel: t.tr('episodes.nextBadge'),
                        unwatchLabel: t.tr('detail.unwatchAction'),
                        markWatchedLabel: t.tr('detail.markWatched'),
                        th: th,
                        onMarkUpTo: () => widget.onSetSeasonProgressOf(
                            _activeSeason?.id ?? '', episode.number),
                        onToggle: () => widget.onToggleEpisodeOf(
                            _activeSeason?.id ?? '', episode.number),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.progressError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16), // space-y-4
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorMessage(widget.progressError!, locale),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  color: Color(0xFFFDA4AF), // text-rose-300
                ),
              ),
            ),
          ),
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 16), // space-y-4
          sections[i],
        ],
      ],
    );
  }
}

enum _EpisodeFilter { all, unwatched, watched }

/// Кольцо сводной карточки: 80px, stroke 7, #8b7cf6.
class _EpisodesRingPainter extends CustomPainter {
  final double percent;
  _EpisodesRingPainter({required this.percent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = Colors.white.withAlpha(18); // stroke-white/[0.07]
    canvas.drawCircle(center, _kRingRadius, track);

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = _kPurple;
    final rect = Rect.fromCircle(center: center, radius: _kRingRadius);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * percent / 100, false,
        progress);
  }

  @override
  bool shouldRepaint(_EpisodesRingPainter old) => old.percent != percent;
}

/// Кнопка next-up: bg-[#8b7cf6], Play.
class _NextUpButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool disabled;
  final VoidCallback onTap;

  const _NextUpButton({
    required this.label,
    required this.tooltip,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 36, // h-9
          padding: const EdgeInsets.symmetric(horizontal: 14), // px-3.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            color: disabled ? _kPurple.withAlpha(153) : _kPurple,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.play, size: 13, color: Colors.white),
              const SizedBox(width: 6), // gap-1.5
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w700, // font-bold
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mark all: border-white/10 px-2.5 text-xs.
class _MarkAllButton extends StatelessWidget {
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  const _MarkAllButton({
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            height: 36, // h-9
            padding:
                const EdgeInsets.symmetric(horizontal: 10), // px-2.5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withAlpha(26)), // /10
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: disabled
                      ? const Color(0xFFCBD5E1).withAlpha(153)
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

/// Пропорциональный бар сезона: клик по позиции → абсолютное значение.
class _SeasonBar extends StatelessWidget {
  final TvSeason season;
  final bool finished;
  final I18nDictionary t;
  final void Function(int value) onTap;

  const _SeasonBar({
    required this.season,
    required this.finished,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8), // gap-2
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onTapUp: (details) {
            if (width <= 0) return;
            final ratio =
                (details.localPosition.dx / width).clamp(0.0, 1.0);
            final value = (ratio * season.totalEpisodes).round();
            onTap(value);
          },
          child: Tooltip(
            message:
                '${t.tf('progress.seasonN', [season.seasonNumber])} · ${season.currentEpisode}/${season.totalEpisodes}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4), // rounded-[4px]
              child: Container(
                height: 10, // h-2.5
                color: _kSegmentIdle,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.centerLeft,
                    widthFactor: (season.currentEpisode / season.totalEpisodes)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    heightFactor: 1,
                    child: Container(
                      color: finished
                          ? const Color(0xB334D399) // emerald-400/70
                          : _kPurpleDeep,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Pace-чип: h-5 min-w-6, [10px] bold.
class _PaceChip extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _PaceChip({required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected, // aria-pressed
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 20, // h-5
          constraints: const BoxConstraints(minWidth: 24), // min-w-6
          padding: const EdgeInsets.symmetric(horizontal: 4), // px-1
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4), // rounded
            border: Border.all(
              color: selected
                  ? _kPurple.withAlpha(153) // border-[#8b7cf6]/60
                  : Colors.white.withAlpha(26), // border-white/10
            ),
            color: selected
                ? _kPurple.withAlpha(38) // bg-[#8b7cf6]/15
                : Colors.transparent,
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 10, // text-[10px]
                fontWeight: FontWeight.w700, // font-bold
                color: selected ? _kPurple : const Color(0xFF94A3B8), // slate-400
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Риббон-карточка сезона: w-28, 4px progress rail.
class _SeasonRibbonCard extends StatelessWidget {
  final TvSeason season;
  final bool active;
  final bool finished;
  final I18nDictionary t;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _SeasonRibbonCard({
    required this.season,
    required this.active,
    required this.finished,
    required this.t,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 112, // w-28
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), // rounded-lg
          border: Border.all(
            color: active
                ? _kPurple.withAlpha(128) // border-[#8b7cf6]/50
                : Colors.white.withAlpha(15), // /[0.06]
          ),
          color: active
              ? _kPurple.withAlpha(26) // bg-[#8b7cf6]/10
              : th.bgSurface, // panel-line
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.tf('progress.seasonN', [season.seasonNumber]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w700, // font-bold
                color: Colors.white,
              ),
            ),
            Text(
              t.tf('card.episodes', [season.currentEpisode, season.totalEpisodes]),
              style: TextStyle(
                fontSize: 11, // text-[11px]
                color: th.textMuted, // text-muted
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6), // mt-1.5
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 4, // h-1
                color: Colors.white.withAlpha(21), // /[0.08]
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: season.totalEpisodes > 0
                        ? math.min(
                            1,
                            season.currentEpisode / season.totalEpisodes,
                          )
                        : 0,
                    heightFactor: 1,
                    child: Container(
                      color: finished
                          ? const Color(0xFF34D399) // emerald-400
                          : _kPurple,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Чип фильтра: rounded-full px-2.5 py-1.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected, // aria-pressed
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // px-2.5 py-1
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999), // rounded-full
            color: selected ? _kPurple.withAlpha(38) : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w600, // font-semibold
              color: selected ? _kPurple : const Color(0xFF94A3B8), // slate-400
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка сортировки: bg-surface/50, ArrowUpDown.
class _SortButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onToggle;
  final TsundokuTheme th;

  const _SortButton({
    required this.label,
    required this.tooltip,
    required this.onToggle,
    required this.th,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          height: 28, // h-7
          padding: const EdgeInsets.symmetric(horizontal: 8), // px-2
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: Border.all(color: Colors.white.withAlpha(21)), // /[0.08]
            color: th.bgSurface.withAlpha(128), // bg-surface/50
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.arrowUpDown,
                  size: 12, color: _kPurple),
              const SizedBox(width: 4), // gap-1
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Текстовая кнопка mark/unmark сезона.
class _SeasonToggleTextButton extends StatelessWidget {
  final bool finished;
  final bool disabled;
  final String markLabel;
  final String unmarkLabel;
  final VoidCallback onTap;

  const _SeasonToggleTextButton({
    required this.finished,
    required this.disabled,
    required this.markLabel,
    required this.unmarkLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Text(
        finished ? unmarkLabel : markLabel,
        style: TextStyle(
          fontSize: 12, // text-xs
          fontWeight: FontWeight.w600, // font-semibold
          color: finished
              ? const Color(0xFF94A3B8) // text-slate-400
              : const Color(0xFF6EE7B7), // text-emerald-300
        ),
      ),
    );
  }
}

/// Armed confirm-кнопка: rose.
class _ConfirmResetButton extends StatelessWidget {
  final bool disabled;
  final String label;
  final VoidCallback onTap;

  const _ConfirmResetButton({
    required this.disabled,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // px-2 py-1
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6), // rounded-md
          border: Border.all(
              color: const Color(0x66F43F5E)), // border-rose-500/40
          color: const Color(0x26F43F5E), // bg-rose-500/15
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12, // text-xs
            fontWeight: FontWeight.w700, // font-bold
            color: Color(0xFFFDA4AF), // text-rose-300
          ),
        ),
      ),
    );
  }
}

/// Reset all: muted → hover rose.
class _ResetAllButton extends StatelessWidget {
  final bool disabled;
  final String label;
  final VoidCallback onTap;

  const _ResetAllButton({
    required this.disabled,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12, // text-xs
            color: disabled
                ? const Color(0xFF94A3B8).withAlpha(153)
                : const Color(0xFF94A3B8), // text-muted
          ),
        ),
      ),
    );
  }
}

/// Строка серии: E-бейдж, заголовок, mark-up-to, toggle-кнопка.
class _EpisodeRowWidget extends StatefulWidget {
  final EpisodeRow episode;
  final bool watched;
  final bool next;
  final bool datesVary;
  final bool busy;
  final String? Function(String?) formatDate;
  final String Function(String) cleanTitle;
  final String seasonId;
  final String markUpToLabel;
  final String nextBadgeLabel;
  final String unwatchLabel;
  final String markWatchedLabel;
  final TsundokuTheme th;
  final VoidCallback onMarkUpTo;
  final VoidCallback onToggle;

  const _EpisodeRowWidget({
    required this.episode,
    required this.watched,
    required this.next,
    required this.datesVary,
    required this.busy,
    required this.formatDate,
    required this.cleanTitle,
    required this.seasonId,
    required this.markUpToLabel,
    required this.nextBadgeLabel,
    required this.unwatchLabel,
    required this.markWatchedLabel,
    required this.th,
    required this.onMarkUpTo,
    required this.onToggle,
  });

  @override
  State<_EpisodeRowWidget> createState() => _EpisodeRowWidgetState();
}

class _EpisodeRowWidgetState extends State<_EpisodeRowWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tooltipLabel = widget.watched ? widget.unwatchLabel : widget.markWatchedLabel;
    final th = widget.th;
    final episode = widget.episode;
    final watched = widget.watched;
    final next = widget.next;
    final busy = widget.busy;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6), // space-y-1.5
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), // rounded-lg
          border: Border.all(
            color: next
                ? _kPurple.withAlpha(77) // border-[#8b7cf6]/30
                : Colors.white.withAlpha(13), // border-white/5
          ),
          color: next
              ? _kPurple.withAlpha(15) // bg-[#8b7cf6]/[0.06]
              : th.bgSurface, // panel-line
        ),
        child: Row(
          children: [
            // E-бейдж.
            Container(
              width: 36, // size-9
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8), // rounded-lg
                color: next
                    ? _kPurple // bg-[#8b7cf6]
                    : watched
                        ? Colors.white.withAlpha(13) // bg-white/[0.05]
                        : th.bgSurface, // color-field
              ),
              child: Center(
                child: Text(
                  'E${episode.number}',
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700, // font-bold
                    color: next
                        ? Colors.white
                        : watched
                            ? th.textMuted // text-muted
                            : const Color(0xFFCBD5E1), // text-slate-300
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12), // gap-3
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.cleanTitle(episode.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w600, // font-semibold
                            color: watched
                                ? th.textMuted // text-muted без line-through
                                : Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      if (next)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2), // px-1.5 py-0.5
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: _kPurple.withAlpha(102)), // /40
                            color: _kPurple.withAlpha(38), // /15
                          ),
                          child: Text(
                            widget.nextBadgeLabel,
                            style: const TextStyle(
                              fontSize: 10, // text-[10px]
                              fontWeight: FontWeight.w700, // font-bold
                              color: _kPurple,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (widget.datesVary && episode.airDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2), // mt-0.5
                      child: Text(
                        widget.formatDate(episode.airDate) ?? '',
                        style: TextStyle(
                          fontSize: 11, // text-[11px]
                          color: th.textMuted, // text-muted
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!watched)
              Opacity(
                opacity: _hovered ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: _MarkUpToButton(
                    label: widget.markUpToLabel,
                    disabled: busy,
                    onTap: widget.onMarkUpTo,
                  ),
                ),
              ),
            const SizedBox(width: 12), // gap-3
            // Toggle-кнопка: размер 8, emerald для просмотренных.
            Semantics(
              button: true,
              label: tooltipLabel,
              child: Tooltip(
                message: tooltipLabel,
                child: GestureDetector(
                  onTap: busy ? null : widget.onToggle,
                  child: Container(
                    width: 32, // size-8
                    height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      width: 1,
                      color: watched
                          ? const Color(0x6634D399) // border-emerald-400/40
                          : Colors.white.withAlpha(31), // /[0.12]
                    ),
                    color: watched
                        ? const Color(0x3334D399) // bg-emerald-400/20
                        : th.bgSurface, // color-field
                  ),
                  child: watched
                      ? const Icon(LucideIcons.check,
                          size: 15, color: Color(0xFF34D399)) // emerald-400
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

/// Mark-up-to: border-white/10, hover.
class _MarkUpToButton extends StatelessWidget {
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  const _MarkUpToButton({
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // px-2 py-1
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: Border.all(color: Colors.white.withAlpha(26)), // /10
          ),
          child: Text(
            '✓ $label',
            style: TextStyle(
              fontSize: 11, // text-[11px]
              fontWeight: FontWeight.w500, // font-medium
              color: disabled
                  ? const Color(0xFFCBD5E1).withAlpha(153)
                  : const Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
        ),
      ),
    );
  }
}
