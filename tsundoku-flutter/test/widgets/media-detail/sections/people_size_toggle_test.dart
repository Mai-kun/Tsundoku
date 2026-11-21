import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/utils/ui_settings.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/people_size_toggle.dart';

/// Тесты `PeopleSizeToggle.svelte`: переключение компакт/крупный вид для
/// cast/staff-блоков (сохранение в uiSettings по категории).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpToggle(
    WidgetTester tester, {
    required String category,
    required PeopleBlock block,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: const MaterialApp(
        home: Material(
          child: PeopleSizeToggle(category: 'anime', block: PeopleBlock.cast),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('дефолт compact: List активен, LayoutGrid неактивен',
      (tester) async {
    await pumpToggle(tester, category: 'anime', block: PeopleBlock.cast);

    // Обе иконки присутствуют; компактная (list) — активная (белая).
    expect(find.byIcon(LucideIcons.list), findsOneWidget);
    expect(find.byIcon(LucideIcons.layoutGrid), findsOneWidget);
    final listIcon = tester.widget<Icon>(find.byIcon(LucideIcons.list));
    final gridIcon = tester.widget<Icon>(find.byIcon(LucideIcons.layoutGrid));
    expect(listIcon.color, Colors.white); // bg-accent text-white
    expect(gridIcon.color, isNot(Colors.white)); // text-muted
  });

  testWidgets('тап на крупный вид → переключение в uiSettings (cast)',
      (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container = ProviderContainer(),
      child: const MaterialApp(
        home: Material(
          child: PeopleSizeToggle(category: 'anime', block: PeopleBlock.cast),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(LucideIcons.layoutGrid));
    await tester.pumpAndSettle();

    expect(
      container.read(uiSettingsProvider).castSizeByCategory['anime'],
      PeopleCardSize.large,
    );
    // Grid теперь активен.
    final gridIcon = tester.widget<Icon>(find.byIcon(LucideIcons.layoutGrid));
    expect(gridIcon.color, Colors.white);
  });

  testWidgets('staff-блок хранит размер отдельно от cast', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container = ProviderContainer(),
      child: const MaterialApp(
        home: Material(
          child: PeopleSizeToggle(category: 'anime', block: PeopleBlock.staff),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(LucideIcons.layoutGrid));
    await tester.pumpAndSettle();

    expect(
      container.read(uiSettingsProvider).staffSizeByCategory['anime'],
      PeopleCardSize.large,
    );
    expect(
      container.read(uiSettingsProvider).castSizeByCategory['anime'] ??
          PeopleCardSize.compact,
      isNot(PeopleCardSize.large),
    );
  });
}
