import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_scroll.dart';

void main() {
  test('createTsundokuScrollController uses unified motion and scale config',
      () {
    expect(kTsundokuWheelScale, 1.00);
    expect(
      kTsundokuWheelMotion,
      const WheelMotion.curve(
        duration: Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      ),
    );

    final controller = createTsundokuScrollController(
      initialScrollOffset: 24.0,
      keepScrollOffset: false,
      debugLabel: 'test-scroll',
    );
    addTearDown(controller.dispose);

    expect(controller, isA<SmoothScrollController>());
    expect(controller.initialScrollOffset, 24.0);
    expect(controller.keepScrollOffset, isFalse);
    expect(controller.debugLabel, 'test-scroll');
    expect(
      controller.motion,
      const WheelMotion.curve(
        duration: Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      ),
    );
  });

  testWidgets(
      'createTsundokuScrollController smoothly scrolls ListView on PointerScrollEvent',
      (tester) async {
    final controller = createTsundokuScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 40,
          itemExtent: 50,
          itemBuilder: (_, index) => SizedBox(
            height: 50,
            child: Text('Item $index'),
          ),
        ),
      ),
    );

    expect(controller.offset, 0.0);

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));

    // Начальный тик тикера (dt = 0) не прыгает сразу на 120 px.
    await tester.pump();
    expect(controller.offset, 0.0);

    // Через 16 мс (~1 кадр 60 Гц) позиция сдвигается плавно, без мгновенного прыжка на 120 px.
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(0.0));
    expect(controller.offset, lessThan(120.0));

    final afterOneFrame = controller.offset;
    await tester.pump(const Duration(milliseconds: 32));
    expect(controller.offset, greaterThan(afterOneFrame));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120.0, 0.01));
  });

  testWidgets(
      'createTsundokuScrollController accumulates rapid wheel events and cancels on jumpTo',
      (tester) async {
    final controller = createTsundokuScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 200,
            child: ListView.builder(
              controller: controller,
              itemCount: 10,
              itemExtent: 50,
              itemBuilder: (_, index) => SizedBox(
                height: 50,
                child: Text('Item $index'),
              ),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 500)));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(300.0, 0.01));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -150)));
    await tester.pump(const Duration(milliseconds: 16));
    controller.jumpTo(10.0);
    await tester.pumpAndSettle();
    expect(controller.offset, 10.0);
  });

  testWidgets(
      'TsundokuSmoothScrollView attaches SmoothScrollController and interpolates wheel scroll',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: TsundokuSmoothScrollView(
            child: Column(
              children: [
                for (int i = 0; i < 30; i++)
                  SizedBox(height: 50, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.widget.controller, isA<SmoothScrollController>());

    final center = tester.getCenter(find.byType(SingleChildScrollView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));

    await tester.pump();
    expect(scrollable.position.pixels, 0.0);

    await tester.pump(const Duration(milliseconds: 16));
    expect(scrollable.position.pixels, greaterThan(0.0));
    expect(scrollable.position.pixels, lessThan(120.0));

    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(120.0, 0.01));
  });

  testWidgets(
      'TsundokuSmoothScrollScope provides SmoothScrollController via PrimaryScrollController on desktop',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: TsundokuSmoothScrollScope(
          child: ListView.builder(
            itemCount: 40,
            itemExtent: 50,
            itemBuilder: (_, index) => SizedBox(
              height: 50,
              child: Text('Row $index'),
            ),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.widget.controller, isA<SmoothScrollController>());

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));

    await tester.pump();
    expect(scrollable.position.pixels, 0.0);

    await tester.pump(const Duration(milliseconds: 16));
    expect(scrollable.position.pixels, greaterThan(0.0));
    expect(scrollable.position.pixels, lessThan(120.0));

    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(120.0, 0.01));
  });
}
