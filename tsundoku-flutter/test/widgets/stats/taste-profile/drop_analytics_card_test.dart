import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/drop_analytics_card.dart';

Future<void> pumpDropAnalyticsCard(
  WidgetTester tester, {
  required DropAnalytics analytics,
  Locale locale = Locale.ru,
  double width = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        i18nProvider.overrideWith(() => _FixedLocaleController(locale)),
        tProvider.overrideWithValue(I18nDictionary(locale)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: DropAnalyticsCard(analytics: analytics),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _FixedLocaleController extends I18nController {
  final Locale fixed;
  _FixedLocaleController(this.fixed);

  @override
  Locale build() => fixed;
}

void main() {
  testWidgets('пустой стейт: totalDropped == 0', (tester) async {
    const analytics = DropAnalytics(
      totalDropped: 0,
      averageDropProgressPercent: 0,
      earlyDropCount: 0,
      midDropCount: 0,
      lateDropCount: 0,
      topReasons: [],
    );

    await pumpDropAnalyticsCard(tester, analytics: analytics);

    expect(find.byIcon(LucideIcons.ban), findsOneWidget);
    expect(find.text('Анатомия дропа'), findsOneWidget);
    expect(find.text('Всего брошено: 0'), findsOneWidget);
    expect(
      find.text(
        'Нет брошенных тайтлов — все начатое доведено до конца или отложено.',
      ),
      findsOneWidget,
    );
    expect(find.text('Точка невозврата'), findsNothing);
  });

  testWidgets('ранний дроп: отображаются графики, причины и цитата',
      (tester) async {
    const analytics = DropAnalytics(
      totalDropped: 10,
      averageDropProgressPercent: 15,
      earlyDropCount: 7,
      midDropCount: 2,
      lateDropCount: 1,
      topReasons: [
        DropReasonStat(
          reason: 'boredom',
          count: 5,
          percentage: 50.0,
        ),
        DropReasonStat(
          reason: 'bad_pacing',
          count: 3,
          percentage: 30.0,
        ),
      ],
    );

    await pumpDropAnalyticsCard(tester, analytics: analytics);

    expect(find.text('Анатомия дропа'), findsOneWidget);
    expect(find.text('Всего брошено: 10'), findsOneWidget);
    expect(find.text('ТОЧКА НЕВОЗВРАТА'), findsOneWidget);
    expect(find.text('avg 15%'), findsOneWidget);
    expect(
      find.text('В среднем вы бросаете произведения на 15% пути'),
      findsOneWidget,
    );

    // Легенда
    expect(find.text('Ранний дроп (<20%)'), findsOneWidget);
    expect(find.text('В середине (20–70%)'), findsOneWidget);
    expect(find.text('В шаге от финала (>70%)'), findsOneWidget);

    // Причины
    expect(find.text('ТОП ПРИЧИН ДРОПА'), findsOneWidget);
    expect(find.text('5 '), findsOneWidget);
    expect(find.text('(50%)'), findsOneWidget);

    // Инсайт раннего дропа
    expect(
      find.textContaining('Вы не боитесь бросать скучное в самом начале'),
      findsOneWidget,
    );
  });

  testWidgets('поздний дроп: инсайт позднего дропа', (tester) async {
    const analytics = DropAnalytics(
      totalDropped: 10,
      averageDropProgressPercent: 75,
      earlyDropCount: 1,
      midDropCount: 3,
      lateDropCount: 6,
      topReasons: [],
    );

    await pumpDropAnalyticsCard(tester, analytics: analytics);

    expect(
      find.textContaining('Вы даете произведениям шанс раскрыться до самого конца'),
      findsOneWidget,
    );
  });

  testWidgets('сбалансированный дроп: общий инсайт', (tester) async {
    const analytics = DropAnalytics(
      totalDropped: 10,
      averageDropProgressPercent: 45,
      earlyDropCount: 3,
      midDropCount: 4,
      lateDropCount: 3,
      topReasons: [],
    );

    await pumpDropAnalyticsCard(tester, analytics: analytics);

    expect(
      find.textContaining('Вы тонко чувствуете момент'),
      findsOneWidget,
    );
  });

  testWidgets('английская локаль', (tester) async {
    const analytics = DropAnalytics(
      totalDropped: 5,
      averageDropProgressPercent: 12,
      earlyDropCount: 4,
      midDropCount: 1,
      lateDropCount: 0,
      topReasons: [],
    );

    await pumpDropAnalyticsCard(
      tester,
      analytics: analytics,
      locale: Locale.en,
    );

    expect(find.text('Drop Analysis'), findsOneWidget);
    expect(find.text('Total dropped: 5'), findsOneWidget);
    expect(find.text('POINT OF NO RETURN'), findsOneWidget);
    expect(
      find.text('On average, you drop titles at 12% of progress'),
      findsOneWidget,
    );
    expect(
      find.textContaining("You aren't afraid to drop boring titles early"),
      findsOneWidget,
    );
  });
}
