/// 1:1 port of
/// `mediatracker-ui/src/widgets/media-detail/tabs/RecommendationsTab.svelte`.
///
/// Галерея готовых `media.recommendations` — только рендер, без пикера
/// источника; сетка 2/3/4/5 колонок по ширине.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../entities/media/model/cover_url.dart';
import '../../../shared/i18n/index.dart';
import '../../../shared/theme/tsundoku_tokens.dart';
import '../detail_types.dart';

/// Таб «Рекомендации» (1-в-1 с RecommendationsTab.svelte).
class RecommendationsTab extends ConsumerWidget {
  /// Готовый `media.recommendations`.
  final List<RecommendationItem> items;

  const RecommendationsTab({super.key, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);

    if (items.isEmpty) {
      return Text(
        t.tr('detail.noRecommendations'),
        style: TextStyle(
          fontSize: 14, // text-sm
          color: th.textMuted, // text-muted
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    // grid-cols-2 sm:3 md:4 lg:5.
    final columns = width >= 1024
        ? 5
        : width >= 768
            ? 4
            : width >= 640
                ? 3
                : 2;
    final gap = 12.0; // gap-3
    final cardWidth =
        ((MediaQuery.sizeOf(context).width - 48 - gap * (columns - 1)) /
                columns)
            .clamp(120.0, 400.0);

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final rec in items)
          SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8), // rounded-lg
                    color: th.bgSurface, // panel-line
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AspectRatio(
                    aspectRatio: 2 / 3, // aspect-[2/3]
                    child: rec.coverUrl != null && rec.coverUrl!.isNotEmpty
                        ? Image.network(
                            proxiedExternalCoverUrl(rec.coverUrl!),
                            fit: BoxFit.cover,
                          )
                        : Center(
                            child: Icon(LucideIcons.image,
                                size: 24, color: th.textMuted),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6), // mt-1.5
                  child: Text(
                    rec.title,
                    maxLines: 1, // line-clamp-1
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w600, // font-semibold
                      color: Colors.white,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2), // mt-0.5
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rec.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11, // text-[11px]
                            color: th.textMuted, // text-muted
                          ),
                        ),
                      ),
                      if (rec.rating != null && rec.rating! > 0)
                        Text(
                          '★ ${rec.rating!.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700, // font-bold
                            color: Color(0xFFFBBF24), // text-amber-400
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
