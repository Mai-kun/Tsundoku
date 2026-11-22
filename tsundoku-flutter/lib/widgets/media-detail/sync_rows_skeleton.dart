/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/SyncRowsSkeleton.svelte`.
///
/// Скелетон трёх строк синхронизации (animate-pulse), label — для скринридера
/// (role=status).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/theme/tsundoku_tokens.dart';

/// Скелетон синхронизации (1-в-1 с SyncRowsSkeleton.svelte).
class SyncRowsSkeleton extends ConsumerStatefulWidget {
  final String label;

  const SyncRowsSkeleton({super.key, required this.label});

  @override
  ConsumerState<SyncRowsSkeleton> createState() => _SyncRowsSkeletonState();
}

class _SyncRowsSkeletonState extends ConsumerState<SyncRowsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500), // animate-pulse ~1.5s
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // aria-hidden="true": визуальные строки вне семантики.
        ExcludeSemantics(
          child: Column(
            children: [
              for (var row = 0; row < 3; row++)
                FadeTransition(
                  opacity: _pulse.drive(
                    Tween(begin: 0.5, end: 1.0),
                  ),
                  child: Opacity(
                    opacity: row == 1 ? 0.8 : 1.0, // row === 1 → opacity-80
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12), // space-y-3
                      padding: const EdgeInsets.all(12), // p-3
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8), // rounded-lg
                        border: Border.all(
                            color: Colors.white.withAlpha(15)), // /[0.06]
                        color: th.bgCard, // bg-card
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36, // w-9
                            height: 48, // h-12
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: Colors.white.withAlpha(15),
                            ),
                          ),
                          const SizedBox(width: 12), // gap-3
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: (88 - row * 16) / 100,
                                  child: Container(
                                    height: 12, // h-3
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(4), // rounded
                                      color:
                                          Colors.white.withAlpha(20), // /[0.08]
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8), // space-y-2
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 0.4, // w-2/5
                                  child: Container(
                                    height: 10, // h-2.5
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color:
                                          Colors.white.withAlpha(13), // /[0.05]
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
        // role="status" sr-only.
        Semantics(
          liveRegion: true,
          label: widget.label,
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
