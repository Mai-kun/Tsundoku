/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/sections/BookProgressSection.svelte`.
///
/// Прогресс книги: страницы (romanobэ/новеллы — главы, 6 мин/глава), темп
/// [10,20,30,50] страниц или [1,2,3,5] глав, amber-акцент.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../../../shared/utils/ui_settings.dart';
import '../detail_types.dart';
import 'progress_card.dart';

/// Прогресс книги (1-в-1 с BookProgressSection.svelte).
class BookProgressSection extends ConsumerWidget {
  final int totalPages;
  final int currentPage;
  final String? format;
  final int? totalChapters;
  final int? currentChapter;
  final String? finishedAt;
  final ProgressInfo progress;
  final int value;
  final double percent;
  final Object? error;
  final void Function(int delta) onStep;
  final void Function(int value)? onCounterChange;

  const BookProgressSection({
    super.key,
    required this.totalPages,
    required this.currentPage,
    this.format,
    this.totalChapters,
    this.currentChapter,
    required this.finishedAt,
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

    final isNovel = format == 'light_novel' || format == 'web_novel';
    final minsPerUnit = isNovel ? 6.0 : settings.bookPageMinutes;

    final effectiveTotal = isNovel
        ? (totalChapters != null && totalChapters! > 0
            ? totalChapters!
            : (progress.total ?? 0))
        : (totalPages > 0 ? totalPages : (progress.total ?? 0));

    return ProgressCard(
      label: isNovel ? t.tr('progress.unitsChapters') : t.tr('progress.unitsPages'),
      unitShort: isNovel ? t.tr('progress.unitShortCh') : t.tr('progress.unitShortPg'),
      unitNoun: isNovel
          ? t.tr('progress.unitNounChapter')
          : t.tr('progress.unitNounPage'),
      accent: ProgressAccent.amber,
      value: value,
      total: effectiveTotal,
      percent: percent,
      minsPerUnit: minsPerUnit,
      doneLabel: t.tr('progress.readVerb'),
      remainLabel: t.tr('progress.remainReadVerb'),
      paceOptions: isNovel ? const [1, 2, 3, 5] : const [10, 20, 30, 50],
      paceDefault: isNovel ? 3 : 20,
      startHint: isNovel ? t.tr('progress.startChapters') : t.tr('progress.startPages'),
      finishedAt: finishedAt,
      error: error,
      onStep: onStep,
      onCounterChange: onCounterChange,
    );
  }
}
