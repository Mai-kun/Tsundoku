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
      'TsundokuSmoothWheelInterceptor uses SmoothWheelScrollActivity with critically damped spring and kWheelStepMultiplier',
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

    const double rawDelta = 120.0;
    final double expectedTarget = rawDelta * kWheelStepMultiplier; // 210.0

    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, rawDelta),
    );

    // Активность переключилась на SmoothWheelScrollActivity сразу при тике колеса.
    final ScrollPosition position = controller.position;
    expect(position.activity, isA<SmoothWheelScrollActivity>());
    expect(position.activity!.isScrolling, isTrue);
    expect(position.activity!.shouldIgnorePointer, isTrue);

    // Плавный старт без ступеньки, монотонно приближается к цели без перелёта.
    double prev = 0.0;
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final double current = controller.offset;
      expect(current, greaterThan(prev));
      expect(current, lessThanOrEqualTo(expectedTarget));
      if (position.activity is SmoothWheelScrollActivity) {
        expect(position.activity!.isScrolling, isTrue);
        expect(position.activity!.shouldIgnorePointer, isTrue);
      }
      prev = current;
    }

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(expectedTarget, 0.25));
    expect(position.activity!.isScrolling, isFalse);
    expect(position.activity!.shouldIgnorePointer, isFalse);
  });

  testWidgets(
      'SmoothWheelScrollActivity sends ScrollStartNotification once, ScrollEndNotification once, keeps shouldIgnorePointer=true, and suppresses card MouseRegion hover during scroll',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    int startNotifications = 0;
    int updateNotifications = 0;
    int endNotifications = 0;
    int hoverEnters = 0;

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const TsundokuSmoothScrollBehavior(),
        builder: TsundokuSmoothWheelInterceptor.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  startNotifications++;
                } else if (notification is ScrollUpdateNotification) {
                  updateNotifications++;
                } else if (notification is ScrollEndNotification) {
                  endNotifications++;
                }
                return false;
              },
              child: ListView.builder(
                controller: controller,
                itemExtent: 50,
                itemCount: 40,
                itemBuilder: (_, i) => MouseRegion(
                  onEnter: (_) => hoverEnters++,
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.book, size: 16),
                        const SizedBox(width: 8),
                        Text('Card $i'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Наводим курсор на текст/иконку внутри карточки до начала скролла.
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(50, 125)));
    await tester.pump();
    final int initialHoverEnters = hoverEnters;

    // Серия из 4 тиков колеса подряд (несмотря на движение карточек под курсором).
    for (int i = 0; i < 4; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
      await tester.pump(const Duration(milliseconds: 24));
      await tester.sendEventToBinding(pointer.hover(const Offset(50, 125)));

      final ScrollPosition pos = controller.position;
      expect(pos.activity, isA<SmoothWheelScrollActivity>());
      expect(pos.activity!.isScrolling, isTrue);
      expect(pos.activity!.shouldIgnorePointer, isTrue);
      expect(startNotifications, 1);
      expect(endNotifications, 0);
    }

    // Во время активного скролла MouseRegion.onEnter проплывающих карточек не срабатывал.
    expect(hoverEnters, initialHoverEnters);
    expect(updateNotifications, greaterThan(1));

    // Проверяем до полной остановки: пока пружина доезжает, start=1, end=0.
    while (controller.position.activity!.isScrolling) {
      expect(controller.position.activity!.shouldIgnorePointer, isTrue);
      expect(startNotifications, 1);
      expect(endNotifications, 0);
      await tester.pump(const Duration(milliseconds: 16));
    }

    // После полной остановки ScrollStart ровно 1, ScrollEnd ровно 1, pointer снова активен.
    expect(startNotifications, 1);
    expect(endNotifications, 1);
    expect(controller.position.activity!.isScrolling, isFalse);
    expect(controller.position.activity!.shouldIgnorePointer, isFalse);
  });

  testWidgets(
      'SmoothWheelScrollActivity preserves positive velocity without dropping to 0 between consecutive wheel ticks',
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
              itemCount: 80,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Первый тик запускает движение.
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 80),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.position.activity!.velocity, greaterThan(0.0));

    // Серия последовательных тиков — скорость ни разу не сбрасывается в 0 между тиками.
    for (int i = 0; i < 5; i++) {
      final double velocityBeforeTick = controller.position.activity!.velocity;
      expect(velocityBeforeTick, greaterThan(0.0));

      await _sendWheel(
        tester,
        position: const Offset(200, 150),
        scrollDelta: const Offset(0, 80),
      );
      expect(
        controller.position.activity!.velocity,
        equals(velocityBeforeTick),
      );

      await tester.pump(const Duration(milliseconds: 25));
      expect(controller.position.activity!.velocity, greaterThan(0.0));
    }

    await tester.pumpAndSettle();
    expect(controller.position.activity!.velocity, 0.0);
  });

  testWidgets(
      'TsundokuSmoothWheelInterceptor accelerates fast wheel spins up to kFastSpinMaxBoost and resets after window',
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
              itemCount: 80,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Одиночный тик -> базовый множитель 1.0 * kWheelStepMultiplier (100 * 1.75 = 175).
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(100.0 * kWheelStepMultiplier, 0.25));

    // Быстрая серия из 6 тиков с интервалом 30 мс (< kFastSpinWindowMs = 85 мс):
    // должна разогнать boost до kFastSpinMaxBoost и при retargeting'е не прыгать назад.
    final double startOffset = controller.offset;
    double prevOffset = startOffset;
    for (int i = 0; i < 6; i++) {
      await _sendWheel(
        tester,
        position: const Offset(200, 150),
        scrollDelta: const Offset(0, 50),
      );
      await tester.pump(const Duration(milliseconds: 30));
      expect(controller.offset, greaterThanOrEqualTo(prevOffset));
      prevOffset = controller.offset;
    }

    await tester.pumpAndSettle();
    final double fastSpinDistance = controller.offset - startOffset;
    final double unboostedDistance = 6 * 50.0 * kWheelStepMultiplier;
    expect(fastSpinDistance, greaterThan(unboostedDistance * 1.4));
    expect(
      fastSpinDistance,
      lessThanOrEqualTo(unboostedDistance * kFastSpinMaxBoost + 0.5),
    );

    // После паузы >= kFastSpinWindowMs комбо-ускорение сбрасывается обратно в 1.0.
    final double beforeResetTick = controller.offset;
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
    );
    await tester.pumpAndSettle();
    expect(
      controller.offset - beforeResetTick,
      closeTo(100.0 * kWheelStepMultiplier, 0.25),
    );
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

    // Два тика с паузой >= kFastSpinWindowMs дают 2 * 100 * kWheelStepMultiplier = 350.0.
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
    );
    await tester.pump(const Duration(milliseconds: 90));
    final double midOffset = controller.offset;
    expect(midOffset, greaterThan(0.0));

    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThanOrEqualTo(midOffset));
    expect(controller.offset, lessThan(200.0 * kWheelStepMultiplier));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(200.0 * kWheelStepMultiplier, 0.5));
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

    // Пока внутренний список не на дне, колесо крутит только внутренний список (60 * 1.75 = 105).
    await _sendWheel(
      tester,
      position: innerCenter,
      scrollDelta: const Offset(0, 60),
    );
    await tester.pumpAndSettle();
    expect(innerController.offset, closeTo(60.0 * kWheelStepMultiplier, 0.5));
    expect(outerController.offset, 0.0);

    // Докручиваем внутренний список ровно до его нижней границы (200.0).
    await _sendWheel(
      tester,
      position: innerCenter,
      scrollDelta: const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(innerController.offset, closeTo(200.0, 0.5));
    expect(outerController.offset, 0.0);

    // Внутренний список упёрся в край — следующий тик колеса плавно скроллит внешний список!
    await _sendWheel(
      tester,
      position: innerCenter,
      scrollDelta: const Offset(0, 100),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(outerController.offset, greaterThan(0.0));
    expect(outerController.offset, lessThan(100.0 * kWheelStepMultiplier));

    await tester.pumpAndSettle();
    expect(outerController.offset, closeTo(100.0 * kWheelStepMultiplier, 0.5));
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
    // перехватывается плавно с множителем kWheelStepMultiplier.
    await _sendWheel(
      tester,
      position: const Offset(200, 150),
      scrollDelta: const Offset(0, 100),
      kind: PointerDeviceKind.unknown,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(104.0));
    expect(controller.offset, lessThan(104.0 + 100.0 * kWheelStepMultiplier));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(104.0 + 100.0 * kWheelStepMultiplier, 0.5));
  });

  testWidgets(
      'TsundokuSmoothWheelInterceptor stops SmoothWheelScrollActivity immediately on external jumpTo mid-glide',
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
      scrollDelta: const Offset(0, 200),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(0.0));
    expect(controller.offset, lessThan(200.0 * kWheelStepMultiplier));
    expect(controller.position.activity, isA<SmoothWheelScrollActivity>());

    // Внешний jumpTo должен сразу остановить SmoothWheelScrollActivity.
    controller.jumpTo(700.0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, closeTo(700.0, 0.01));
    expect(controller.position.activity, isNot(isA<SmoothWheelScrollActivity>()));
    expect(controller.position.activity!.isScrolling, isFalse);
  });
}
