/// 1:1 port of `mediatracker-ui/src/shared/ui/TotalBadge.svelte`.
///
/// Plain counter for toolbars: no pill, no border, no background.
/// i18n: library.resultCount(total) / resultCountWithShown(total, shown).
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/index.dart';

class TsundokuTotalBadge extends ConsumerWidget {
  /// Filtered total the badge counts.
  final int total;

  /// Items that actually reached the client; smaller than total explains the
  /// window.
  final int? shown;

  const TsundokuTotalBadge({super.key, required this.total, this.shown});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final shownValue = shown ?? total;
    final text = shownValue < total
        ? t.tf('library.resultCountWithShown', [total, shownValue])
        : t.tf('library.resultCount', [total]);
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Color(0x80FFFFFF), // text-white/50
        fontFeatures: [FontFeature.tabularFigures()], // tabular-nums
      ),
    );
  }
}
