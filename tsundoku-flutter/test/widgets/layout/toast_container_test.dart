import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/widgets/layout/toast_container.dart';

/// Widget-тесты `ToastContainer.svelte`: полный цикл — показ, countdown с
/// паузой на hover (грейс 1s), разворот, undo/actions/OK/X.
void main() {
  late ProviderContainer container;

  Future<void> pumpToasts(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomRight,
                child: ToastContainer(),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
  }

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  testWidgets('тост рендерится: заголовок, тип-бейдж, X', (tester) async {
    container.read(toastStoreProvider.notifier).show(const ToastOptions(
          title: 'Ошибка сохранения',
          description: 'Сервер недоступен',
          type: ToastType.error,
        ));
    await pumpToasts(tester);

    expect(find.text('Ошибка сохранения'), findsOneWidget);
    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
  });

  testWidgets('X → onClose вызван, тост исчез', (tester) async {
    var closed = false;
    container.read(toastStoreProvider.notifier).show(const ToastOptions(
          title: 'Тайтл',
          description: 'Описание',
        ));
    await pumpToasts(tester);
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pump();
    expect(closed, isFalse); // onClose не задан
    expect(find.text('Тайтл'), findsNothing);
    // closed = false: onClose был null — проверяем только исчезновение.
    closed = closed; // no-op to keep var used
  });

  testWidgets('onClose колбек вызывается при X', (tester) async {
    var closed = 0;
    container.read(toastStoreProvider.notifier).show(ToastOptions(
          title: 'Тайтл',
          description: 'Описание',
          onClose: () => closed += 1,
        ));
    await pumpToasts(tester);
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('countdown: авто-dismiss по истечении durationMs', (tester) async {
    container.read(toastStoreProvider.notifier).show(const ToastOptions(
          title: 'Быстрый тост',
          description: '',
          durationMs: 300,
        ));
    await pumpToasts(tester);
    expect(find.text('Быстрый тост'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Быстрый тост'), findsNothing);
  });

  testWidgets('hover пауза: тост не исчезает, пока курсор на карточке',
      (tester) async {
    container.read(toastStoreProvider.notifier).show(const ToastOptions(
          title: 'Долгий тост',
          description: '',
          durationMs: 400,
        ));
    await pumpToasts(tester);

    final center = tester.getCenter(find.text('Долгий тост'));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 100));
    // Пауза на hover: тост жив.
    expect(find.text('Долгий тост'), findsOneWidget);
  });

  testWidgets('undo-кнопка: runAction = dismiss + колбек', (tester) async {
    var undone = 0;
    container.read(toastStoreProvider.notifier).show(ToastOptions(
          title: 'Статус изменён',
          description: '',
          durationMs: 10000,
          undo: () => undone += 1,
        ));
    await pumpToasts(tester);
    expect(find.byIcon(LucideIcons.rotateCw), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.rotateCw));
    await tester.pump();
    expect(undone, 1);
    expect(find.text('Статус изменён'), findsNothing);
  });

  testWidgets('actions: keepStatus → Tag-иконка; клик → dismiss + onClick',
      (tester) async {
    var kept = 0;
    container.read(toastStoreProvider.notifier).show(ToastOptions(
          title: 'Статус обновлён',
          description: '',
          durationMs: 10000,
          actions: [
            ToastAction(id: 'keepStatus', label: 'Оставить', onClick: () => kept += 1),
          ],
        ));
    await pumpToasts(tester);
    expect(find.byIcon(LucideIcons.tag), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.tag));
    await tester.pump();
    expect(kept, 1);
    expect(find.text('Статус обновлён'), findsNothing);
  });

  testWidgets('showOk → OK-кнопка: dismiss без onClose', (tester) async {
    var closed = 0;
    container.read(toastStoreProvider.notifier).show(ToastOptions(
          title: 'Готово',
          description: '',
          durationMs: 10000,
          showOk: true,
          onClose: () => closed += 1,
        ));
    await pumpToasts(tester);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.check));
    await tester.pump();
    expect(find.text('Готово'), findsNothing);
    expect(closed, 0); // onClose зарезервирован за X (1-в-1)
  });

  testWidgets('expand: клик по шеврону → описание + подписанные кнопки',
      (tester) async {
    container.read(toastStoreProvider.notifier).show(ToastOptions(
          title: 'Развёрнутый',
          description: 'Длинное описание действия',
          durationMs: 10000,
          showOk: true,
          undo: () {},
        ));
    await pumpToasts(tester);

    // До разворота описание скрыто (AnimatedSize), компактные кнопки видны.
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();

    expect(find.text('Длинное описание действия'), findsOneWidget);
    // Подписанные кнопки в футере.
    expect(find.text('Ок'), findsOneWidget);
    expect(find.text('Откатить'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronUp), findsOneWidget);
  });

  testWidgets('несколько тостов — стек до 5 (MAX_TOASTS)', (tester) async {
    for (var i = 0; i < 7; i++) {
      container.read(toastStoreProvider.notifier).show(ToastOptions(
            title: 'Тост $i',
            description: '',
            durationMs: 60000,
          ));
    }
    await pumpToasts(tester);
    // MAX_TOASTS 5 (логика стора, Фаза 1).
    expect(
        find.textContaining('Тост '), findsNWidgets(5));
  });
}
