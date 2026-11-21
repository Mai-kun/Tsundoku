/// Порт `mediatracker-ui/src/features/create-media/GameFormFields.svelte`.
///
/// Поля категории game: платформа + часы игры. ⬆️ Вытащен из Фазы 5
/// (зависимость CategoryFieldsModule, Фаза 4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';

class GameFormFields extends ConsumerWidget {
  final String platform;
  final String hoursPlayed;
  final ValueChanged<String>? onPlatformChange;
  final ValueChanged<String>? onHoursPlayedChange;

  const GameFormFields({
    super.key,
    required this.platform,
    required this.hoursPlayed,
    required this.onPlatformChange,
    required this.onHoursPlayedChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // grid gap-4 sm:grid-cols-2
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.platform'),
                child: CreateTextField(
                  value: platform,
                  hint: t.tr('createModal.placeholders.platform'),
                  onChange: (v) => onPlatformChange?.call(v),
                ),
              ),
            ),
            const SizedBox(width: 16), // gap-4
            Expanded(
              child: TsundokuFormField(
                label: t.tr('createModal.fields.hoursPlayed'),
                child: CreateTextField(
                  value: hoursPlayed,
                  number: true,
                  onChange: (v) => onHoursPlayedChange?.call(v),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
