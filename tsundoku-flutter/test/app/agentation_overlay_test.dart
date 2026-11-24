// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy_material;
import 'package:flutter_agentation/flutter_agentation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/main.dart';

void main() {
  testWidgets(
      'buildDebugAgentationOverlay allows typing in AnnotationPopup TextField inside material_ui MaterialApp',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final targetKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: buildDebugAgentationOverlay(mcpEnabled: false),
        home: Center(
          child: Container(
            key: targetKey,
            padding: const EdgeInsets.all(16),
            child: const Text('Поиск тайтлов'),
          ),
        ),
      ),
    );
    await tester.pump();

    // Включаем режим инспекции Agentation и кликаем по элементу, чтобы
    // открылся AnnotationPopup с legacy TextField.
    final ctx = targetKey.currentContext!;
    AgentationScope.of(ctx).toggleInspect();
    await tester.pump();

    await tester.tap(find.text('Поиск тайтлов'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final popupField = find.byType(legacy_material.TextField);
    expect(popupField, findsOneWidget);

    await tester.enterText(popupField, 'Сдвинуть отступ');
    await tester.pump();

    expect(find.text('Сдвинуть отступ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
