/// Порт
/// `mediatracker-ui/src/features/edit-media/modules/CategoryFieldsModule.svelte`.
///
/// Block 5 — тип-специфичные поля, делегирующие существующим форм-компонентам
/// по категориям. Весь бандл едет через один bindable-объект `category`. Для
/// существующего тайтла строки сезонов read-only: контракт обновления не
/// имеет записи сезонов, сезоны редактируются на странице сериала.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/create-media/book_form_fields.dart';
import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/features/create-media/game_form_fields.dart';
import 'package:tsundoku_flutter/features/create-media/manga_form_fields.dart';
import 'package:tsundoku_flutter/features/create-media/movie_form_fields.dart';
import 'package:tsundoku_flutter/features/create-media/tvshow_form_fields.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class CategoryFieldsModule extends ConsumerWidget {
  final bool flat;
  final String type; // MediaType wire
  final CategoryDraft category;

  /// Значения меняются через колбек; новый бандл собирает родитель.
  final void Function(CategoryDraft next)? onCategoryChange;

  /// True — редактирование существующей записи (tv-show сезоны read-only).
  final bool isEditing;

  const CategoryFieldsModule({
    super.key,
    this.flat = false,
    required this.type,
    required this.category,
    required this.onCategoryChange,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final on = onCategoryChange;

    return ModuleCard(
      flat: flat,
      title: t.tr('createModal.modules.category'),
      count: null,
      icon: const Icon(LucideIcons.clapperboard, size: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type == 'game')
            GameFormFields(
              platform: category.platform,
              hoursPlayed: category.hoursPlayed,
              onPlatformChange: (v) =>
                  on?.call(category.copyWith(platform: v)),
              onHoursPlayedChange: (v) =>
                  on?.call(category.copyWith(hoursPlayed: v)),
            )
          else if (type == 'book')
            BookFormFields(
              author: category.author,
              totalPages: category.totalPages,
              format: category.bookFormat,
              totalChapters: category.totalChapters,
              totalVolumes: category.bookTotalVolumes,
              onAuthorChange: (v) => on?.call(category.copyWith(author: v)),
              onTotalPagesChange: (v) =>
                  on?.call(category.copyWith(totalPages: v)),
              onFormatChange: (v) =>
                  on?.call(category.copyWith(bookFormat: v)),
              onTotalChaptersChange: (v) =>
                  on?.call(category.copyWith(totalChapters: v)),
              onTotalVolumesChange: (v) =>
                  on?.call(category.copyWith(bookTotalVolumes: v)),
            )
          else if (type == 'manga')
            MangaFormFields(
              author: category.author,
              totalChapters: category.totalChapters,
              currentVolume: category.currentVolume,
              totalVolumes: category.totalPages,
              onAuthorChange: (v) => on?.call(category.copyWith(author: v)),
              onTotalChaptersChange: (v) =>
                  on?.call(category.copyWith(totalChapters: v)),
              onCurrentVolumeChange: (v) =>
                  on?.call(category.copyWith(currentVolume: v)),
              onTotalVolumesChange: (v) =>
                  on?.call(category.copyWith(totalPages: v)),
            )
          else if (type == 'movie')
            MovieFormFields(
              durationMinutes: category.durationMinutes,
              studio: category.studio,
              isAnime: category.isAnime,
              onDurationMinutesChange: (v) =>
                  on?.call(category.copyWith(durationMinutes: v)),
              onStudioChange: (v) => on?.call(category.copyWith(studio: v)),
              onIsAnimeChange: (v) => on?.call(category.copyWith(isAnime: v)),
            )
          else if (type == 'tvshow' && isEditing)
            _TvShowEditingFields(category: category, onCategoryChange: on)
          else
            TvShowFormFields(
              studio: category.studio,
              network: category.network,
              isAnime: category.isAnime,
              seasons: category.seasons,
              onStudioChange: (v) => on?.call(category.copyWith(studio: v)),
              onNetworkChange: (v) => on?.call(category.copyWith(network: v)),
              onIsAnimeChange: (v) => on?.call(category.copyWith(isAnime: v)),
              onSeasonsChange: (v) =>
                  on?.call(category.copyWith(seasons: v)),
            ),
        ],
      ),
    );
  }
}

/// Ветка «редактирование существующего сериала»: студия/сеть редактируемы,
/// сезоны — read-only список (контракт обновления не пишет сезоны).
class _TvShowEditingFields extends ConsumerWidget {
  final CategoryDraft category;
  final void Function(CategoryDraft next)? onCategoryChange;

  const _TvShowEditingFields({
    required this.category,
    required this.onCategoryChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final on = onCategoryChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.studio'),
                child: CreateTextField(
                  value: category.studio,
                  hint: t.tr('createModal.placeholders.studio'),
                  onChange: (v) => on?.call(category.copyWith(studio: v)),
                ),
              ),
            ),
            const SizedBox(width: 12), // gap-3
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.network'),
                child: CreateTextField(
                  value: category.network,
                  hint: t.tr('createModal.placeholders.network'),
                  onChange: (v) => on?.call(category.copyWith(network: v)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Чекбокс «Это аниме?» (text-muted, accent-accent).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => on?.call(category.copyWith(isAnime: !category.isAnime)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: category.isAnime,
                  onChanged: (v) =>
                      on?.call(category.copyWith(isAnime: v ?? false)),
                  activeColor: th.accent,
                ),
              ),
              const SizedBox(width: 8), // gap-2
              Text(
                t.tr('createModal.fields.isAnime'),
                style: TextStyle(fontSize: 14, color: th.textMuted),
              ),
            ],
          ),
        ),
        if (category.seasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12), // p-3
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12), // rounded-xl
              border: Border.all(
                  color: Colors.white.withAlpha(26)), // border-white/10
              color: th.bgSurface.withAlpha(128), // bg-field/50
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.tr('navigation.seasons'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: th.textPrimary,
                  ),
                ),
                const SizedBox(height: 8), // space-y-2
                for (final season in category.seasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            season.title.isEmpty
                                ? '${t.tr('createModal.fields.season')} ${season.seasonNumber}'
                                : '${t.tr('createModal.fields.season')} ${season.seasonNumber} — ${season.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFCBD5E1), // text-slate-300
                            ),
                          ),
                        ),
                        const SizedBox(width: 12), // gap-3
                        Text(
                          '${t.tr('createModal.fields.episodes')}: ${season.totalEpisodes}',
                          style: TextStyle(
                            fontSize: 12, // text-xs
                            color: th.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  t.tr('createModal.seasonsReadonly'),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: th.textMuted.withAlpha(178), // text-muted/70
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
