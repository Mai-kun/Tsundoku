/// 1:1 port of `mediatracker-ui/src/entities/media/ui/MediaScoreBadge.svelte`.
///
/// Круглая бейдж-оценка: bg-score-bg (#4a63c9), 2.33rem, text-[17px]
/// font-black tracking-tight tabular-nums, shadow-lg. Рендерится только при
/// `score !== null && score > 0`; title → Tooltip.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/i18n/index.dart';
import '../model/media_labels.dart';

class MediaScoreBadge extends ConsumerWidget {
  /// Svelte: `number | null` → num? (MediaItem.score — int?, поисковые модели
  /// шлют дробные — num покрывает оба контракта).
  final num? score;

  const MediaScoreBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = score;
    if (s == null || s <= 0) return const SizedBox.shrink();

    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final formatted = formatNumber(s, locale);

    return Tooltip(
      // title={`${i18n.t.createModal.fields.score}: ${score}`}
      message: '${t.tr('createModal.fields.score')}: ${_titleNumber(s)}',
      child: Transform.translate(
        // -ml-2: круг перекрывает правый край статус-кнопки на 8px (z-10 —
        // рисуется поверх: поздний ребёнок Row).
        offset: const Offset(-8, 0),
        child: Container(
          width: 37.28, // h-[2.33rem] w-[2.33rem] @ 16px/rem
          height: 37.28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF4A63C9), // bg-score-bg (--color-score-bg)
            shape: BoxShape.circle,
            boxShadow: [
              // shadow-lg: 0 10px 15px -3px rgb(0 0 0/0.1),
              //            0 4px 6px -4px rgb(0 0 0/0.1)
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
          child: Text(
            formatted,
            style: const TextStyle(
              fontSize: 17, // text-[17px]
              fontWeight: FontWeight.w900, // font-black
              // tracking-tight = -0.025em @ 17px
              letterSpacing: -0.425,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()], // tabular-nums
            ),
          ),
        ),
      ),
    );
  }
}

/// title-атрибут Svelte интерполирует сырой score (`${score}`), не
/// Intl-формат — фиксируем 1-в-1 (8.5 → «8.5», не «8,5»).
String _titleNumber(num s) =>
    s == s.roundToDouble() ? s.round().toString() : s.toString();
