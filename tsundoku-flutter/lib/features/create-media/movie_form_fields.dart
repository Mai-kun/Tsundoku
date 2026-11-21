/// Порт `mediatracker-ui/src/features/create-media/MovieFormFields.svelte`.
///
/// Поля категории movie: длительность (мин), студия, чекбокс «Это аниме?».
/// ⬆️ Вытащен из Фазы 5 (зависимость CategoryFieldsModule, Фаза 4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';

class MovieFormFields extends ConsumerWidget {
  final String durationMinutes;
  final String studio;
  final bool isAnime;
  final ValueChanged<String>? onDurationMinutesChange;
  final ValueChanged<String>? onStudioChange;
  final ValueChanged<bool>? onIsAnimeChange;

  const MovieFormFields({
    super.key,
    required this.durationMinutes,
    required this.studio,
    required this.isAnime,
    required this.onDurationMinutesChange,
    required this.onStudioChange,
    required this.onIsAnimeChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.durationMinutes'),
                child: CreateTextField(
                  value: durationMinutes,
                  number: true,
                  onChange: (v) => onDurationMinutesChange?.call(v),
                ),
              ),
            ),
            const SizedBox(width: 16), // gap-4
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.studio'),
                child: CreateTextField(
                  value: studio,
                  hint: t.tr('createModal.placeholders.studio'),
                  onChange: (v) => onStudioChange?.call(v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Чекбокс «Это аниме?» (accent-accent, text-muted text-sm).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onIsAnimeChange?.call(!isAnime),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16, // h-4 w-4
                height: 16,
                child: Checkbox(
                  value: isAnime,
                  onChanged: (v) => onIsAnimeChange?.call(v ?? false),
                  activeColor: th.accent, // accent-accent
                ),
              ),
              const SizedBox(width: 8), // gap-2
              Text(
                t.tr('createModal.fields.isAnime'),
                style: TextStyle(
                  fontSize: 14, // text-sm
                  color: th.textMuted, // text-muted
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
