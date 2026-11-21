import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_progress_controls.dart';
import 'package:tsundoku_flutter/widgets/media-card/movie_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/tv_show_card.dart';

/// Widget-тесты `MovieCard.svelte` (0/1 toggle) и `TvShowCard.svelte`
/// (оптимистичный счётчик серий / hover-бейдж без onEpisodeStep).
class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  late ProviderContainer container;
  late StubAdapter adapter;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) => jsonBody(<String, Object?>{}));
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester, Widget child,
      {bool hover = false, Finder? hoverTarget}) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Center(
          child: SizedBox(width: 300, height: 450, child: child),
        ),
      ),
    ));
    await tester.pump();
    if (hover) {
      final target = hoverTarget ?? find.byType(child.runtimeType);
      final center = tester.getCenter(target.first);
      final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse, pointer: 7);
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();
    }
  }

  MediaItem mediaItem(String type, Map<String, Object?> extra) =>
      MediaItem.fromJson({
        'id': 'm1',
        'type': type,
        'title': 'Тестовый тайтл',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  group('MovieCard', () {
    testWidgets('подзаголовок: режиссёр → types.movie', (tester) async {
      await pump(tester, MovieCard(props: MediaCardProps(
        item: mediaItem('movie', {'director': 'Villeneuve'}),
      )));
      expect(find.text('Villeneuve'), findsOneWidget);
      await pump(tester, MovieCard(props: MediaCardProps(
        item: mediaItem('movie', {}),
      )));
      expect(find.text('Фильм'), findsOneWidget);
    });

    testWidgets('0/1 ↔ 1/1: toggle через createCardStatus (onStatusChange)',
        (tester) async {
      final statuses = <MediaStatus>[];
      MediaItem item =
          mediaItem('movie', {'status': 0}); // planned → 0 / 1
      await pump(tester, StatefulBuilder(builder: (context, setState) {
        return MovieCard(props: MediaCardProps(
          item: item,
          showProgress: true,
          onStatusChange: (updated, next) {
            setState(() => item = updated.copyWithFields(status: next));
            statuses.add(next);
          },
        ));
      }));

      // Hover активирует hover-слой (IgnorePointer без него).
      final center = tester.getCenter(find.byType(MovieCard).first);
      final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse, pointer: 7);
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();

      // Плюс: 0/1 → 1/1 = changeStatus(completed).
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      expect(statuses, [MediaStatus.completed]);

      // При watched минус активен (decrementDisabled={!watched}):
      // 1/1 → 0/1 = changeStatus(planned).
      await tester.tap(find.byIcon(LucideIcons.minus));
      await tester.pumpAndSettle();
      expect(statuses, [MediaStatus.completed, MediaStatus.planned]);
    });

    testWidgets('«1 / 1» при completed', (tester) async {
      await pump(tester, MovieCard(props: MediaCardProps(
        item: mediaItem('movie', {'status': 2}),
      )));
      expect(find.text('1 / 1'), findsOneWidget);
    });
  });

  group('TvShowCard', () {
    testWidgets('подзаголовок: cardTypeLabel + seasonsCount', (tester) async {
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {'seasonsCount': 4}),
      )));
      expect(find.text('Сериал • 4'), findsOneWidget);
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {}),
      )));
      expect(find.text('Сериал'), findsOneWidget);
    });

    testWidgets('текст эпизодов: «N / total» и голый N без total',
        (tester) async {
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {
          'totalEpisodesWatched': 5,
          'totalEpisodesCount': 12,
        }),
        onEpisodeStep: (item, watched) async {},
      )));
      expect(find.text('5 / 12'), findsOneWidget);
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {'totalEpisodesWatched': 5}),
        onEpisodeStep: (item, watched) async {},
      )));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('шаг: локальный счётчик мгновенно + onEpisodeStep с абсолютом',
        (tester) async {
      final steps = <int>[];
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {
          'totalEpisodesWatched': 5,
          'totalEpisodesCount': 12,
        }),
        onEpisodeStep: (item, watched) async => steps.add(watched),
      )));

      final center = tester.getCenter(find.byType(TvShowCard).first);
      final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse, pointer: 7);
      await gesture.addPointer(location: center);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(center);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
      expect(steps, [6]);
      expect(find.text('6 / 12'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.minus));
      await tester.pumpAndSettle();
      expect(steps, [6, 5]);
      expect(find.text('5 / 12'), findsOneWidget);

      // Дебаунс серии (3s) — не оставить pending timer.
      await tester.pump(const Duration(seconds: 3, milliseconds: 200));
      await tester.pumpAndSettle();
    });

    testWidgets('без onEpisodeStep → hover-слой с MediaStatusBadge',
        (tester) async {
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {'totalEpisodesWatched': 3}),
      )));
      // Бейдж статуса в hover-слое (inProgress → Play) + бейдж в постере.
      expect(find.byIcon(LucideIcons.play), findsNWidgets(2));
      // Степперных кнопок нет.
      expect(find.byIcon(LucideIcons.plus), findsNothing);
    });

    testWidgets('atLastEpisode: + задизейблен на последней серии',
        (tester) async {
      await pump(tester, TvShowCard(props: MediaCardProps(
        item: mediaItem('tvshow', {
          'totalEpisodesWatched': 12,
          'totalEpisodesCount': 12,
        }),
        onEpisodeStep: (item, watched) async {},
      )));
      expect(find.text('12 / 12'), findsOneWidget);
      final controls = tester.widget<CardProgressControls>(
          find.byType(CardProgressControls));
      expect(controls.incrementDisabled, isTrue);
      expect(controls.decrementDisabled, isFalse);
    });
  });
}
