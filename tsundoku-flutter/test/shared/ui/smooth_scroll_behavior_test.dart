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
      'TsundokuSmoothWheelInterceptor uses EaseOutCubic with immediate start and kWheelStepMultiplier',
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

    // За первые 16 мс EaseOutCubic делает уверенный старт без фазовой задержки.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final double offset16 = controller.offset;
    expect(offset16, greaterThan(0.0));
    expect(offset16, lessThan(expectedTarget));

    // Следующие 16 мс: скорость монотонно затухает (step16to32 < step0to16),
    // как в детерминированной кривой Chromium EaseOutCubic.
    await tester.pump(const Duration(milliseconds: 16));
    final double offset32 = controller.offset;
    final double step16to32 = offset32 - offset16;
    expect(step16to32, greaterThan(0.0));
    expect(step16to32, lessThan(offset16));

    // На половине длительности (~77 мс от старта) скролл уже прошёл > 80% пути.
    await tester.pump(const Duration(milliseconds: 45));
    final double offset77 = controller.offset;
    expect(offset77, greaterThan(expectedTarget * 0.8));
    expect(offset77, lessThan(expectedTarget));

    // По истечении kScrollDurationMs (155 мс) анимация точно завершена.
    await tester.pump(Duration(milliseconds: kScrollDurationMs - 77));
    expect(controller.offset, closeTo(expectedTarget, 0.25));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(expectedTarget, 0.01));
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

    // После паузы >= kFastSpinWindowMs (уже прошло >= 155 мс в pumpAndSettle)
    // комбо-ускорение сбрасывается обратно в 1.0.
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
      scrollDelta: const Offset(0, 200),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(0.0));
    expect(controller.offset, lessThan(200.0 * kWheelStepMultiplier));

    // Внешний jumpTo (> 2px от последнего записанного значения) должен остановить тикер.
    controller.jumpTo(700.0);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, closeTo(700.0, 0.01));
  });
}
