import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/base_media_module.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';

void main() {
  testWidgets('рендер: тайтл-карточка, лейблы полей, плейсхолдер',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: BaseMediaModule(
                type: MediaType.game,
                title: '',
                score: '',
                status: MediaStatus.planned,
                startedAt: '',
                finishedAt: '',
                onTypeChange: (_) {},
                onTitleChange: (_) {},
                onScoreChange: (_) {},
                onStatusChange: (_) {},
                onStartedAtChange: (_) {},
                onFinishedAtChange: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ModuleCard), findsOneWidget);
    expect(find.byIcon(LucideIcons.layers), findsOneWidget);
    expect(find.text('БАЗОВЫЕ ДАННЫЕ'), findsOneWidget);
    expect(find.text('Тип'), findsOneWidget);
    expect(find.text('Название'), findsOneWidget);
    expect(find.text('Оценка'), findsOneWidget);
    expect(find.text('Статус'), findsOneWidget);
    expect(find.text('Начало'), findsOneWidget);
    expect(find.text('Завершение'), findsOneWidget);
    // Плейсхолдер тайтла (пустое значение).
    expect(find.text('Например, The Witcher 3'), findsOneWidget);
    // Выбранный тип и статус в триггерах селектов.
    expect(find.text('Игра'), findsOneWidget);
    expect(find.text('В планах'), findsOneWidget);
  });

  testWidgets('ввод тайтла отдаёт bindable', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: BaseMediaModule(
                type: MediaType.game,
                title: 'The Witcher 3',
                score: '',
                status: MediaStatus.planned,
                startedAt: '',
                finishedAt: '',
                onTypeChange: (_) {},
                onTitleChange: (_) {},
                onScoreChange: (_) {},
                onStatusChange: (_) {},
                onStartedAtChange: (_) {},
                onFinishedAtChange: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    final titleField = find.widgetWithText(TextField, 'The Witcher 3');
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, 'Witcher 3 GOTY');
    await tester.pump();
  });

  testWidgets('смена типа через селект', (tester) async {
    MediaType? next;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: BaseMediaModule(
                type: MediaType.game,
                title: 'x',
                score: '',
                status: MediaStatus.planned,
                startedAt: '',
                finishedAt: '',
                onTypeChange: (v) => next = v,
                onTitleChange: (_) {},
                onScoreChange: (_) {},
                onStatusChange: (_) {},
                onStartedAtChange: (_) {},
                onFinishedAtChange: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    // Открыть type-селект (триггер с текстом «Игра»).
    await tester.tap(find.text('Игра'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Манга'), findsWidgets); // опция в меню
    await tester.tap(find.text('Манга').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(next, MediaType.manga);
  });

  testWidgets('смена статуса через селект', (tester) async {
    MediaStatus? next;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: BaseMediaModule(
                type: MediaType.game,
                title: 'x',
                score: '',
                status: MediaStatus.planned,
                startedAt: '',
                finishedAt: '',
                onTypeChange: (_) {},
                onTitleChange: (_) {},
                onScoreChange: (_) {},
                onStatusChange: (v) => next = v,
                onStartedAtChange: (_) {},
                onFinishedAtChange: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('В планах'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Брошено').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(next, MediaStatus.dropped);
  });

  testWidgets('ввод оценки и дат отдаёт bindable', (tester) async {
    String? score;
    String? started;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: BaseMediaModule(
                type: MediaType.game,
                title: 'x',
                score: '9',
                status: MediaStatus.planned,
                startedAt: '',
                finishedAt: '',
                onTypeChange: (_) {},
                onTitleChange: (_) {},
                onScoreChange: (v) => score = v,
                onStatusChange: (_) {},
                onStartedAtChange: (v) => started = v,
                onFinishedAtChange: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    // Оценка: число 9 уже в поле.
    final scoreField = find.widgetWithText(TextField, '9');
    expect(scoreField, findsOneWidget);
    await tester.enterText(scoreField, '10');
    await tester.pump();
    expect(score, '10');

    // Текстовых полей ровно 2: название и оценка (даты управляются нативным _DatePickerField).
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    // Даты: открывается DatePickerDialog при тапе по календарю.
    final datePickers = find.byIcon(LucideIcons.calendar);
    expect(datePickers, findsNWidgets(2));
    await tester.tap(datePickers.first);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(started, isNotNull);
  });
}
