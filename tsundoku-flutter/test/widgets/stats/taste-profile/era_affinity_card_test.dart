import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/era_affinity_card.dart';

Future<void> pumpEraAffinityCard(
  WidgetTester tester, {
  required List<EraAffinityStat> eras,
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
              child: EraAffinityCard(eras: eras),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('пустой стейт: отображается сообщение и хинт', (tester) async {
    await pumpEraAffinityCard(tester, eras: []);

    expect(find.byIcon(LucideIcons.crown), findsOneWidget);
    expect(find.text('Золотая эпоха'), findsOneWidget);
    expect(
      find.text(
        'Десятилетия ваших любимых произведений (оценка 8+ или завершенные)',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Недостаточно данных — добавьте и оцените тайтлы, чтобы профиль вкуса раскрылся.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('список эпох: отображаются лейблы, бары и проценты',
      (tester) async {
    const eras = [
      EraAffinityStat(era: '2020s', count: 12, percentage: 40.0),
      EraAffinityStat(era: '2010s', count: 9, percentage: 30.0),
      EraAffinityStat(era: '2000s', count: 6, percentage: 20.0),
      EraAffinityStat(era: '1990s', count: 3, percentage: 10.0),
    ];

    await pumpEraAffinityCard(tester, eras: eras);

    expect(find.text('2020-е'), findsOneWidget);
    expect(find.text('2010-е'), findsOneWidget);
    expect(find.text('2000-е'), findsOneWidget);
    expect(find.text('1990-е'), findsOneWidget);

    expect(find.text('12 · 40%'), findsOneWidget);
    expect(find.text('9 · 30%'), findsOneWidget);
    expect(find.text('6 · 20%'), findsOneWidget);
    expect(find.text('3 · 10%'), findsOneWidget);
  });

  testWidgets('неизвестная эпоха отображается как есть', (tester) async {
    const eras = [
      EraAffinityStat(era: 'custom_era', count: 2, percentage: 100.0),
    ];

    await pumpEraAffinityCard(tester, eras: eras);

    expect(find.text('custom_era'), findsOneWidget);
    expect(find.text('2 · 100%'), findsOneWidget);
  });

  testWidgets('английская локаль', (tester) async {
    const eras = [
      EraAffinityStat(era: 'pre-1980', count: 4, percentage: 50.0),
      EraAffinityStat(era: '1980s', count: 4, percentage: 50.0),
    ];

    await pumpEraAffinityCard(
      tester,
      eras: eras,
      locale: Locale.en,
    );

    expect(find.text('Golden era'), findsOneWidget);
    expect(find.text('Before 1980'), findsOneWidget);
    expect(find.text('1980s'), findsOneWidget);
  });
}
