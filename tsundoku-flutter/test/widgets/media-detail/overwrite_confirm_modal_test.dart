import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/widgets/media-detail/overwrite_confirm_modal.dart';

/// Тесты `OverwriteConfirmModal.svelte`: заголовок/подсказка, три кнопки
/// (safe/full/cancel) с колбеками, busy-disabled.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpModal(
    WidgetTester tester, {
    bool busy = false,
    required void Function() onFillMissing,
    required void Function() onOverwrite,
    required void Function() onClose,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: OverwriteConfirmModal(
            isOpen: true,
            busy: busy,
            onFillMissing: onFillMissing,
            onOverwrite: onOverwrite,
            onClose: onClose,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('текст: заголовок конфликта + подсказка + подписи кнопок',
      (tester) async {
    await pumpModal(
      tester,
      busy: false,
      onFillMissing: () {},
      onOverwrite: () {},
      onClose: () {},
    );

    expect(find.textContaining('ручные изменения'), findsOneWidget);
    expect(find.textContaining('Обновить только пустые'), findsOneWidget);
    expect(find.textContaining('Перезаписать'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
  });

  testWidgets('safe → onFillMissing; full → onOverwrite; отмена → onClose',
      (tester) async {
    var filled = 0;
    var overwrote = 0;
    var closed = 0;
    await pumpModal(
      tester,
      busy: false,
      onFillMissing: () => filled += 1,
      onOverwrite: () => overwrote += 1,
      onClose: () => closed += 1,
    );

    await tester.tap(find.textContaining('Обновить только пустые'));
    await tester.pump();
    expect(filled, 1);

    await tester.tap(find.textContaining('Перезаписать'));
    await tester.pump();
    expect(overwrote, 1);

    await tester.tap(find.text('Отмена'));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('busy: кнопки не срабатывают', (tester) async {
    var any = 0;
    await pumpModal(
      tester,
      busy: true,
      onFillMissing: () => any += 1,
      onOverwrite: () => any += 1,
      onClose: () => any += 1,
    );

    await tester.tap(find.textContaining('Обновить только пустые'),
        warnIfMissed: false);
    await tester.tap(find.textContaining('Перезаписать'), warnIfMissed: false);
    await tester.tap(find.text('Отмена'), warnIfMissed: false);
    await tester.pump();
    expect(any, 0);
  });
}
