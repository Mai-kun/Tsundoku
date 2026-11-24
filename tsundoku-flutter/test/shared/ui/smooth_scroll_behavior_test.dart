import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/smooth_scroll_behavior.dart';

Future<void> _sendWheel(
  WidgetTester tester, {
  required Offset position,
  required Offset scrollDelta,
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final TestPointer pointer = TestPointer(1, kind);
  await tester.sendEventToBinding(pointer.hover(position));
  await tester.sendEventToBinding(pointer.scroll(scrollDelta));
}

void main() {
  testWidgets(
      'TsundokuSmoothWheelInterceptor produces smooth intermediate steps on ListView without instant jump',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const TsundokuSmoothScrollBehavior(),
        builder: TsundokuSmoothWheelInterceptor.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              controller: controller,
              itemExtent: 50,
              itemCount: 40,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.offset, 0.0);

    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 240),
    );

    // Первый кадр тикера: позиция НЕ делает мгновенный скачок на 240, а движется плавно.
    await tester.pump();
    final double firstFrameOffset = controller.offset;
    expect(firstFrameOffset, greaterThan(0.0));
    expect(firstFrameOffset, lessThan(240.0));

    await tester.pump(const Duration(milliseconds: 7));
    final double step1 = controller.offset;
    expect(step1, greaterThan(firstFrameOffset));
    expect(step1, lessThan(240.0));

    // Серия 144Hz кадров (~7ms): каждый кадр монотонно приближается к 240.
    final List<double> steps = <double>[step1];
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 7));
      steps.add(controller.offset);
      expect(steps.last, greaterThan(steps[steps.length - 2]));
      expect(steps.last, lessThan(240.0));
    }

    // После достаточного времени скролл сходится точно к целевой позиции 240.0.
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(240.0, 0.5));
  });

  testWidgets(
      'TsundokuSmoothWheelInterceptor smoothly scrolls CustomScrollView and accumulates wheel ticks',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const TsundokuSmoothScrollBehavior(),
        builder: TsundokuSmoothWheelInterceptor.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: CustomScrollView(
              controller: controller,
              slivers: [
                SliverFixedExtentList.builder(
                  itemExtent: 50,
                  itemCount: 40,
                  itemBuilder: (_, i) => Text('Sliver $i'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.offset, 0.0);

    // Два быстрых тика колеса накапливают target = 120 + 120 = 240.
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 120),
    );
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 120),
    );

    await tester.pump();
    expect(controller.offset, greaterThan(0.0));
    expect(controller.offset, lessThan(240.0));

    await tester.pump(const Duration(milliseconds: 7));
    expect(controller.offset, lessThan(240.0));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(240.0, 0.5));
  });

  testWidgets(
      'TsundokuSmoothWheelInterceptor hands off wheel scroll to outer list when inner reaches edge',
      (tester) async {
    final outerController = ScrollController();
    final innerController = ScrollController();
    addTearDown(outerController.dispose);
    addTearDown(innerController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const TsundokuSmoothScrollBehavior(),
        builder: TsundokuSmoothWheelInterceptor.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: ListView(
              controller: outerController,
              children: [
                const SizedBox(height: 100),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    key: const ValueKey('inner-list'),
                    controller: innerController,
                    itemExtent: 50,
                    itemCount: 8, // maxScrollExtent = 400 - 200 = 200
                    itemBuilder: (_, i) => Text('Inner $i'),
                  ),
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Offset innerCenter =
        tester.getCenter(find.byKey(const ValueKey('inner-list')));

    // Пока внутренний список не на дне, колесо крутит только внутренний список.
    await _sendWheel(
      tester,
      position: innerCenter,
      scrollDelta: const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(innerController.offset, closeTo(120.0, 0.5));
    expect(outerController.offset, 0.0);

    // Докручиваем внутренний список ровно до его нижней границы (200.0).
    await _sendWheel(
      tester,
      position: innerCenter,
      scrollDelta: const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(innerController.offset, closeTo(200.0, 0.5));
    expect(outerController.offset, 0.0);

    // Внутренний список упёрся в край — следующий тик колеса плавно скроллит внешний список!
    await _sendWheel(
      tester,
      position: innerCenter,
      scrollDelta: const Offset(0, 150),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 7));
    expect(outerController.offset, greaterThan(0.0));
    expect(outerController.offset, lessThan(150.0));

    await tester.pumpAndSettle();
    expect(outerController.offset, closeTo(150.0, 0.5));
    expect(innerController.offset, closeTo(200.0, 0.5));
  });

  testWidgets(
      'TsundokuSmoothWheelInterceptor skips trackpad and Ctrl+wheel events',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const TsundokuSmoothScrollBehavior(),
        builder: TsundokuSmoothWheelInterceptor.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              controller: controller,
              itemExtent: 50,
              itemCount: 40,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Trackpad событие не перехватывается плавным скроллом (идёт напрямую в Scrollable сразу).
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
      kind: PointerDeviceKind.trackpad,
    );
    await tester.pump();
    expect(controller.offset, closeTo(100.0, 0.01));

    // Ctrl + mouse wheel пропускается перехватчиком.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(controller.offset, closeTo(200.0, 0.01));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets(
      'TsundokuSmoothWheelInterceptor syncs immediately on external jumpTo mid-glide',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const TsundokuSmoothScrollBehavior(),
        builder: TsundokuSmoothWheelInterceptor.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              controller: controller,
              itemExtent: 50,
              itemCount: 40,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 7));
    expect(controller.offset, greaterThan(0.0));
    expect(controller.offset, lessThan(300.0));

    // Внешний jumpTo (> 2px от последнего записанного значения) должен остановить тикер.
    controller.jumpTo(700.0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, closeTo(700.0, 0.01));
  });
}
