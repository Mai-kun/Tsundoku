import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/smooth_scroll_controller.dart';

void main() {
  testWidgets(
      'SmoothScrollController interpolates mouse wheel deltas across frames',
      (tester) async {
    final controller = SmoothScrollController();
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

    // После 1 кадра (7 мс ~ 144 Гц) позиция должна сдвинуться частично, а не
    // прыгнуть на все 120 px за один кадр.
    await tester.pump(const Duration(milliseconds: 7));
    expect(controller.offset, greaterThan(0.0));
    expect(controller.offset, lessThan(120.0));

    final afterOneFrame = controller.offset;

    // За несколько кадров позиция приближается к целевой и достигает 120.0.
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(afterOneFrame));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120.0, 0.01));
  });

  testWidgets('SmoothScrollController accumulates rapid wheel events and clamps',
      (tester) async {
    final controller = SmoothScrollController();
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

    // maxScrollExtent = 10 * 50 - 200 = 300.
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
  });

  testWidgets('SmoothScrollController cancels wheel glide cleanly on jumpTo',
      (tester) async {
    final controller = SmoothScrollController();
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

    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(0.0));

    controller.jumpTo(10.0);
    await tester.pumpAndSettle();
    expect(controller.offset, 10.0);
  });

  testWidgets('SmoothScrollScope attaches SmoothScrollController on desktop',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: SmoothScrollScope(
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

    await tester.pump(const Duration(milliseconds: 7));
    expect(scrollable.position.pixels, greaterThan(0.0));
    expect(scrollable.position.pixels, lessThan(120.0));

    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(120.0, 0.01));
  });
}
