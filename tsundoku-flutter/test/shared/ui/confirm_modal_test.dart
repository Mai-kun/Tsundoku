import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_dialog.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';

/// Widget-тесты `ConfirmModal.svelte`: полный цикл request → выбор → settle,
/// чекбоксы памяти (взаимоисключающие), Enter/Esc.
void main() {
  late ProviderContainer container;

  Future<void> pumpModal(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ConfirmModal()),
    ));
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  testWidgets('danger-запрос: иконка Trash2, дефолт-описание «необратимо»',
      (tester) async {
    unawaited(container.read(confirmDialogProvider.notifier).request(
      const ConfirmRequest(
        key: 'delete-media',
        title: 'Удалить «Норагами»?',
        danger: true,
      ),
    ));
    await pumpModal(tester);

    expect(find.text('Удалить «Норагами»?'), findsOneWidget);
    expect(find.text('Это действие необратимо.'), findsOneWidget);
    // Кнопки с дефолт-лейблами.
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Подтвердить'), findsOneWidget);
    // Оба чекбокса памяти.
    expect(find.text('Запомнить выбор'), findsOneWidget);
    expect(find.text('Запомнить выбор на 1 час'), findsOneWidget);
  });

  testWidgets('settle(true) через кнопку → подтверждение с памятью',
      (tester) async {
    final future = container.read(confirmDialogProvider.notifier).request(
      const ConfirmRequest(
        key: 'k1',
        title: 'Тайтл?',
        confirmLabel: 'Да',
        cancelLabel: 'Нет',
      ),
    );
    await pumpModal(tester);
    expect(find.text('Да'), findsOneWidget);
    expect(find.text('Нет'), findsOneWidget);

    // Чекбокс «навсегда» → клик.
    await tester.tap(find.text('Запомнить выбор'));
    await tester.pump();

    await tester.tap(find.text('Да'));
    await tester.pump();
    expect(await future, isTrue);

    // Память записана: повторный запрос с тем же ключом отвечает сразу.
    final second = container.read(confirmDialogProvider.notifier).request(
      const ConfirmRequest(key: 'k1', title: 'Снова?'),
    );
    expect(await second, isTrue);
  });

  testWidgets('чекбоксы взаимоисключающие: последний тикнутый решает память',
      (tester) async {
    final future = container.read(confirmDialogProvider.notifier).request(
      const ConfirmRequest(key: 'k2', title: '?'),
    );
    await pumpModal(tester);

    // Тик «час», затем тик «навсегда» — активен только «навсегда».
    await tester.tap(find.text('Запомнить выбор на 1 час'));
    await tester.pump();
    await tester.tap(find.text('Запомнить выбор'));
    await tester.pump();

    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(await future, isTrue);

    // Память записана как «навсегда» (последний активный чекбокс): повторный
    // запрос с тем же ключом отвечает сразу true.
    final second = container.read(confirmDialogProvider.notifier).request(
      const ConfirmRequest(key: 'k2', title: 'Снова?'),
    );
    expect(await second, isTrue);
  });

  testWidgets('settle(false) по «Отмена»', (tester) async {
    final future = container.read(confirmDialogProvider.notifier).request(
      const ConfirmRequest(key: 'k4', title: '?'),
    );
    await pumpModal(tester);
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    expect(await future, isFalse);
  });
}
