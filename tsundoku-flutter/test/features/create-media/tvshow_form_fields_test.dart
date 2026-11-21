import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/tvshow_form_fields.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  testWidgets('TvShowFormFields: студия/сеть + чекбокс + сезоны',
      (tester) async {
    bool? anime;
    bool isAnime = false;
    var seasons = const [
      SeasonDraft(seasonNumber: '1', title: 'S1', totalEpisodes: '12'),
    ];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: StatefulBuilder(builder: (context, setOuter) {
                return TvShowFormFields(
                  studio: 'Studio',
                  network: '',
                  isAnime: isAnime,
                  seasons: seasons,
                  onStudioChange: (_) {},
                  onNetworkChange: (_) {},
                  onIsAnimeChange: (v) {
                    anime = v;
                    isAnime = v;
                    setOuter(() {});
                  },
                  onSeasonsChange: (v) {
                    seasons = v;
                    setOuter(() {});
                  },
                );
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Студия'), findsWidgets);
    expect(find.text('Сеть'), findsWidgets);
    expect(find.text('Это аниме?'), findsOneWidget);
    expect(find.text('Сезоны'), findsOneWidget);
    expect(find.text('Добавить сезон'), findsOneWidget);
    // Строка сезона: title подставлен.
    expect(find.text('S1'), findsOneWidget);

    await tester.tap(find.text('Это аниме?'));
    await tester.pump();
    expect(anime, isTrue);

    // Добавление сезона: seasonNumber = length+1.
    await tester.tap(find.text('Добавить сезон'));
    await tester.pump();
    expect(seasons, hasLength(2));
    expect(seasons[1].seasonNumber, '2');
    expect(seasons[1].title, '');

    // Удаление первого сезона (кнопка Minus в первой строке).
    await tester.tap(find.byIcon(LucideIcons.minus).first);
    await tester.pump();
    expect(seasons, hasLength(1));
    expect(seasons[0].seasonNumber, '2');
  });
}
