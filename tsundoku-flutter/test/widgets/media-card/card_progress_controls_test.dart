import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_progress_controls.dart';

/// Widget-тесты `CardProgressControls.svelte`: степпер ±, disabled-ветки,
/// errorMessage под степпером.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String text = '3 / 12',
    void Function(int)? onStep,
    bool decrementDisabled = false,
    bool incrementDisabled = false,
    Object? error,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: 220,
            child: CardProgressControls(
              text: text,
              onStep: onStep ?? (_) {},
              decrementDisabled: decrementDisabled,
              incrementDisabled: incrementDisabled,
              error: error,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('рендерит текст прогресса и две кнопки ±', (tester) async {
    await pump(tester);
    expect(find.text('3 / 12'), findsOneWidget);
    expect(find.byIcon(LucideIcons.minus), findsOneWidget);
    expect(find.byIcon(LucideIcons.plus), findsOneWidget);
  });

  testWidgets('тап по кнопкам вызывает onStep(-1)/(+1)', (tester) async {
    final steps = <int>[];
    await pump(tester, onStep: steps.add);
    await tester.tap(find.byIcon(LucideIcons.minus));
    await tester.tap(find.byIcon(LucideIcons.plus));
    expect(steps, [-1, 1]);
  });

  testWidgets('disabled-кнопки не вызывают onStep', (tester) async {
    final steps = <int>[];
    await pump(tester,
        onStep: steps.add, decrementDisabled: true, incrementDisabled: true);
    await tester.tap(find.byIcon(LucideIcons.minus), warnIfMissed: false);
    await tester.tap(find.byIcon(LucideIcons.plus), warnIfMissed: false);
    expect(steps, isEmpty);
  });

  testWidgets('без ошибки — alert-строки нет', (tester) async {
    await pump(tester);
    expect(find.byType(Text).evaluate().length, 1); // только лейбл прогресса
  });

  testWidgets('ошибка → errorMessage под степпером (errors.unexpected)',
      (tester) async {
    await pump(tester, error: Exception('boom'));
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.length, 2);
    expect(texts[1].data, isNotNull);
    expect(texts[1].data, isNot('3 / 12'));
  });
}
