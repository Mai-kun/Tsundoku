/// Порт `mediatracker-ui/src/features/edit-media/modules/ModuleCard.svelte`.
///
/// Общая обёртка модульных карточек редактора: иконка, тайтл, опциональный
/// counter-чип и тело. Чисто презентационная — без стейта и API, поэтому
/// любой из шести модулей переиспользуется вне большого редактора с тем же
/// видом.
///
/// `flat` снимает рамку и headline-бар: хост (например, окно workspace) уже
/// рисует свою рамку и тайтл, поэтому модуль рендерит только маленький
/// section-лейбл и тело. `showLabel` прячет даже лейбл, если тайтл хоста
/// говорит то же самое.
library;

import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class ModuleCard extends StatelessWidget {
  final Widget icon;
  final String title;

  /// Опциональный бейдж рядом с тайтлом (число элементов).
  final int? count;
  final bool flat;
  final bool showLabel;
  final Widget child;

  const ModuleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.child,
    this.flat = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);

    if (flat) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel) ...[
            Row(
              children: [
                IconTheme.merge(
                  data: IconThemeData(
                      size: 14, color: th.textMuted), // text-muted
                  child: icon,
                ),
                const SizedBox(width: 6), // gap-1.5
                Flexible(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10, // text-[10px]
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4, // tracking-[0.14em]
                      color: th.textMuted,
                    ),
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10, // text-[10px]
                      fontWeight: FontWeight.w600,
                      color: th.textMuted.withAlpha(178), // text-muted/70
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10), // gap-2.5
          ],
          child,
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(
            color: Colors.white.withAlpha(15)), // border-white/[0.06]
        color: const Color(0xFF12151C), // bg-[#12151c]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28, // size-7
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                  color: Colors.white.withAlpha(10), // bg-white/[0.04]
                ),
                alignment: Alignment.center,
                child: IconTheme.merge(
                  data: IconThemeData(
                      size: 15, color: th.accentSoft), // text-accent-soft
                  child: icon,
                ),
              ),
              const SizedBox(width: 8), // gap-2
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.68, // tracking-[0.14em]
                    color: th.textPrimary, // text-ink
                  ),
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2), // px-2 py-0.5
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withAlpha(15), // bg-white/[0.06]
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFCBD5E1), // slate-300
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12), // gap-3
          child,
        ],
      ),
    );
  }
}
