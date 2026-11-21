import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_title_block.dart';

/// Widget-тесты `CardTitleBlock.svelte`: clamp-2 заголовок с Tooltip,
/// clamp-1 подзаголовок.
void main() {
  Future<void> pump(WidgetTester tester, String title, String subtitle) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: CardTitleBlock(title: title, subtitle: subtitle),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('рендерит title и subtitle', (tester) async {
    await pump(tester, 'Норагами', 'Adachitoka');
    expect(find.text('Норагами'), findsOneWidget);
    expect(find.text('Adachitoka'), findsOneWidget);
  });

  testWidgets('title: clamp 2 строки; subtitle: clamp 1', (tester) async {
    await pump(tester, 'Длинное название', 'Подзаголовок');
    final title = tester.widget<Text>(find.text('Длинное название'));
    expect(title.maxLines, 2);
    final subtitle = tester.widget<Text>(find.text('Подзаголовок'));
    expect(subtitle.maxLines, 1);
  });

  testWidgets('Tooltip = titleTooltip: короткое название целиком', (tester) async {
    await pump(tester, 'Норагами', 'Adachitoka');
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Норагами');
  });

  testWidgets('Tooltip обрезает название >100 символов (97 + "...")',
      (tester) async {
    final long = 'а' * 120;
    await pump(tester, long, 'x');
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '${'а' * 97}...');
  });
}
