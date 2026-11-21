/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/TvShowProgressSection.svelte`.
///
/// Прогресс сериала: минуты/серия (episodeDuration → durationMinutes → 24),
/// tooltip на total с разбивкой по сезонам, indigo-акцент.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/model/media_labels.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/types/index.dart';
import '../detail_types.dart';
import 'progress_card.dart';

/// Прогресс сериала (1-в-1 с TvShowProgressSection.svelte).
class TvShowProgressSection extends ConsumerWidget {
  final MediaDetail media;
  final int totalEpisodes;
  final int watchedEpisodes;
  final ProgressInfo progress;
  final int value;
  final double percent;
  final Object? error;
  final void Function(int delta) onStep;
  final void Function(int value)? onCounterChange;

  const TvShowProgressSection({
    super.key,
    required this.media,
    required this.totalEpisodes,
    required this.watchedEpisodes,
    required this.progress,
    required this.value,
    required this.percent,
    required this.error,
    required this.onStep,
    this.onCounterChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);

    final duration = (media.episodeDurationMinutes != null &&
            media.episodeDurationMinutes! > 0)
        ? media.episodeDurationMinutes!
        : (media.durationMinutes != null && media.durationMinutes! > 0
            ? media.durationMinutes!
            : 24);

    /// Все сезоны, когда detail-payload принёс их.
    final seasons = media.seasons ?? const <TvSeason>[];

    /// «Сезон 1: 220 · Сезон 2: 280» — tooltip на total, только для
    /// многосезонных.
    final String? totalTooltip = seasons.length > 1
        ? seasons
            .map((s) =>
                '${t.tf('progress.seasonN', [s.seasonNumber])}: ${formatNumber(s.totalEpisodes, locale)}')
            .join(' · ')
        : null;

    final effectiveTotal =
        totalEpisodes > 0 ? totalEpisodes : (progress.total ?? 0);

    return ProgressCard(
      label: t.tr('progress.unitsEpisodes'),
      unitShort: t.tr('progress.unitShortEp'),
      unitNoun: t.tr('progress.unitNounSeries'),
      accent: ProgressAccent.indigo,
      value: value,
      total: effectiveTotal,
      percent: percent,
      minsPerUnit: duration.toDouble(),
      doneLabel: t.tr('progress.watchedVerb'),
      remainLabel: t.tr('progress.remainWatchVerb'),
      paceOptions: const [1, 2, 3, 5],
      paceDefault: 2,
      startHint: t.tr('progress.startSeries'),
      totalTooltip: totalTooltip,
      finishedAt: media.finishedAt,
      error: error,
      onStep: onStep,
      onCounterChange: onCounterChange,
    );
  }
}
