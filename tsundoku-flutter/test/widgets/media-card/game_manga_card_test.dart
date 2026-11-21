import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';
import 'package:tsundoku_flutter/widgets/media-card/game_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/manga_card.dart';

/// Widget-тесты `GameCard.svelte` и `MangaCard.svelte`: подзаголовки
/// (платформа/автор/формат), текст степпера (часы/главы).
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Center(
          child: SizedBox(width: 300, height: 450, child: child),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('GameCard: userPlatform приоритетен над platform',
      (tester) async {
    await pump(
      tester,
      GameCard(props: MediaCardProps(item: gameItem({
        'userPlatform': ' Steam ',
        'platform': 'PC',
      }))),
    );
    expect(find.text('Steam'), findsOneWidget);
    expect(find.text('PC'), findsNothing);
  });

  testWidgets('GameCard: platform-фолбэк и types.game', (tester) async {
    await pump(tester, GameCard(props: MediaCardProps(item: gameItem({
      'platform': ' Switch ',
    }))));
    expect(find.text('Switch'), findsOneWidget);
    await pump(tester, GameCard(props: MediaCardProps(item: gameItem({}))));
    expect(find.text('Игра'), findsOneWidget);
  });

  testWidgets('MangaCard: автор → формат → types.manga', (tester) async {
    await pump(tester, MangaCard(props: MediaCardProps(item: mangaItem({
      'author': 'Ода',
      'mangaFormat': 'manhwa',
    }))));
    expect(find.text('Ода'), findsOneWidget);
    await pump(tester, MangaCard(props: MediaCardProps(item: mangaItem({
      'mangaFormat': 'manhwa',
    }))));
    expect(find.text('manhwa'), findsOneWidget);
    await pump(tester, MangaCard(props: MediaCardProps(item: mangaItem({}))));
    expect(find.text('Манга'), findsOneWidget);
  });

  testWidgets('MangaCard: главы с total, 0 → прочерк', (tester) async {
    await pump(
      tester,
      MangaCard(props: MediaCardProps(item: mangaItem({
        'currentChapter': 5,
        'totalChapters': 100,
      }))),
    );
    // Hover-слой скрыт (opacity 0), но текст в дереве.
    expect(find.text('5 / 100 гл.'), findsOneWidget);
    // Замена item в реальной сетке — keyed-виджет (Svelte keyed each):
    // новый ключ → новый контроллер.
    await pump(tester, MangaCard(
      key: const Key('manga-2'),
      props: MediaCardProps(item: mangaItem({
        'currentChapter': 7,
        'totalChapters': 0,
      })),
    ));
    expect(find.text('7 / — гл.'), findsOneWidget);
  });
}

MediaItem gameItem(Map<String, Object?> extra) => mediaItem('game', extra);
MediaItem mangaItem(Map<String, Object?> extra) => mediaItem('manga', extra);

MediaItem mediaItem(String type, Map<String, Object?> extra) =>
    MediaItem.fromJson({
      'id': 'm1',
      'type': type,
      'title': 'Тестовый тайтл',
      'status': 1,
      'createdAt': '2024-01-01T00:00:00Z',
      ...extra,
    });
