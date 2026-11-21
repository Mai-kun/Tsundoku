/// Порт `mediatracker-ui/src/features/create-media/MangaFormFields.svelte`.
///
/// Поля категории manga: автор, главы, текущий том, тома (totalVolumes —
/// двойная роль общего поля; второй ряд — две грид-пары). ⬆️ Вытащен из
/// Фазы 5 (зависимость CategoryFieldsModule, Фаза 4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';

class MangaFormFields extends ConsumerWidget {
  final String author;
  final String totalChapters;
  final String currentVolume;

  /// Двойная роль total-volume поля; биндингом владеет родитель.
  final String totalVolumes;
  final ValueChanged<String>? onAuthorChange;
  final ValueChanged<String>? onTotalChaptersChange;
  final ValueChanged<String>? onCurrentVolumeChange;
  final ValueChanged<String>? onTotalVolumesChange;

  const MangaFormFields({
    super.key,
    required this.author,
    required this.totalChapters,
    required this.currentVolume,
    required this.totalVolumes,
    required this.onAuthorChange,
    required this.onTotalChaptersChange,
    required this.onCurrentVolumeChange,
    required this.onTotalVolumesChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.author'),
                child: CreateTextField(
                  value: author,
                  hint: t.tr('createModal.placeholders.author'),
                  onChange: (v) => onAuthorChange?.call(v),
                ),
              ),
            ),
            const SizedBox(width: 16), // gap-4
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.totalChapters'),
                child: CreateTextField(
                  value: totalChapters,
                  number: true,
                  onChange: (v) => onTotalChaptersChange?.call(v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16), // межгридовый gap-4
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.currentVolume'),
                child: CreateTextField(
                  value: currentVolume,
                  number: true,
                  onChange: (v) => onCurrentVolumeChange?.call(v),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TsundokuFormField(
                label: t.tr('detail.tabVolumes'),
                child: CreateTextField(
                  value: totalVolumes,
                  number: true,
                  hint: '1',
                  onChange: (v) => onTotalVolumesChange?.call(v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
