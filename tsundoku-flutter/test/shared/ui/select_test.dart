import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';

/// Widget-тесты `Select.svelte` (обёртка над PopoverMenu).
void main() {
  Future<void> pumpSelect(
    WidgetTester tester, {
    String selected = 'newest',
    bool disabled = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: TsundokuSelect<String>(
            id: 'sort',
            options: const [
              PopoverOption(value: 'newest', label: 'Newest'),
              PopoverOption(value: 'oldest', label: 'Oldest'),
              PopoverOption(value: 'rating', label: 'Rating'),
            ],
            value: selected,
            onChange: (_) {},
            placeholder: 'Sort…',
            disabled: disabled,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('триггер показывает label выбранного', (tester) async {
    await pumpSelect(tester, selected: 'rating');
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('Newest'), findsNothing);
  });

  testWidgets('пустой value → placeholder', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: TsundokuSelect<String>(
            id: 'sort',
            options: const [
              PopoverOption(value: 'newest', label: 'Newest'),
            ],
            value: 'unknown-value',
            onChange: (_) {},
            placeholder: 'Sort…',
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Sort…'), findsOneWidget);
  });
}
