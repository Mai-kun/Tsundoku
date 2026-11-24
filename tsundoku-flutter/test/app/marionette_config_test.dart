import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/platform/dev_tools_io.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/button.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';
import 'package:tsundoku_flutter/shared/ui/segmented_control.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';
import 'package:tsundoku_flutter/widgets/media-card/media_card.dart';

void main() {
  testWidgets(
      'buildTsundokuMarionetteConfiguration recognizes all custom interactive widgets',
      (tester) async {
    final MarionetteConfiguration config = buildTsundokuMarionetteConfiguration();
    final MediaItem sampleItem = MediaItem.fromJson(const <String, dynamic>{
      'id': 'm-1',
      'type': 'tvshow',
      'title': 'Frieren: Beyond Journey\'s End',
      'status': 1,
      'createdAt': '2026-01-01T00:00:00Z',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTsundokuTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  TsundokuButton(
                    onPressed: () {},
                    child: const Text('Сохранить'),
                  ),
                  TsundokuSelect<String>(
                    id: 'select-status',
                    value: 'watching',
                    options: const <PopoverOption<String>>[
                      PopoverOption(value: 'watching', label: 'Смотрю'),
                      PopoverOption(value: 'completed', label: 'Завершено'),
                    ],
                    onChange: (_) {},
                  ),
                  TsundokuPopoverMenu<String>(
                    key: const ValueKey('explicit-popover'),
                    id: 'menu-actions',
                    label: 'Действия',
                    selected: 'edit',
                    options: const <PopoverOption<String>>[
                      PopoverOption(value: 'edit', label: 'Изменить'),
                    ],
                    onSelect: (_) {},
                    trigger: (_, _) => const Text('Меню'),
                  ),
                  const TsundokuTextField(
                    initialValue: 'Поиск по библиотеке',
                    placeholder: 'Поиск...',
                  ),
                  TsundokuSegmentedControl<String>(
                    value: 'grid',
                    options: const <SegmentedOption<String>>[
                      SegmentedOption(value: 'grid', label: 'Сетка'),
                      SegmentedOption(value: 'list', label: 'Список'),
                    ],
                    onChanged: (_) {},
                  ),
                  SizedBox(
                    width: 220,
                    height: 360,
                    child: MediaCard(
                      props: MediaCardProps(item: sampleItem),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Element elementOf(Finder finder) => finder.evaluate().single;

    expect(
      config.isElementInteractive(elementOf(find.byType(TsundokuButton))),
      isTrue,
    );
    expect(
      config.isElementInteractive(
          elementOf(find.byType(TsundokuSelect<String>))),
      isTrue,
    );
    expect(
      config.isElementInteractive(
          elementOf(find.byKey(const ValueKey('explicit-popover')))),
      isTrue,
    );
    expect(
      config.isElementInteractive(elementOf(find.byType(TsundokuTextField))),
      isTrue,
    );
    expect(
      config.isElementInteractive(
          elementOf(find.byType(TsundokuSegmentedControl<String>))),
      isTrue,
    );
    expect(
      config.isElementInteractive(elementOf(find.byType(MediaCard))),
      isTrue,
    );

    expect(
      config.extractTextFromWidget(
          elementOf(find.byType(TsundokuSelect<String>))),
      'Смотрю',
    );
    expect(
      config.extractTextFromWidget(
          elementOf(find.byKey(const ValueKey('explicit-popover')))),
      'Действия',
    );
    expect(
      config.extractTextFromWidget(elementOf(find.byType(TsundokuTextField))),
      'Поиск по библиотеке',
    );
    expect(
      config.extractTextFromWidget(elementOf(find.byType(MediaCard))),
      'Frieren: Beyond Journey\'s End',
    );
  });
}
