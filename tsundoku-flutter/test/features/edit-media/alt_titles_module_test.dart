import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/alt_titles_module.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  Future<void> pumpModule(
    WidgetTester tester,
    List<String> titles,
    ValueChanged<List<String>> onChange,
  ) async {
    var current = titles;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 500,
            child: StatefulBuilder(builder: (context, setOuter) {
              return AltTitlesModule(
                altTitles: current,
                onChange: (next) {
                  current = next;
                  onChange(next);
                  setOuter(() {});
                },
              );
            }),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('пустой список: empty-строка, ввод сплитом «/» и «,»',
      (tester) async {
    List<List<String>>? commits;
    await pumpModule(tester, const [], (next) {
      commits ??= [];
      commits!.add(next);
    });
    expect(find.text('ПОКА НЕТ АЛЬТЕРНАТИВНЫХ НАЗВАНИЙ'), findsNothing); // uppercase — это лейбл
    expect(find.text('Пока нет альтернативных названий'), findsOneWidget);
    expect(find.byType(ModuleCard), findsOneWidget);
    expect(find.byIcon(LucideIcons.tag), findsOneWidget);

    // Ввод с разделителями → два элемента.
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Frieren / Sousou no Frieren, 葬送のフリーレン');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits!.last, hasLength(3));
    expect(commits!.last[0], 'Frieren');
    expect(commits!.last[1], 'Sousou no Frieren');
    expect(commits!.last[2], '葬送のフリーレン');
  });

  testWidgets('кнопка добавления добавляет список; дубликат — no-op',
      (tester) async {
    List<List<String>>? commits;
    await pumpModule(tester, const ['Frieren'], (next) {
      commits ??= [];
      commits!.add(next);
    });
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Frieren,葬送のフリーレン');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    expect(commits!.last, hasLength(2)); // Frieren отфильтрован
    expect(commits!.last[1], '葬送のフリーレン');
  });

  testWidgets('строки: pencil → редактирование → commit', (tester) async {
    List<List<String>>? commits;
    await pumpModule(tester, const ['Frieren', 'Old title'], (next) {
      commits ??= [];
      commits!.add(next);
    });
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Old title'), findsOneWidget);
    // Редактирование второй строки.
    await tester.tap(find.byIcon(LucideIcons.pencil).last);
    await tester.pump(const Duration(milliseconds: 50));
    // Инпут редактирования — последний TextField (первый — быстрый ввод).
    await tester.enterText(find.byType(TextField).last, 'New title');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits!.last, ['Frieren', 'New title']);
  });

  testWidgets('удаление строки trash2', (tester) async {
    List<List<String>>? commits;
    await pumpModule(tester, const ['A', 'B'], (next) {
      commits ??= [];
      commits!.add(next);
    });
    await tester.tap(find.byIcon(LucideIcons.trash2).first);
    await tester.pump();
    expect(commits!.last, ['B']);
  });
}
