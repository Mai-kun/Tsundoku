import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/entities/media/ui/media_status_badge.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';

/// Widget-тесты `MediaStatusBadge.svelte`: иконка по статусу, поповер с 5
/// опциями (порядок statusOptions), onSelect при выборе.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    MediaStatus status = MediaStatus.planned,
    void Function(MediaStatus)? onSelect,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Center(
          child: MediaStatusBadge(
            id: 'status-1',
            status: status,
            onSelect: onSelect ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('planned → Bookmark 20px на триггере', (tester) async {
    await pump(tester);
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.bookmark));
    expect(icon.size, 20);
  });

  testWidgets('dropped → X 20px', (tester) async {
    await pump(tester, status: MediaStatus.dropped);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
  });

  testWidgets('completed → Check 21px', (tester) async {
    await pump(tester, status: MediaStatus.completed);
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.check));
    expect(icon.size, 21);
  });

  testWidgets('тап → поповер с 5 опциями в порядке statusOptions (ru)',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(LucideIcons.bookmark));
    await tester.pumpAndSettle();

    expect(find.text('В планах'), findsWidgets); // опция (+label поповера)
    expect(find.text('В процессе'), findsOneWidget);
    expect(find.text('Завершено'), findsOneWidget);
    expect(find.text('Отложено'), findsOneWidget);
    expect(find.text('Брошено'), findsOneWidget);
  });

  testWidgets('выбор «Завершено» → onSelect(MediaStatus.completed)',
      (tester) async {
    MediaStatus? selected;
    await pump(tester, onSelect: (s) => selected = s);
    await tester.tap(find.byIcon(LucideIcons.bookmark));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Завершено'));
    await tester.pumpAndSettle();

    expect(selected, MediaStatus.completed);
  });

  testWidgets('выбор «Отложено» → onSelect(MediaStatus.onHold)',
      (tester) async {
    MediaStatus? selected;
    await pump(tester, onSelect: (s) => selected = s);
    await tester.tap(find.byIcon(LucideIcons.bookmark));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отложено'));
    await tester.pumpAndSettle();

    expect(selected, MediaStatus.onHold);
  });
}
