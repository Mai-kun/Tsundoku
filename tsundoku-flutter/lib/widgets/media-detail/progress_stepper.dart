/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/ProgressStepper.svelte`.
///
/// Тонкая обёртка над ProgressCard дляgeneric-прогресса: label как unit,
/// акцент темы, без времени (minsPerUnit = null), pace-опции пустые.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import 'detail_types.dart';
import 'sections/progress_card.dart';

/// Универсальный степпер прогресса (episodes/chapters/pages).
class ProgressStepper extends ConsumerWidget {
  final ProgressInfo progress;
  final int value;
  final double percent;
  final Object? error;
  final void Function(int delta) onStep;
  final void Function(int value)? onCounterChange;

  const ProgressStepper({
    super.key,
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
    final total = progress.total ?? 0;

    return ProgressCard(
      label: progress.label,
      unitShort: '',
      accent: ProgressAccent.theme,
      value: value,
      total: total,
      percent: percent,
      minsPerUnit: null,
      doneLabel: progress.label,
      remainLabel: progress.label,
      paceOptions: const [],
      startHint: t.tr('progress.startGeneric'),
      error: error,
      onStep: onStep,
      onCounterChange: onCounterChange,
    );
  }
}
