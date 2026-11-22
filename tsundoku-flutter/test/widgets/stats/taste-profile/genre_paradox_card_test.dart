import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_paradox_card.dart';

Future<void> pumpGenreParadoxCard(
  WidgetTester tester, {
  required List<GenreCompletionStat> paradox,
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
              child: GenreParadoxCard(paradox: paradox),
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
  testWidgets('пустой стейт: отображается сообщение и шапка', (tester) async {
    await pumpGenreParadoxCard(tester, paradox: []);

    expect(find.byIcon(LucideIcons.scale), findsOneWidget);
    expect(find.text('Парадокс жанров'), findsOneWidget);
    expect(find.text('Завершение'), findsOneWidget);
    expect(find.text('Дроп'), findsOneWidget);
    expect(
      find.text(
        'Недостаточно данных — добавьте и оцените тайтлы, чтобы профиль вкуса раскрылся.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('список жанров: отображаются лейблы и проценты',
      (tester) async {
    const stats = [
      GenreCompletionStat(
        genre: 'action',
        total: 10,
        completed: 8,
        dropped: 1,
        completionRate: 80.0,
        dropRate: 10.0,
      ),
      GenreCompletionStat(
        genre: 'comedy',
        total: 12,
        completed: 6,
        dropped: 5,
        completionRate: 50.0,
        dropRate: 41.7,
      ),
    ];

    await pumpGenreParadoxCard(tester, paradox: stats);

    expect(find.text('Боевик'), findsOneWidget);
    expect(find.text('Комедия'), findsOneWidget);

    expect(find.text('80%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('41.7%'), findsOneWidget);
  });

  testWidgets('неизвестный жанр отображается как есть', (tester) async {
    const stats = [
      GenreCompletionStat(
        genre: 'weird_genre',
        total: 5,
        completed: 4,
        dropped: 1,
        completionRate: 80.0,
        dropRate: 20.0,
      ),
    ];

    await pumpGenreParadoxCard(tester, paradox: stats);

    expect(find.text('weird_genre'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
  });

  testWidgets('английская локаль', (tester) async {
    const stats = [
      GenreCompletionStat(
        genre: 'action',
        total: 10,
        completed: 9,
        dropped: 1,
        completionRate: 90.0,
        dropRate: 10.0,
      ),
    ];

    await pumpGenreParadoxCard(
      tester,
      paradox: stats,
      locale: Locale.en,
    );

    expect(find.text('Genre paradox'), findsOneWidget);
    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('Dropped'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
  });
}
