import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/entities/media/ui/placeholder404.dart';

/// Widget-тесты `Placeholder404.svelte`: label пробрасывается в
/// MediaCoverPlaceholder, undefined → дефолт activity.coverMissing.
void main() {
  Future<void> pump(WidgetTester tester, {String? label}) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 150,
            child: Placeholder404(label: label),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('без label → дефолтный activity.coverMissing (ru)',
      (tester) async {
    await pump(tester);
    expect(find.text('Обложка не найдена'), findsOneWidget);
  });

  testWidgets('кастомный label пробрасывается в плейсхолдер', (tester) async {
    await pump(tester, label: 'Превью недоступно');
    expect(find.text('Превью недоступно'), findsOneWidget);
    expect(find.text('Обложка не найдена'), findsNothing);
  });
}
