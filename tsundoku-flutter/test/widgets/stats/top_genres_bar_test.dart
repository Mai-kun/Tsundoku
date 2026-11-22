import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/top_genres_bar.dart';

List<GenreCount> _makeGenres(int count, {String prefix = 'genre'}) {
  return List.generate(
    count,
    (i) => GenreCount(
      genre: '$prefix$i',
      count: (count - i) * 10,
      percentage: (100 / count),
    ),
  );
}

Future<void> pumpTopGenresBar(
  WidgetTester tester, {
  List<GenreItem> genres = const [],
  Map<String, List<GenreItem>> genresByType = const {},
  double width = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: TopGenresBar(
                genres: genres,
                genresByType: genresByType,
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
  testWidgets('шапка: иконка, тайтл, 7 кнопок категорий', (tester) async {
    await pumpTopGenresBar(tester);

    expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
    expect(find.text('Любимые жанры'), findsOneWidget);

    expect(find.text('Все'), findsOneWidget);
    expect(find.text('Игры'), findsOneWidget);
    expect(find.text('Фильмы'), findsOneWidget);
    expect(find.text('Сериалы'), findsOneWidget);
    expect(find.text('Аниме'), findsOneWidget);
    expect(find.text('Манга'), findsOneWidget);
    expect(find.text('Книги'), findsOneWidget);
  });

  testWidgets('дефолт "all": рендер списка жанров и прогресс-бара',
      (tester) async {
    final genres = [
      const GenreCount(genre: 'action', count: 50, percentage: 50.0),
      const GenreCount(genre: 'comedy', count: 30, percentage: 30.0),
      const GenreCount(genre: 'drama', count: 20, percentage: 20.0),
    ];
    await pumpTopGenresBar(tester, genres: genres);

    // Локализованные лейблы: action -> Боевик, comedy -> Комедия, drama -> Драма
    expect(find.text('Боевик'), findsOneWidget);
    expect(find.text('Комедия'), findsOneWidget);
    expect(find.text('Драма'), findsOneWidget);

    // Счётчики и проценты
    expect(find.text('50'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);

    // Тултипы прогресс-бара
    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .toList();
    expect(tooltips.any((m) => m.contains('Боевик: 50%')), isTrue);
    expect(tooltips.any((m) => m.contains('Комедия: 30%')), isTrue);
    expect(tooltips.any((m) => m.contains('Драма: 20%')), isTrue);
  });

  testWidgets('переключение категории обновляет отображаемые жанры',
      (tester) async {
    final allGenres = [
      const GenreCount(genre: 'action', count: 50, percentage: 50.0),
    ];
    final gameGenres = [
      const GenreCount(genre: 'rpg', count: 40, percentage: 100.0),
    ];
    await pumpTopGenresBar(
      tester,
      genres: allGenres,
      genresByType: {'game': gameGenres},
    );

    expect(find.text('Боевик'), findsOneWidget);
    expect(find.text('RPG'), findsNothing);

    // Тап по кнопке 'Игры'
    await tester.tap(find.text('Игры'));
    await tester.pump();

    expect(find.text('Боевик'), findsNothing);
    expect(find.text('RPG'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('пустая категория: отображается empty state', (tester) async {
    await pumpTopGenresBar(tester, genres: []);

    expect(find.text('Нет данных о жанрах в этой категории'), findsOneWidget);
  });

  testWidgets('ограничение до 8 жанров (slice 0..8)', (tester) async {
    final tenGenres = _makeGenres(10);
    await pumpTopGenresBar(tester, genres: tenGenres);

    // Первые 8 есть (genre0 .. genre7)
    for (int i = 0; i < 8; i++) {
      expect(find.text('genre$i'), findsOneWidget);
    }
    // 9-й и 10-й (genre8, genre9) отсечены
    expect(find.text('genre8'), findsNothing);
    expect(find.text('genre9'), findsNothing);
  });
}
