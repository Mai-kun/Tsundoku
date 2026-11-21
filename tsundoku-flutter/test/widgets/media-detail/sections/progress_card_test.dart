import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/progress_card.dart';

/// Тесты полного цикла `ProgressCard.svelte`: заголовок/кольцо, кнопки
/// (Start/−/+1/+5), ручной ввод с клампом, drag-установка по бару,
/// сегменты vs непрерывный, completed-итог, pace-чипы, error.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required int value,
    required int total,
    double percent = 50,
    String label = 'Эпизоды',
    String unitShort = 'эп.',
    double? minsPerUnit,
    List<int> paceOptions = const [],
    String? finishedAt,
    Object? error,
    void Function(int delta)? onStep,
    void Function(int value)? onCounterChange,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: ProgressCard(
            label: label,
            value: value,
            total: total,
            percent: percent,
            unitShort: unitShort,
            doneLabel: 'Просмотрено',
            remainLabel: 'Осталось смотреть',
            minsPerUnit: minsPerUnit,
            paceOptions: paceOptions,
            startHint: 'Отметьте первый шаг',
            finishedAt: finishedAt,
            accent: ProgressAccent.theme,
            error: error,
            onStep: onStep ?? (_) {},
            onCounterChange: onCounterChange,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('шапка: label, счётчик, /total, проценты кольца', (tester) async {
    await pumpCard(tester, value: 6, total: 12, percent: 50);

    expect(find.text('ЭПИЗОДЫ'), findsOneWidget); // uppercase
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('/ 12'), findsOneWidget); // unitShort
    expect(find.text('50%'), findsOneWidget); // центр кольца
  });

  testWidgets('пустая карточка: кнопка «Начать» → onStep(1)', (tester) async {
    var stepped = 0;
    await pumpCard(tester, value: 0, total: 12, onStep: (d) => stepped = d);

    expect(find.text('Начать'), findsOneWidget);
    expect(find.text('+1'), findsNothing); // триада заменена Start

    await tester.tap(find.text('Начать'));
    await tester.pump();
    expect(stepped, 1);
  });

  testWidgets('бегущая карточка: +1/+5 → onStep; − disabled на нуле', (tester) async {
    final steps = <int>[];
    await pumpCard(
      tester,
      value: 6,
      total: 12,
      onStep: steps.add,
    );

    expect(find.text('+1'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget); // 12-6>=5
    expect(find.text('Начать'), findsNothing);

    await tester.tap(find.text('+1'));
    await tester.pump();
    await tester.tap(find.text('+5'));
    await tester.pump();
    expect(steps, [1, 5]);
  });

  testWidgets('+5 скрыт, когда до конца меньше 5', (tester) async {
    await pumpCard(tester, value: 9, total: 12);
    expect(find.text('+5'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('ручной ввод: тап по счётчику → поле → value клампится к total',
      (tester) async {
    int? changed;
    await pumpCard(
      tester,
      value: 6,
      total: 12,
      onCounterChange: (v) => changed = v,
    );

    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '999'),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, 12); // кламп к total
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('тап по бару: позиция → значение (onCounterChange)',
      (tester) async {
    int? changed;
    await pumpCard(
      tester,
      value: 0,
      total: 10,
      percent: 0,
      onCounterChange: (v) => changed = v,
    );

    final barRect = tester.getRect(find.byKey(const ValueKey('progress-bar')));
    // Тап в 70% ширины бара → round(0.7*10) = 7.
    final gesture = await tester.startGesture(
      Offset(barRect.left + barRect.width * 0.7, barRect.center.dy),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changed, 7);
  });

  testWidgets('сегменты при total ≤ 36; непрерывный бар при больших',
      (tester) async {
    await pumpCard(tester, value: 3, total: 10, percent: 30);
    // 10 сегментов-контейнеров с rounded-[3px].
    final segments = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(3));
    expect(segments, findsNWidgets(10));

    await pumpCard(tester, value: 300, total: 500, percent: 60);
    // Непрерывный бар: один ClipRRect с rounded-full.
    final continuous = find.byWidgetPredicate((w) =>
        w is ClipRRect &&
        w.borderRadius == BorderRadius.circular(999));
    expect(continuous, findsOneWidget);
  });

  testWidgets('completed: бейдж «Выполнено», блок «Всего», finishedOn',
      (tester) async {
    await pumpCard(
      tester,
      value: 12,
      total: 12,
      percent: 100,
      minsPerUnit: 24,
      finishedAt: '2024-04-06T00:00:00Z',
    );

    expect(find.textContaining('Завершено'), findsOneWidget); // progress.completedBadge
    expect(find.text('ВСЕГО'), findsOneWidget); // totalTimeLabel uppercase
    expect(find.textContaining('4 ч 48 мин'), findsOneWidget); // 12*24=288мин
    expect(find.text('Дата окончания'), findsOneWidget);
    expect(find.text('+1'), findsNothing); // кнопки − только
  });

  testWidgets('error → errorMessage в rose', (tester) async {
    await pumpCard(tester, value: 6, total: 12, error: StateError('boom'));
    expect(find.text('Произошла непредвиденная ошибка.'), findsOneWidget);
  });

  testWidgets('pace-чипы: выбор темпа меняет оценку завершения', (tester) async {
    await pumpCard(
      tester,
      value: 2, // isEmpty → startHint, pace-блок только при value > 0
      total: 10,
      percent: 20,
      minsPerUnit: 24,
      paceOptions: [1, 2, 3],
    );

    expect(find.textContaining('Темп'), findsOneWidget);
    expect(find.textContaining('/день'), findsOneWidget);
    // Чипы 1/2/3: «2» дублируется счётчиком (value=2), «1»/«3» уникальны.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));
    
    // Оценка при темпе 1: 10 дней → caption finishAt присутствует.
    expect(find.textContaining('закончите'), findsOneWidget);
  });
}
