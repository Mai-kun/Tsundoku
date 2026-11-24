import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';

void main() {
  testWidgets('TsundokuTextField: renders with default 36px height and fontSize 13', (tester) async {
    final controller = TextEditingController(text: 'Initial');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TsundokuTextField(
            controller: controller,
            placeholder: 'Search here...',
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    final sizedBoxFinder = find.byType(SizedBox).first;
    final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
    expect(sizedBox.height, 36.0);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.style?.fontSize, 13);
    expect(textField.decoration?.contentPadding, const EdgeInsets.symmetric(horizontal: 12, vertical: 8));

    // Test text editing
    await tester.enterText(find.byType(TextField), 'Updated text');
    expect(controller.text, 'Updated text');
  });

  testWidgets('TsundokuTextField: multiline removes fixed height constraint', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: TsundokuTextField(
            multiline: true,
            placeholder: 'Notes...',
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.minLines, 3);
    expect(textField.maxLines, null);
  });

  testWidgets('TsundokuTextField: prefixIcon and suffix render properly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TsundokuTextField(
          prefixIcon: Icon(Icons.search, key: Key('prefix-search')),
          suffix: Icon(Icons.clear, key: Key('suffix-clear')),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prefix-search')), findsOneWidget);
    expect(find.byKey(const Key('suffix-clear')), findsOneWidget);
  });
}
