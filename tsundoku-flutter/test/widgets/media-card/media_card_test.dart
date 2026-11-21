import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-card/book_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';
import 'package:tsundoku_flutter/widgets/media-card/game_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/media_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/manga_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/movie_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/tv_show_card.dart';

/// Widget-тесты `MediaCard.svelte`: диспетчеризация по item.type.
void main() {
  MediaItem item(String type) => MediaItem.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'Тестовый тайтл',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
      });

  Future<Widget> buildCard(String type) =>
      Future.value(MediaCard(props: MediaCardProps(item: item(type))));

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(),
      child: MaterialApp(
        home: Center(
          child: SizedBox(width: 300, height: 450, child: child),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('game → GameCard', (tester) async {
    await pump(tester, await buildCard('game'));
    expect(find.byType(GameCard), findsOneWidget);
  });

  testWidgets('book → BookCard', (tester) async {
    await pump(tester, await buildCard('book'));
    expect(find.byType(BookCard), findsOneWidget);
  });

  testWidgets('manga → MangaCard', (tester) async {
    await pump(tester, await buildCard('manga'));
    expect(find.byType(MangaCard), findsOneWidget);
  });

  testWidgets('movie → MovieCard', (tester) async {
    await pump(tester, await buildCard('movie'));
    expect(find.byType(MovieCard), findsOneWidget);
  });

  testWidgets('tvshow → TvShowCard (default-ветка)', (tester) async {
    await pump(tester, await buildCard('tvshow'));
    expect(find.byType(TvShowCard), findsOneWidget);
  });
}
