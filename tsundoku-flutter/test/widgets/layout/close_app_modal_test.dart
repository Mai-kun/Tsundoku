import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/widgets/layout/close_app_modal.dart';

/// Widget-тесты `CloseAppModal.svelte`: выбор tray/exit, Apply с биндингами,
/// Cancel/Esc → onClose.
void main() {
  late ProviderContainer container;
  var closed = 0;
  var exitCalled = 0;
  var toastShown = 0;

  Future<void> pumpModal(WidgetTester tester) async {
    closed = 0;
    exitCalled = 0;
    toastShown = 0;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CloseAppModal(
          onClose: () => closed += 1,
          closeWindow: () async {},
          showToast:
              ({required title, required description}) => toastShown += 1,
        ),
      ),
    ));
    await tester.pump();
  }

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  testWidgets('дефолт: выбран «в трей»; Apply → closeToTray + onClose',
      (tester) async {
    await pumpModal(tester);
    expect(find.text('Сворачивать в трей'), findsOneWidget);
    expect(find.text('Полный выход из Tsundoku'), findsOneWidget);
    expect(find.text('Применить'), findsOneWidget);

    await tester.tap(find.text('Применить'));
    await tester.pump();
    // Tray-биндинг без AppExit (null) → только onClose.
    expect(closed, 1);
    expect(exitCalled, 0);
  });

  testWidgets('выбор «полный выход» → radio переключается, Apply не закрывает',
      (tester) async {
    await pumpModal(tester);
    await tester.tap(find.text('Полный выход из Tsundoku'));
    await tester.pump();
    await tester.tap(find.text('Применить'));
    await tester.pump();
    // exitApp без AppExit — nothing called; onClose НЕ вызван (в Svelte
    // после exitApp окно закрывается браузером).
    expect(closed, 0);
  });

  testWidgets('Cancel → onClose', (tester) async {
    await pumpModal(tester);
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('Escape → onClose', (tester) async {
    await pumpModal(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);
  });
}
