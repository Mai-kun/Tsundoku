import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sync_rows_skeleton.dart';

/// Тесты `SyncRowsSkeleton.svelte`: 3 строки скелетона с убывающими
/// ширинами (88/72/56%) + семантика статуса.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('рендер: 3 строки, ширины 88/72/56%, строки вне семантики',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: const MaterialApp(
        home: Material(child: SyncRowsSkeleton(label: 'Синхронизация…')),
      ),
    ));
    await tester.pump();

    // Основные блоки первой строки: w-2/5 (40%).
    final subLines = find.byWidgetPredicate((w) =>
        w is FractionallySizedBox && w.widthFactor == 0.4);
    expect(subLines, findsNWidgets(3)); // по одной на строку

    // Главные линии: 88/72/56%.
    final mainLines = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .where((f) => f.widthFactor != 0.4)
        .map((f) => f.widthFactor)
        .toList();
    expect(mainLines, containsAll([0.88, 0.72, 0.56]));

    // Скринридер-статус (role=status) — Semantics с label.
    final status = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Синхронизация…');
    expect(status, findsOneWidget);
  });
}
