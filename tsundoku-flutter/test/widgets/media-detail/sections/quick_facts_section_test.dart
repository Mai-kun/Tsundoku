import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/quick_facts_section.dart';

/// Тесты `QuickFactsSection.svelte`: чипы тип/язык/страна/статус/объём,
/// ru-плюрализация, флаги.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media(String type, Map<String, Object?> extra) =>
      MediaDetail.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'X',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  Future<void> pumpFacts(
    WidgetTester tester, {
    required MediaDetail media,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(child: QuickFactsSection(media: media)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('аниме (tvshow+isAnime): тип «Аниме», язык 🇯🇵 Japanese',
      (tester) async {
    await pumpFacts(
      tester,
      // durationMinutes не задаём: цепочка measure в Svelte сначала
      // возвращает «мин. / эп.», и счётчик серий не отрисовался бы.
      media: media('tvshow', {
        'isAnime': true,
        'originalLanguage': 'ja',
        'totalEpisodesCount': 13,
      }),
    );

    expect(find.textContaining(RegExp('Быстрые факты', caseSensitive: false)), findsOneWidget);
    expect(find.text('Аниме'), findsOneWidget);
    expect(find.textContaining('Japanese'), findsOneWidget);
    // Серий: ru-плюрализация 13 → «серий».
    expect(find.text('13 серий'), findsOneWidget);
  });

  testWidgets('ru-плюрализация: 3 серии (few), 1 страница (singular)',
      (tester) async {
    await pumpFacts(
      tester,
      media: media('tvshow', {'totalEpisodesCount': 3}),
    );
    expect(find.text('3 серии'), findsOneWidget);

    await pumpFacts(
      tester,
      media: media('book', {'totalPages': 1}),
    );
    expect(find.text('1 страница'), findsOneWidget);
  });

  testWidgets('манга: тома · главы', (tester) async {
    await pumpFacts(
      tester,
      media: media('manga', {'totalVolumes': 4, 'totalChapters': 120}),
    );
    expect(find.text('Манга'), findsOneWidget);
    expect(find.text('4 тома · 120 глав'), findsOneWidget);
  });

  testWidgets('статус releaseStatus → Онгоинг/Завершён/Анонс',
      (tester) async {
    await pumpFacts(
      tester,
      media: media('movie', {'releaseStatus': 'RELEASING'}),
    );
    expect(find.text('Онгоинг'), findsOneWidget);

    await pumpFacts(
      tester,
      media: media('movie', {'releaseStatus': 'RELEASED'}),
    );
    expect(find.text('Завершён'), findsOneWidget);

    await pumpFacts(
      tester,
      media: media('movie', {'releaseStatus': 'UPCOMING'}),
    );
    expect(find.text('Анонс'), findsOneWidget);
  });

  testWidgets('страна: флаг по codePoint + название', (tester) async {
    await pumpFacts(
      tester,
      media: media('game', {'countryOfOrigin': 'JP'}),
    );
    expect(find.textContaining('Япония'), findsOneWidget);
  });
}
