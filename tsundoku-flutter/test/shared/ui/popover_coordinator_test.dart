import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';

void main() {
  testWidgets('PopoverCoordinator: opening one popover automatically closes any open popover', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Text('Outside Area'),
            Row(
              children: [
                TsundokuPopoverMenu<String>(
                  id: 'menu-a',
                  label: 'Menu A',
                  selected: 'a1',
                  onSelect: (_) {},
                  options: const [
                    PopoverOption(value: 'a1', label: 'Option A1'),
                    PopoverOption(value: 'a2', label: 'Option A2'),
                  ],
                  trigger: (ctx, tCtx) => const Text('Trigger A'),
                ),
                const SizedBox(width: 40),
                TsundokuPopoverMenu<String>(
                  id: 'menu-b',
                  label: 'Menu B',
                  selected: 'b1',
                  onSelect: (_) {},
                  options: const [
                    PopoverOption(value: 'b1', label: 'Option B1'),
                    PopoverOption(value: 'b2', label: 'Option B2'),
                  ],
                  trigger: (ctx, tCtx) => const Text('Trigger B'),
                ),
              ],
            ),
          ],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Neither is open initially
    expect(find.text('Option A1'), findsNothing);
    expect(find.text('Option B1'), findsNothing);

    // Tap Trigger A to open Menu A
    await tester.tap(find.text('Trigger A'));
    await tester.pumpAndSettle();

    expect(find.text('Option A1'), findsOneWidget);
    expect(find.text('Option B1'), findsNothing);

    // Tap Trigger B: Menu A must automatically close, and Menu B must open!
    await tester.tap(find.text('Trigger B'));
    await tester.pumpAndSettle();

    expect(find.text('Option A1'), findsNothing, reason: 'Menu A should be closed automatically');
    expect(find.text('Option B1'), findsOneWidget, reason: 'Menu B should now be open');

    // Tap Trigger B again: toggles Menu B closed
    await tester.tap(find.text('Trigger B'));
    await tester.pumpAndSettle();

    expect(find.text('Option B1'), findsNothing, reason: 'Menu B should toggle closed');

    // Open Menu A again and tap outside
    await tester.tap(find.text('Trigger A'));
    await tester.pumpAndSettle();
    expect(find.text('Option A1'), findsOneWidget);

    await tester.tap(find.text('Outside Area'));
    await tester.pumpAndSettle();
    expect(find.text('Option A1'), findsNothing, reason: 'Tapping outside should close Menu A');
  });
}
