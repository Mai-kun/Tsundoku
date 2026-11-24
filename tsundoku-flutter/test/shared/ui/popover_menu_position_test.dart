import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';

void main() {
  testWidgets('TsundokuPopoverMenu positions adjacent to trigger, strictly not at (0, 0)', (tester) async {
    const triggerOffset = Offset(200, 300);
    const triggerSize = Size(100, 40);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: triggerOffset.dx,
              top: triggerOffset.dy,
              width: triggerSize.width,
              height: triggerSize.height,
              child: TsundokuPopoverMenu<String>(
                id: 'test-popover',
                placement: PopoverPlacement.bottomStart,
                options: const [
                  PopoverOption(value: 'opt1', label: 'Option 1'),
                  PopoverOption(value: 'opt2', label: 'Option 2'),
                ],
                selected: 'opt1',
                onSelect: (_) {},
                label: 'Test Menu',
                trigger: (context, ctx) => Container(
                  key: const Key('trigger-box'),
                  color: Colors.blue,
                  child: const Text('Open'),
                ),
              ),
            ),
          ],
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Verify trigger is rendered at the expected position
    final triggerRenderBox = tester.renderObject(find.byKey(const Key('trigger-box'))) as RenderBox;
    final triggerGlobalPos = triggerRenderBox.localToGlobal(Offset.zero);
    expect(triggerGlobalPos.dx, triggerOffset.dx);
    expect(triggerGlobalPos.dy, triggerOffset.dy);

    // Tap trigger to open popover
    await tester.tap(find.byKey(const Key('trigger-box')));
    await tester.pumpAndSettle();

    // Verify popover options are visible
    final opt1Finder = find.text('Option 1');
    expect(opt1Finder, findsOneWidget);

    // Verify position of Option 1 in global coordinates
    final opt1RenderBox = tester.renderObject(opt1Finder) as RenderBox;
    final opt1GlobalPos = opt1RenderBox.localToGlobal(Offset.zero);

    // Option 1 must NOT be at (0, 0)
    expect(opt1GlobalPos.dx, isNot(closeTo(0, 10)));
    expect(opt1GlobalPos.dy, isNot(closeTo(0, 10)));

    // Popover placement is bottom-start, so it should be near triggerOffset.dx and below triggerOffset.dy + 40
    expect(opt1GlobalPos.dx, greaterThanOrEqualTo(triggerOffset.dx - 10));
    expect(opt1GlobalPos.dy, greaterThan(triggerOffset.dy + triggerSize.height));

    // Verify font size is 14px (text-sm)
    final textWidget = tester.widget<Text>(opt1Finder);
    expect(textWidget.style?.fontSize, 14);
  });

  testWidgets('PopoverPlacement.bottomEnd aligns menu right edge with trigger right edge',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const triggerOffset = Offset(720, 96);
    const triggerSize = Size(40, 40);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: triggerOffset.dx,
              top: triggerOffset.dy,
              width: triggerSize.width,
              height: triggerSize.height,
              child: TsundokuPopoverMenu<String>(
                id: 'bottom-end-popover',
                placement: PopoverPlacement.bottomEnd,
                options: const [
                  PopoverOption(value: 'updated', label: 'По дате обновления'),
                  PopoverOption(value: 'created', label: 'По дате добавления'),
                ],
                selected: 'updated',
                onSelect: (_) {},
                label: 'Sort',
                trigger: (context, ctx) => Container(
                  key: const Key('trigger-end'),
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('trigger-end')));
    await tester.pumpAndSettle();

    final menuMaterial = find.descendant(
      of: find.byType(CustomSingleChildLayout),
      matching: find.byType(Material),
    ).first;
    final menuRect = tester.getRect(menuMaterial);
    final triggerRight = triggerOffset.dx + triggerSize.width;
    expect(menuRect.right, closeTo(triggerRight, 0.5));
    expect(menuRect.left, lessThan(triggerOffset.dx));
    expect(menuRect.right, lessThanOrEqualTo(800 - 8));
  });
}
