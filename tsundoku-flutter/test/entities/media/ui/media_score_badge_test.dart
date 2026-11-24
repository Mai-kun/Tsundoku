import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/entities/media/ui/media_score_badge.dart';

/// Widget-тесты `MediaScoreBadge.svelte`: скрытие при null/<=0, Intl-формат
/// числа (ru), Tooltip с сырым score.
void main() {
  Future<void> pump(WidgetTester tester, double? score) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Center(child: MediaScoreBadge(score: score)),
      ),
    ));
    await tester.pump();
  }

  testWidgets('score null → не рендерится', (tester) async {
    await pump(tester, null);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('score 0 → не рендерится (guard score > 0)', (tester) async {
    await pump(tester, 0);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('score 8 → Intl-формат ru без дробной части («8»)',
      (tester) async {
    await pump(tester, 8);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('score 8.5 → Intl-формат ru с запятой («8,5»)', (tester) async {
    await pump(tester, 8.5);
    expect(find.text('8,5'), findsOneWidget);
  });

  testWidgets('Tooltip на MediaScoreBadge отключён (нет hint при наведении)',
      (tester) async {
    await pump(tester, 8);
    expect(find.byType(Tooltip), findsNothing);
  });
}
