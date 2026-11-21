import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/progress_stepper.dart';

/// Тесты `ProgressStepper.svelte`: тонкая обёртка над ProgressCard —
/// theme-акцент, без времени, label как unit, startGeneric-подсказка.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpStepper(
    WidgetTester tester, {
    required int value,
    required int? total,
    required double percent,
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
            child: ProgressStepper(
              progress: ProgressInfo(
                current: value,
                total: total,
                editable: true,
                label: 'Главы',
              ),
              value: value,
              percent: percent,
              error: null,
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

  testWidgets('пустой прогресс: Start → onStep(1), подсказка startGeneric',
      (tester) async {
    var stepped = 0;
    await pumpStepper(
      tester,
      value: 0,
      total: null, // total неизвестен (game) → без кольца/бара
      percent: 0,
      onStep: (d) => stepped = d,
    );

    expect(find.text('ГЛАВЫ'), findsOneWidget);
    expect(find.text('Начать'), findsOneWidget);
    expect(find.text('Отметьте первый шаг'), findsOneWidget);

    await tester.tap(find.text('Начать'));
    await tester.pump();
    expect(stepped, 1);
  });

  testWidgets('total известен: кольцо, /total, +1/+5 через onStep',
      (tester) async {
    final steps = <int>[];
    await pumpStepper(
      tester,
      value: 3,
      total: 20,
      percent: 15,
      onStep: steps.add,
    );

    expect(find.text('15%'), findsOneWidget);
    expect(find.textContaining('/ 20'), findsOneWidget);

    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(steps, [1]);
  });

  testWidgets('onCounterChange пробрасывается в ProgressCard (ручной ввод)',
      (tester) async {
    int? changed;
    await pumpStepper(
      tester,
      value: 3,
      total: 20,
      percent: 15,
      onCounterChange: (v) => changed = v,
    );

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changed, 10);
  });

  testWidgets('использует ProgressCard с theme-акцентом и без времени',
      (tester) async {
    await pumpStepper(tester, value: 3, total: 20, percent: 15);

    // minsPerUnit = null → блока времени «Осталось» нет.
    expect(find.textContaining('ОСТАЛОСЬ'), findsNothing);
  });
}
