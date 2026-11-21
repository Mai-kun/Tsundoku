import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_header.dart';

/// Тесты `DetailHeader.svelte`: заголовок/оригинал, теги, рейтинги (score
/// + голоса), синопсис clamp/раскрытие.
void main() {
  Future<void> pumpHeader(
    WidgetTester tester, {
    String title = 'Норагами',
    String? originalTitle = 'ノラガミ',
    List<String> tags = const ['Аниме', 'Приключения'],
    List<RatingBadge> ratings = const [
      RatingBadge(source: 'AniList', score: 8.6, votes: 1317),
      RatingBadge(source: 'Shikimori', score: null, votes: null),
    ],
    String? synopsis,
    bool expanded = false,
    bool expandable = true,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SingleChildScrollView(
          child: DetailHeader(
            title: title,
            originalTitle: originalTitle,
            tags: tags,
            ratings: ratings,
            synopsisText: synopsis,
            synopsisExpanded: expanded,
            synopsisExpandable: expandable,
            synopsisTranslated: false,
            translatedSynopsis: null,
            translatingSynopsis: false,
            onToggleTranslate: () {},
            onToggleExpand: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('заголовок + оригинальное название + теги', (tester) async {
    await pumpHeader(tester,
        synopsis: 'Длинное описание синопсиса. ' * 40);
    expect(find.text('Норагами'), findsOneWidget);
    expect(find.text('ノラガミ'), findsOneWidget);
    expect(find.text('Аниме'), findsOneWidget);
    expect(find.text('Приключения'), findsOneWidget);
  });

  testWidgets('без оригинального названия строки нет', (tester) async {
    await pumpHeader(tester, originalTitle: null);
    expect(find.text('ノラガミ'), findsNothing);
  });

  testWidgets('рейтинг: score 8.6 + hover-голоса 1.3k', (tester) async {
    await pumpHeader(tester);
    expect(find.text('ANILIST'), findsOneWidget);
    expect(find.text('8.6'), findsOneWidget);
    expect(find.text('SHIKIMORI'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // score null → прочерк
  });

  testWidgets('формат голосов: 1317 → 1.3k (formatVotes)', (tester) async {
    expect(formatVotes(1317), '1.3k');
    expect(formatVotes(5), '5');
    expect(formatVotes(999), '999');
  });

  testWidgets('синопсис: clamp 4 строки без expanded, кнопка Read more',
      (tester) async {
    await pumpHeader(tester,
        synopsis: 'Длинное описание синопсиса. ' * 40);
    // Кнопка разворота есть (expandable).
    expect(find.textContaining('Читать далее'), findsOneWidget);
    // Секция синопсиса с заголовком.
    expect(find.text('СИНОПСИС'), findsOneWidget);
  });

  testWidgets('короткий синопсис → без кнопки разворота', (tester) async {
    await pumpHeader(tester, synopsis: 'Короткое описание', expandable: false);
    expect(find.textContaining('Читать далее'), findsNothing);
    expect(find.text('Короткое описание'), findsOneWidget);
  });

  testWidgets('пустой синопсис → noSynopsis', (tester) async {
    await pumpHeader(tester, synopsis: null);
    expect(find.text('Описание отсутствует.'), findsOneWidget);
  });
}
