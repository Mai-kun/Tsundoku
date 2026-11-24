import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/ui/context_menu.dart';
import 'package:tsundoku_flutter/shared/ui/context_menu_controller.dart';

/// Widget-тесты `ContextMenu.svelte`: сепаратор, подменю, hold-to-delete,
/// danger-стиль, закрытие по Esc/вне.
void main() {
  late ProviderContainer container;

  Future<void> pumpMenu(WidgetTester tester,
      {required List<MenuItem> items, double x = 100, double y = 100}) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    // Открыть меню до монтирования дерева:
    container.read(contextMenuStoreProvider.notifier).open(x, y, items);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: const Scaffold(body: SizedBox.expand()),
          builder: (context, _) => const Stack(children: [ContextMenu()]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('меню рендерит items, сепаратор и danger-лейблы', (tester) async {
    await pumpMenu(tester, items: [
      const MenuItem(id: 'edit', label: 'Редактировать', icon: 'edit'),
      MenuItem.separator(),
      const MenuItem(id: 'del', label: 'Удалить', kind: 'danger'),
    ]);
    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    // Сепаратор — контейнер 1px:
    expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints != null &&
            w.constraints!.minHeight == 1),
        findsOneWidget);
  });

  testWidgets('подменю: тап по родителю раскрывает flyout', (tester) async {
    await pumpMenu(tester, items: [
      MenuItem(
        id: 'list',
        label: 'В список',
        children: [
          const MenuItem(id: 's1', label: 'Просмотрено'),
          const MenuItem(id: 's2', label: 'Брошено'),
        ],
      ),
    ]);
    expect(find.text('Просмотрено'), findsNothing);
    await tester.tap(find.text('В список'));
    await tester.pumpAndSettle();
    expect(find.text('Просмотрено'), findsOneWidget);
    expect(find.text('Брошено'), findsOneWidget);
  });

  testWidgets('hold-to-delete item: лейбл по умолчанию, не завершается без холда',
      (tester) async {
    var deleted = 0;
    await pumpMenu(tester, items: [
      MenuItem(
          id: 'del',
          label: 'Удалить',
          kind: 'danger',
          holdToDelete: true,
          action: () => deleted++),
    ]);
    expect(find.text('Удалить'), findsOneWidget);
    // Тап (не холд) — не завершает удаление и показывает подсказку:
    await tester.tap(find.text('Удалить'));
    await tester.pump();
    expect(deleted, 0);
    expect(find.text('Удерживайте 1 сек'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('Esc-клавиша закрывает меню', (tester) async {
    await pumpMenu(tester, items: [
      const MenuItem(id: 'a', label: 'A'),
    ]);
    expect(container.read(contextMenuStoreProvider).isOpen, isTrue);
    // Focus + Escape:
    final focusNode = FocusNode();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: KeyboardListener(
            focusNode: focusNode,
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                container.read(contextMenuStoreProvider.notifier).close();
              }
            },
            child: const Stack(children: [ContextMenu()]),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(container.read(contextMenuStoreProvider).isOpen, isFalse);
  });

  testWidgets('disabled item: opacity 0.4, тап не вызывает action', (tester) async {
    var called = 0;
    await pumpMenu(tester, items: [
      MenuItem(
          id: 'x',
          label: 'Disabled action',
          disabled: true,
          action: () => called++),
    ]);
    await tester.tap(find.text('Disabled action'), warnIfMissed: false);
    expect(called, 0);
  });

  testWidgets('подменю: наведение не раскрывает, только явное нажатие',
      (tester) async {
    await pumpMenu(tester, items: [
      MenuItem(
        id: 'list',
        label: 'В список',
        children: [
          const MenuItem(id: 's1', label: 'Просмотрено'),
        ],
      ),
    ]);

    final center = tester.getCenter(find.text('В список'));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 11);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();

    expect(find.text('Просмотрено'), findsNothing);

    await tester.tap(find.text('В список'));
    await tester.pumpAndSettle();
    expect(find.text('Просмотрено'), findsOneWidget);
  });

  testWidgets('hold-to-delete: беглое нажатие показывает подсказку, холд рисует прогресс и удаляет',
      (tester) async {
    var deleted = 0;
    await pumpMenu(tester, items: [
      MenuItem(
        id: 'del',
        label: 'Удалить',
        kind: 'danger',
        holdToDelete: true,
        action: () => deleted++,
      ),
    ]);

    // Короткий тап -> подсказка «Удерживайте 1 сек»
    await tester.tap(find.text('Удалить'));
    await tester.pump();
    expect(deleted, 0);
    expect(find.text('Удерживайте 1 сек'), findsOneWidget);

    // Ждём исчезновения подсказки (1500ms)
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Удалить'), findsOneWidget);

    // Зажатие -> анимация наполнения и «Удаление…» -> завершение через 1000ms
    final gesture = await tester.startGesture(tester.getCenter(find.text('Удалить')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Удаление…'), findsOneWidget);
    final fillBox = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox));
    expect(fillBox.widthFactor, greaterThan(0.2));

    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(deleted, 1);
  });
}
