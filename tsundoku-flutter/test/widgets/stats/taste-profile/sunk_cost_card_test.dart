import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/sunk_cost_card.dart';

Future<void> pumpSunkCostCard(
  WidgetTester tester, {
  required SunkCost sunkCost,
  Locale locale = Locale.ru,
  double width = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tProvider.overrideWithValue(I18nDictionary(locale)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: SunkCostCard(sunkCost: sunkCost),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('рендеринг со всеми категориями и часами', (tester) async {
    const sunkCost = SunkCost(
      lowScoreHours: 42.0,
      percentageOfTotal: 12.5,
      titlesCount: 8,
      categoryBreakdown: {
        'game': 25.0,
        'movie': 17.0,
        'anime': 0.0,
      },
    );

    await pumpSunkCostCard(tester, sunkCost: sunkCost);

    expect(find.byIcon(LucideIcons.hourglass), findsOneWidget);
    expect(find.text('Синдром потерянного времени'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget);
    expect(
      find.text(
        '42 ч. (12.5% всего времени) ушло на непонравившиеся или брошенные произведения',
      ),
      findsOneWidget,
    );
    expect(find.text('тайтлов в убыточной зоне: 8'), findsOneWidget);

    // Легенда: Игры и Фильмы (anime == 0 не рендерится)
    expect(find.text('Игры'), findsOneWidget);
    expect(find.text('25 ч.'), findsOneWidget);
    expect(find.text('Фильмы'), findsOneWidget);
    expect(find.text('17 ч.'), findsOneWidget);
    expect(find.text('Аниме'), findsNothing);

    // Совет
    expect(
      find.text(
        'Смелее бросайте то, что не приносит радости — впереди тысячи отличных историй.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('пустой breakdown: прогресс-бар и легенда не отображаются',
      (tester) async {
    const sunkCost = SunkCost(
      lowScoreHours: 0.0,
      percentageOfTotal: 0.0,
      titlesCount: 0,
      categoryBreakdown: {},
    );

    await pumpSunkCostCard(tester, sunkCost: sunkCost);

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('тайтлов в убыточной зоне: 0'), findsOneWidget);
    expect(find.text('Игры'), findsNothing);
  });

  testWidgets('английская локаль', (tester) async {
    const sunkCost = SunkCost(
      lowScoreHours: 10.0,
      percentageOfTotal: 5.0,
      titlesCount: 2,
      categoryBreakdown: {'book': 10.0},
    );

    await pumpSunkCostCard(
      tester,
      sunkCost: sunkCost,
      locale: Locale.en,
    );

    expect(find.text('Lost time syndrome'), findsOneWidget);
    expect(
      find.text(
        '10 h (5% of your total time) went to titles you didn\'t enjoy or dropped',
      ),
      findsOneWidget,
    );
    expect(find.text('titles in the red zone: 2'), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('10 h'), findsOneWidget);
    expect(
      find.text(
        "Don't be afraid to drop what brings no joy — thousands of great stories lie ahead.",
      ),
      findsOneWidget,
    );
  });
}
