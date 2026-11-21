import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/ui/button.dart';

/// Widget/golden-тесты `Button.svelte` (варианты/размеры/loading/hold-fill).
void main() {
  Future<void> pump(
    WidgetTester tester, {
    ButtonVariant variant = ButtonVariant.secondary,
    ButtonSize size = ButtonSize.md,
    bool loading = false,
    bool iconOnly = false,
    double? holdProgress,
    bool disabled = false,
    VoidCallback? onPressed,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: TsundokuButton(
          variant: variant,
          size: size,
          loading: loading,
          iconOnly: iconOnly,
          holdProgress: holdProgress,
          disabled: disabled,
          onPressed: onPressed,
          child: const Text('OK'),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('tap: onPressed вызывается', (tester) async {
    var pressed = 0;
    await pump(tester, onPressed: () => pressed++);
    await tester.tap(find.byType(TsundokuButton));
    expect(pressed, 1);
  });

  testWidgets('loading: кнопка disabled, спиннер показан', (tester) async {
    var pressed = 0;
    await pump(tester, loading: true, onPressed: () => pressed++);
    await tester.tap(find.byType(TsundokuButton), warnIfMissed: false);
    expect(pressed, 0);
  });

  testWidgets('disabled: onPressed не вызывается', (tester) async {
    var pressed = 0;
    await pump(tester, disabled: true, onPressed: () => pressed++);
    await tester.tap(find.byType(TsundokuButton), warnIfMissed: false);
    expect(pressed, 0);
  });

  testWidgets('holdProgress fill: FractionallySizedBox отрисован', (tester) async {
    await pump(tester, holdProgress: 0.5);
    expect(find.byType(FractionallySizedBox), findsOneWidget);
  });

  testWidgets('iconOnly: квадрат минимальной ширины = высоте', (tester) async {
    await pump(tester, iconOnly: true, size: ButtonSize.md);
    // Внутренний Container держит constraints minWidth/minHeight = 36 (size-9).
    final container = tester.widget<Container>(find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.minWidth == 36));
    expect(container.constraints!.minHeight, 36);
  });

  testWidgets('golden: primary/md — 1440×900 эталон (Svelte-parity)',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: TsundokuButton(
          variant: ButtonVariant.primary,
          onPressed: () {},
          child: const Text('OK'),
        ),
      ),
    ));
    await tester.pump();
    await expectLater(
        find.byType(TsundokuButton),
        matchesGoldenFile(
            'goldens/button_primary_md.png'));
  });

  testWidgets('golden: danger + holdProgress 0.6', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: TsundokuButton(
          variant: ButtonVariant.danger,
          holdProgress: 0.6,
          onPressed: () {},
          child: const Text('Удалить'),
        ),
      ),
    ));
    await tester.pump();
    await expectLater(
        find.byType(TsundokuButton),
        matchesGoldenFile(
            'goldens/button_danger_hold.png'));
  });
}
