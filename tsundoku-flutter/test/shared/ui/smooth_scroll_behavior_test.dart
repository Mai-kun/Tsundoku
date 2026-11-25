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
    final double offset0 = controller.offset;
    expect(offset0, greaterThan(0.0));
    expect(offset0, lessThan(240.0));

    // Профиль скорости 2-го порядка (bell-curve velocity):
    // шаг на старте (t = 8ms) меньше шага на пике разгона (t = 24ms).
    await tester.pump(const Duration(milliseconds: 8));
    final double offset8 = controller.offset;
    final double step8 = offset8 - offset0;
    expect(offset8, greaterThan(offset0));

    await tester.pump(const Duration(milliseconds: 8));
    final double offset16 = controller.offset;
    final double step16 = offset16 - offset8;
    expect(offset16, greaterThan(offset8));

    await tester.pump(const Duration(milliseconds: 8));
    final double offset24 = controller.offset;
    final double step24 = offset24 - offset16;
    expect(offset24, greaterThan(offset16));
    expect(offset24, lessThan(240.0));

    // Ключевая проверка 2-го порядка: нет стартового «рывка» в t=0..8ms!
    expect(offset0, lessThan(step24));
    expect(step8, lessThan(step24));
    expect(step16, greaterThan(step8));

    // Длинный выкат в стиле Chromium (~260–300 мс): на отметке ~120 мс
    // скролл ещё мягко скользит, а не затухает мгновенно за 100 мс.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    final double offset120 = controller.offset;
    expect(offset120, greaterThan(offset24));
    expect(offset120, lessThan(200.0));

    // После достаточного времени скролл сходится точно к целевой позиции 240.0.
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(240.0, 0.25));
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
      'TsundokuSmoothWheelInterceptor skips subpixel trackpad swipes and Ctrl+wheel, intercepts discrete events',
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

    // Мелкий субпиксельный свайп тачпада (|dy| < 8) пропускается без перехвата.
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 4),
      kind: PointerDeviceKind.trackpad,
    );
    await tester.pump();
    expect(controller.offset, closeTo(4.0, 0.01));

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
    expect(controller.offset, closeTo(104.0, 0.01));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    // Дискретный щелчок колеса (например, пришедший как unknown на Wayland/GTK3)
    // перехватывается плавно, а не прыгает сразу на +120.
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 120),
      kind: PointerDeviceKind.unknown,
    );
    await tester.pump();
    expect(controller.offset, greaterThan(104.0));
    expect(controller.offset, lessThan(224.0));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(224.0, 0.5));
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
