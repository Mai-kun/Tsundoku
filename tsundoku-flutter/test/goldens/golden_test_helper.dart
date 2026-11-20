import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Golden-хелпер Tsundoku.
///
/// Рендерит [widget] на эталонном desktop-вьюпорте **1440×900 @ dpr 1.0** —
/// ровно том canvas-размере, на котором снимаются Svelte-скриншоты
/// (mediatracker-ui/checks/harness, backstop-вьюпорт "desktop").
///
/// Шрифт Inter уже загружен в test/flutter_test_config.dart.
///
/// Генерация/обновление эталона:
/// `flutter test --update-goldens test/goldens`
void tsundokuGoldenTest(
  String name,
  Widget widget, {
  Size size = const Size(1440, 900),
}) {
  testWidgets('golden: $name', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(widget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  });
}
