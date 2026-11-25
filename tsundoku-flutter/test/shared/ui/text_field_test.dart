import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/ui/text_field.dart';

void main() {
  testWidgets('TsundokuTextField: renders with default 36px height, collapsed InputDecoration, and 0px inset', (tester) async {
    final controller = TextEditingController(text: 'Initial');

    await tester.pumpWidget(MaterialApp(
      theme: buildTsundokuTheme(),
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

    final fieldRect = tester.getRect(find.byType(TsundokuTextField));
    final containerRect = tester.getRect(find.descendant(
      of: find.byType(TsundokuTextField),
      matching: find.byType(Container),
    ).first);
    expect(fieldRect.height, 36.0);
    expect(containerRect, fieldRect);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.style?.fontSize, 13);
    expect(textField.decoration?.isCollapsed, isTrue);
    expect(textField.decoration?.border, InputBorder.none);
    expect(textField.decoration?.contentPadding, EdgeInsets.zero);
    expect(textField.textAlignVertical, TextAlignVertical.center);

    // Test text editing
    await tester.enterText(find.byType(TextField), 'Updated text');
    expect(controller.text, 'Updated text');
  });

  testWidgets('TsundokuTextField: multiline removes fixed height constraint', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTsundokuTheme(),
      home: const Scaffold(
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
    expect(tester.getRect(find.byType(TsundokuTextField)).height, greaterThan(36.0));
  });

  testWidgets('TsundokuTextField: prefixIcon and suffix render properly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTsundokuTheme(),
      home: const Scaffold(
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

  testWidgets('TsundokuTextField: custom 40px height paints outer Container border with 0px inset and updates on focus',
      (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: Center(
          child: TsundokuTextField(
            height: 40,
            focusNode: focusNode,
            placeholder: 'Search...',
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(TsundokuTextField)).height, 40.0);

    final containerFinder = find.descendant(
      of: find.byType(TsundokuTextField),
      matching: find.byType(Container),
    ).first;
    final idleContainer = tester.widget<Container>(containerFinder);
    final idleDecoration = idleContainer.decoration! as BoxDecoration;
    expect(idleDecoration.color, const Color(0xFF0F1219));
    expect((idleDecoration.border! as Border).top.color, TsundokuTheme.obsidian.borderSubtle);

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    final focusedContainer = tester.widget<Container>(containerFinder);
    final focusedDecoration = focusedContainer.decoration! as BoxDecoration;
    expect((focusedDecoration.border! as Border).top.color, TsundokuTheme.obsidian.accent);
  });
}
