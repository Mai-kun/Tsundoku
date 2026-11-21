import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_layout.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_window.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  Future<void> pumpWindow(
    WidgetTester tester, {
    required ValueChanged<WorkspaceRect> onRectChange,
    required ValueChanged<bool> onDragStateChange,
    required VoidCallback onSettled,
    WorkspaceRect? rect,
    bool collapsed = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var current = rect ?? const WorkspaceRect(x: 100, y: 100, w: 380, h: 320);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Stack(
            children: [
              StatefulBuilder(
                builder: (context, setOuter) {
                  return WorkspaceWindow(
                      id: 'main',
                      title: 'Основное',
                      icon: LucideIcons.fileText,
                      count: 3,
                      rect: current,
                      z: 1,
                      highlighted: false,
                      collapsed: collapsed,
                      onCollapsedChange: (v) {},
                      onFront: () {},
                      onHoverChange: (_) {},
                      onDragStateChange: onDragStateChange,
                      onSettled: onSettled,
                      onRectChange: (next) {
                        current = next;
                        onRectChange(next);
                        setOuter(() {});
                      },
                      viewportW: 1440,
                      viewportH: 900,
                    child: const Text('Тело окна'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('шапка: иконка, uppercase-тайтл, count-бейдж, chevron',
      (tester) async {
    await pumpWindow(
      tester,
      onRectChange: (_) {},
      onDragStateChange: (_) {},
      onSettled: () {},
    );
    expect(find.text('ОСНОВНОЕ'), findsOneWidget); // uppercase + tracking
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(LucideIcons.fileText), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronUp), findsOneWidget);
    expect(find.text('Тело окна'), findsOneWidget);
  });

  testWidgets('драг шапки двигает окно (live clamp в вьюпорт)', (tester) async {
    WorkspaceRect? last;
    var dragging = false;
    var settled = false;
    await pumpWindow(
      tester,
      onRectChange: (r) => last = r,
      onDragStateChange: (v) => dragging = v,
      onSettled: () => settled = true,
    );
    final header = find.text('ОСНОВНОЕ');
    final start = tester.getCenter(header);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    // Двигаем на (+500, +900) — окно должно упереться в границы вьюпорта.
    await gesture.moveBy(const Offset(500, 900));
    await tester.pump();
    expect(dragging, isTrue);
    expect(last, isNotNull);
    // x=100+500=600 (в границах), y упёрся в нижний край 900-16-320=564.
    expect(last!.x, 600);
    // Нижний край: 900 - 16 - 320 = 564.
    expect(last!.y, 564);
    await gesture.up();
    await tester.pump();
    expect(dragging, isFalse);
    expect(settled, isTrue);
  });

  testWidgets('драг не клипится ниже TOP_BAR и правее SIDE_MARGIN',
      (tester) async {
    WorkspaceRect? last;
    await pumpWindow(
      tester,
      rect: const WorkspaceRect(x: 200, y: 200, w: 380, h: 320),
      onRectChange: (r) => last = r,
      onDragStateChange: (_) {},
      onSettled: () {},
    );
    final gesture = await tester.startGesture(tester.getCenter(find.text('ОСНОВНОЕ')));
    await tester.pump();
    // Вверх и влево за границы.
    await gesture.moveBy(const Offset(-1000, -1000));
    await tester.pump();
    expect(last!.x, 16);
    expect(last!.y, 64);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('grip ресайза увеличивает окно с clamp на вьюпорт',
      (tester) async {
    WorkspaceRect? last;
    await pumpWindow(
      tester,
      rect: const WorkspaceRect(x: 100, y: 100, w: 380, h: 320),
      onRectChange: (r) => last = r,
      onDragStateChange: (_) {},
      onSettled: () {},
    );
    // Grip: правый нижний угол окна — 20x20.
    final windowTopLeft = const Offset(100, 100);
    final gripCenter = windowTopLeft + const Offset(380 - 10, 320 - 10);
    final gesture = await tester.startGesture(gripCenter);
    await tester.pump();
    await gesture.moveBy(const Offset(900, 700));
    await tester.pump();
    // w: max(380, min(380+900, 1440-100-16)) = 1280.
    expect(last!.w, 1280);
    // h: max(320, min(320+700, 900-100-16)) = 784.
    expect(last!.h, 784);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('collapse: тело скрыто (opacity), chevron развёрнут', (tester) async {
    await pumpWindow(
      tester,
      collapsed: true,
      onRectChange: (_) {},
      onDragStateChange: (_) {},
      onSettled: () {},
    );
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0);
    final rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation));
    expect(rotation.turns, 0.5);
    expect(find.text('Тело окна'), findsOneWidget); // смонтировано, но невидимо
  });

  testWidgets('count=0/null — бейдж не рендерится', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var current = const WorkspaceRect(x: 100, y: 100, w: 380, h: 320);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Stack(
            children: [
              StatefulBuilder(builder: (context, setOuter) {
                return WorkspaceWindow(
                  id: 'notes',
                  title: 'Заметки',
                  icon: LucideIcons.fileText,
                  count: 0,
                  rect: current,
                  z: 1,
                  highlighted: false,
                  collapsed: false,
                  onCollapsedChange: (_) {},
                  onFront: () {},
                  onHoverChange: (_) {},
                  onDragStateChange: (_) {},
                  onSettled: () {},
                  onRectChange: (r) {
                    current = r;
                    setOuter(() {});
                  },
                  viewportW: 1440,
                  viewportH: 900,
                  child: const SizedBox.shrink(),
                );
              }),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('0'), findsNothing);
  });
}
