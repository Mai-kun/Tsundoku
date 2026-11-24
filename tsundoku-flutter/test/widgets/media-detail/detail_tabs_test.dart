import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_tabs.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';

/// Тесты `DetailTabs.svelte`: набор табов по типу, бейджи, onSelect.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpTabs(
    WidgetTester tester, {
    required SubTab active,
    required String mediaType,
    ({int current, int? total})? seasonProgress,
    int relatedCount = 0,
    int galleryCount = 0,
    void Function(SubTab)? onSelect,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: DetailTabs(
            active: active,
            mediaType: mediaType,
            seasonProgress: seasonProgress,
            relatedCount: relatedCount,
            galleryCount: galleryCount,
            onSelect: onSelect ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('tvshow: 5 табов, эпизоды с бейджем «3/12»', (tester) async {
    await pumpTabs(
      tester,
      active: SubTab.overview,
      mediaType: 'tvshow',
      seasonProgress: (current: 3, total: 12),
    );

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Эпизоды'), findsOneWidget);
    expect(find.text('Галерея'), findsOneWidget);
    expect(find.text('Связанное'), findsOneWidget);
    expect(find.text('Рекомендации'), findsOneWidget);
    expect(find.text('3/12'), findsOneWidget);
    expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
  });

  testWidgets('game: эпизоды-таба нет', (tester) async {
    await pumpTabs(tester, active: SubTab.overview, mediaType: 'game');

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Эпизоды'), findsNothing);
    expect(find.text('Галерея'), findsOneWidget);
    expect(find.text('Рекомендации'), findsOneWidget);
  });

  testWidgets('бейджи галереи и related — только при count > 0',
      (tester) async {
    await pumpTabs(
      tester,
      active: SubTab.gallery,
      mediaType: 'manga',
      galleryCount: 4,
      relatedCount: 0,
    );

    expect(find.text('4'), findsOneWidget);
    // related=0 → бейджа нет (счётчик внутри related-таба отсутствует).
    final relatedBadge = find.text('0');
    expect(relatedBadge, findsNothing);
  });

  testWidgets('onSelect: тап по табу отдаёт SubTab', (tester) async {
    SubTab? selected;
    await pumpTabs(
      tester,
      active: SubTab.overview,
      mediaType: 'manga',
      onSelect: (tab) => selected = tab,
    );

    await tester.tap(find.text('Связанное'));
    await tester.pump();
    expect(selected, SubTab.related);
  });

  testWidgets('didUpdateWidget: смена active двигает контроллер',
      (tester) async {
    SubTab active = SubTab.overview;
    late StateSetter setter;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: StatefulBuilder(builder: (context, setState) {
            setter = setState;
            return DetailTabs(
              active: active,
              mediaType: 'manga',
              seasonProgress: null,
              onSelect: (tab) => setter(() => active = tab),
            );
          }),
        ),
      ),
    ));
    await tester.pump();

    setter(() => active = SubTab.gallery);
    await tester.pumpAndSettle();
    // Контроллер переехал на gallery — underscore у галереи (проверяем
    // через повторный тап onSelect, он продолжит работать).
    await tester.tap(find.text('Обзор'));
    await tester.pumpAndSettle();
    expect(active, SubTab.overview);
  });

  testWidgets('tabAlignment.start: первый таб «Обзор» без отступа слева',
      (tester) async {
    await pumpTabs(
      tester,
      active: SubTab.overview,
      mediaType: 'tvshow',
    );

    final tabBarLeft = tester.getTopLeft(find.byType(TabBar)).dx;
    final overviewLeft = tester.getTopLeft(find.text('Обзор')).dx;
    // Только внутренний labelPadding (12px), без 52px startOffset.
    expect(overviewLeft - tabBarLeft, closeTo(12.0, 1.0));
  });
}
