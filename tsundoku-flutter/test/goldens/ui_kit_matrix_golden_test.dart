// golden_matrix принимает legacy ThemeData из package:flutter/material.dart,
// а appBuilder рендерит приложение через material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy_material;
import 'package:golden_matrix/golden_matrix.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/ui/badge.dart';
import 'package:tsundoku_flutter/shared/ui/button.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';
import 'package:tsundoku_flutter/shared/ui/segmented_control.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';

void main() {
  const desktop = MatrixDevice(
    name: 'desktop',
    logicalSize: Size(1040, 680),
    pixelRatio: 1.0,
  );

  final obsidianTheme = MatrixTheme.custom(
    'obsidian',
    legacy_material.ThemeData.dark(),
    data: TsundokuTheme.obsidian,
  );

  screenMatrixGolden(
    'ui_kit_matrix',
    states: <MatrixScenario>[
      MatrixScenario(
        'default_states',
        builder: () => const _UiKitShowcase(disabledMode: false),
      ),
      MatrixScenario(
        'disabled_and_loading',
        builder: () => const _UiKitShowcase(disabledMode: true),
      ),
    ],
    axes: MatrixAxes(
      themes: <MatrixTheme>[obsidianTheme],
      locales: const <Locale>[Locale('ru')],
      textScales: const <double>[1.0, 1.15],
      devices: const <MatrixDevice>[desktop],
    ),
    fileNameBuilder: (c) {
      final scaleLabel = c.textScale.toString().replaceAll('.', '_');
      return 'goldens/ui_kit_matrix_${c.scenario.slug}_${c.theme.slug}_x$scaleLabel.png';
    },
    captureAfter: const Duration(milliseconds: 200),
    printSummary: false,
    appBuilder: (combination) {
      final tokens = combination.theme.data as TsundokuTheme;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTsundokuTheme(tokens: tokens),
        locale: combination.locale,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(combination.textScale),
            ),
            child: Scaffold(
              backgroundColor: tokens.bgCanvas,
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: combination.scenario.builder(),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _UiKitShowcase extends StatelessWidget {
  final bool disabledMode;

  const _UiKitShowcase({required this.disabledMode});

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: th.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: th.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 20, color: th.accentSoft),
              const SizedBox(width: 8),
              Text(
                disabledMode
                    ? 'Tsundoku UI Kit — Disabled & Loading'
                    : 'Tsundoku UI Kit — Interactive States (Inter + Lucide)',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: th.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1. TsundokuButton
          _SectionLabel('TsundokuButton'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TsundokuButton(
                variant: ButtonVariant.primary,
                size: ButtonSize.md,
                disabled: disabledMode,
                loading: disabledMode,
                onPressed: () {},
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus, size: 15),
                    SizedBox(width: 6),
                    Text('Добавить тайтл'),
                  ],
                ),
              ),
              TsundokuButton(
                variant: ButtonVariant.secondary,
                size: ButtonSize.md,
                disabled: disabledMode,
                onPressed: () {},
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.slidersHorizontal, size: 15),
                    SizedBox(width: 6),
                    Text('Фильтры'),
                  ],
                ),
              ),
              TsundokuButton(
                variant: ButtonVariant.ghost,
                size: ButtonSize.sm,
                disabled: disabledMode,
                onPressed: () {},
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCw, size: 14),
                    SizedBox(width: 6),
                    Text('Обновить'),
                  ],
                ),
              ),
              TsundokuButton(
                variant: ButtonVariant.danger,
                size: ButtonSize.md,
                disabled: disabledMode,
                holdProgress: disabledMode ? 0.55 : null,
                onPressed: () {},
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.trash2, size: 15),
                    SizedBox(width: 6),
                    Text('Удалить'),
                  ],
                ),
              ),
              TsundokuButton(
                variant: ButtonVariant.secondary,
                size: ButtonSize.icon,
                iconOnly: true,
                disabled: disabledMode,
                onPressed: () {},
                child: const Icon(LucideIcons.settings, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2. TsundokuTextField
          _SectionLabel('TsundokuTextField'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TsundokuTextField(
                  enabled: !disabledMode,
                  placeholder: 'Поиск аниме, книг, игр...',
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 15,
                    color: th.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TsundokuTextField(
                  enabled: !disabledMode,
                  initialValue: 'Провожающая в последний путь Фрирен',
                  prefixIcon: Icon(
                    LucideIcons.tv,
                    size: 15,
                    color: th.accentSoft,
                  ),
                  suffix: Icon(
                    LucideIcons.check,
                    size: 15,
                    color: TsundokuPalette.successLine,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: TsundokuTextField(
                  enabled: !disabledMode,
                  initialValue: 'token-value',
                  obscureText: true,
                  prefixIcon: Icon(
                    LucideIcons.keyRound,
                    size: 15,
                    color: th.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 3. TsundokuSegmentedControl & TsundokuSelect
          _SectionLabel('TsundokuSegmentedControl & TsundokuSelect'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TsundokuSegmentedControl<String>(
                value: disabledMode ? 'calendar' : 'grid',
                options: const <SegmentedOption<String>>[
                  SegmentedOption(
                    value: 'grid',
                    label: 'Сетка',
                    icon: LucideIcons.layoutGrid,
                  ),
                  SegmentedOption(
                    value: 'list',
                    label: 'Список',
                    icon: LucideIcons.list,
                  ),
                  SegmentedOption(
                    value: 'calendar',
                    label: 'Календарь',
                    icon: LucideIcons.calendar,
                  ),
                ],
                onChanged: (_) {},
              ),
              TsundokuSelect<String>(
                id: 'matrix-status-select',
                width: 210,
                height: 36,
                disabled: disabledMode,
                value: disabledMode ? 'dropped' : 'watching',
                options: const <PopoverOption<String>>[
                  PopoverOption(value: 'planned', label: 'В планах'),
                  PopoverOption(value: 'watching', label: 'Смотрю сейчас'),
                  PopoverOption(value: 'completed', label: 'Завершено'),
                  PopoverOption(value: 'dropped', label: 'Брошено'),
                ],
                onChange: (_) {},
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4. TsundokuBadge
          _SectionLabel('TsundokuBadge'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const TsundokuBadge(
                tone: BadgeTone.neutral,
                size: BadgeSize.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.clock, size: 12),
                    SizedBox(width: 4),
                    Text('В планах'),
                  ],
                ),
              ),
              const TsundokuBadge(
                tone: BadgeTone.accent,
                size: BadgeSize.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.star, size: 12),
                    SizedBox(width: 4),
                    Text('Шедевр 10/10'),
                  ],
                ),
              ),
              const TsundokuBadge(
                tone: BadgeTone.info,
                size: BadgeSize.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.radio, size: 12),
                    SizedBox(width: 4),
                    Text('Онгоинг'),
                  ],
                ),
              ),
              const TsundokuBadge(
                tone: BadgeTone.success,
                size: BadgeSize.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.circleCheck, size: 12),
                    SizedBox(width: 4),
                    Text('Завершено'),
                  ],
                ),
              ),
              const TsundokuBadge(
                tone: BadgeTone.warning,
                size: BadgeSize.xs,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.pause, size: 10),
                    SizedBox(width: 3),
                    Text('Пауза'),
                  ],
                ),
              ),
              const TsundokuBadge(
                tone: BadgeTone.danger,
                size: BadgeSize.xs,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.circleX, size: 10),
                    SizedBox(width: 3),
                    Text('Брошено'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: th.textMuted,
      ),
    );
  }
}
