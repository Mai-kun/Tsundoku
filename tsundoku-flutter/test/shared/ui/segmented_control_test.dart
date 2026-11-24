import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/segmented_control.dart';

void main() {
  testWidgets('TsundokuSegmentedControl: selects item and stays compact by default', (tester) async {
    String selected = 'opt1';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              return TsundokuSegmentedControl<String>(
                value: selected,
                options: const [
                  SegmentedOption(value: 'opt1', label: 'First'),
                  SegmentedOption(value: 'opt2', label: 'Second'),
                ],
                onChanged: (val) {
                  setState(() => selected = val);
                },
              );
            },
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Verify both items rendered
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    // Verify root Row of segmented control has MainAxisSize.min (expand is false)
    final rootRow = tester.widget<Row>(
      find.descendant(
        of: find.byType(TsundokuSegmentedControl<String>),
        matching: find.byType(Row),
      ).first,
    );
    expect(rootRow.mainAxisSize, MainAxisSize.min);

    // Tap Second
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();

    expect(selected, 'opt2');
  });

  testWidgets('TsundokuSectionHeader: renders uppercase text with 11px and letterSpacing 0.8', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TsundokuSectionHeader('Navigation tools'),
      ),
    ));

    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('NAVIGATION TOOLS'));
    expect(text.style?.fontSize, 11);
    expect(text.style?.letterSpacing, 0.8);
    expect(text.style?.fontWeight, FontWeight.w600);
  });
}
