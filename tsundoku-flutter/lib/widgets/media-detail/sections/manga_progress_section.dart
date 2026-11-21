/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/MangaProgressSection.svelte`.
///
/// Прогресс манги: главы, minsPerChapter из uiSettings (дефолт 6), amber.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/types/index.dart';
import '../../../shared/utils/ui_settings.dart';
import '../detail_types.dart';
import 'progress_card.dart';

/// Прогресс манги (1-в-1 с MangaProgressSection.svelte).
class MangaProgressSection extends ConsumerWidget {
  final MediaDetail media;
  final int totalChapters;
  final int currentChapter;
  final ProgressInfo progress;
  final int value;
  final double percent;
  final Object? error;
  final void Function(int delta) onStep;
  final void Function(int value)? onCounterChange;

  const MangaProgressSection({
    super.key,
    required this.media,
    required this.totalChapters,
    required this.currentChapter,
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
    final settings = ref.watch(uiSettingsProvider);

    final minsPerChapter =
        settings.mangaChapterMinutes > 0 ? settings.mangaChapterMinutes : 6.0;
    final effectiveTotal =
        totalChapters > 0 ? totalChapters : (progress.total ?? 0);

    return ProgressCard(
      label: t.tr('progress.unitsChapters'),
      unitShort: t.tr('progress.unitShortCh'),
      unitNoun: t.tr('progress.unitNounChapter'),
      accent: ProgressAccent.amber,
      value: value,
      total: effectiveTotal,
      percent: percent,
      minsPerUnit: minsPerChapter,
      doneLabel: t.tr('progress.readVerb'),
      remainLabel: t.tr('progress.remainReadVerb'),
      paceOptions: const [1, 2, 3, 5],
      paceDefault: 5,
      startHint: t.tr('progress.startChapters'),
      finishedAt: media.finishedAt,
      error: error,
      onStep: onStep,
      onCounterChange: onCounterChange,
    );
  }
}
