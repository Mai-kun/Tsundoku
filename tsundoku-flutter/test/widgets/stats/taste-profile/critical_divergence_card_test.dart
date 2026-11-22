import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/critical_divergence_card.dart';

Future<void> pumpCriticalDivergenceCard(
  WidgetTester tester, {
  required CriticalDivergence divergence,
  ValueChanged<String>? onOpenMedia,
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
              child: CriticalDivergenceCard(
                divergence: divergence,
                onOpenMedia: onOpenMedia,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const gem = DivergenceItem(
    id: 'media-gem-1',
    title: 'Steins;Gate',
    type: 'anime',
    coverUrl: null,
    userScore: 9.5,
    worldRating: 7.0,
    delta: 2.5,
  );

  const letdown = DivergenceItem(
    id: 'media-letdown-1',
    title: 'Overhyped Show',
    type: 'series',
    coverUrl: null,
    userScore: 5.0,
    worldRating: 8.5,
    delta: -3.5,
  );

  testWidgets('пустой стейт: отображается сообщение и заголовок',
      (tester) async {
    const emptyDivergence = CriticalDivergence(
      hiddenGem: null,
      disappointment: null,
    );

    await pumpCriticalDivergenceCard(tester, divergence: emptyDivergence);

    expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
    expect(find.text('Я против всего мира'), findsOneWidget);
    expect(
      find.text('Пока нет тайтлов с оценкой и внешним рейтингом.'),
      findsOneWidget,
    );
    expect(find.text('Разрыв'), findsNothing);
  });

  testWidgets('рендеринг обеих карточек: шедевр и разочарование',
      (tester) async {
    const divergence = CriticalDivergence(
      hiddenGem: gem,
      disappointment: letdown,
    );

    await pumpCriticalDivergenceCard(tester, divergence: divergence);

    expect(find.text('Я против всего мира'), findsOneWidget);
    expect(find.text('Steins;Gate'), findsOneWidget);
    expect(find.text('Overhyped Show'), findsOneWidget);

    // Заголовки блоков
    expect(find.textContaining('МОЙ ТАЙНЫЙ ШЕДЕВР'), findsOneWidget);
    expect(find.textContaining('ГЛАВНОЕ РАЗОЧАРОВАНИЕ'), findsOneWidget);

    // Дельты
    expect(find.text('+2.5'), findsOneWidget);
    expect(find.text('-3.5'), findsOneWidget);

    // Футер-сноска
    expect(
      find.text('Ваша оценка · Мировая оценка'),
      findsOneWidget,
    );
  });

  testWidgets('клик по карточке вызывает onOpenMedia', (tester) async {
    String? openedId;
    const divergence = CriticalDivergence(
      hiddenGem: gem,
      disappointment: letdown,
    );

    await pumpCriticalDivergenceCard(
      tester,
      divergence: divergence,
      onOpenMedia: (id) => openedId = id,
    );

    await tester.tap(find.text('Steins;Gate'));
    expect(openedId, equals('media-gem-1'));

    await tester.tap(find.text('Overhyped Show'));
    expect(openedId, equals('media-letdown-1'));
  });

  testWidgets('только шедевр: карточка разочарования не рендерится',
      (tester) async {
    const divergence = CriticalDivergence(
      hiddenGem: gem,
      disappointment: null,
    );

    await pumpCriticalDivergenceCard(tester, divergence: divergence);

    expect(find.text('Steins;Gate'), findsOneWidget);
    expect(find.text('Overhyped Show'), findsNothing);
    expect(find.text('+2.5'), findsOneWidget);
  });

  testWidgets('английская локаль', (tester) async {
    const divergence = CriticalDivergence(
      hiddenGem: gem,
      disappointment: letdown,
    );

    await pumpCriticalDivergenceCard(
      tester,
      divergence: divergence,
      locale: Locale.en,
    );

    expect(find.text('Me against the world'), findsOneWidget);
    expect(find.textContaining('MY HIDDEN GEM'), findsOneWidget);
    expect(find.textContaining('THE BIG LETDOWN'), findsOneWidget);
    expect(find.text('Your score · World rating'), findsOneWidget);
  });
}
