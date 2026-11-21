import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/season_row.dart';

/// Тесты полного цикла `SeasonRow.svelte`: optimistic шаг → debounce 3s →
/// send → commit; ошибка → откат; кламп по totalEpisodes; смена сезона.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  TvSeason season(Map<String, Object?> extra) => TvSeason.fromJson({
        'id': 's1',
        'seasonNumber': 1,
        'title': 'Season 1',
        'status': 1,
        'currentEpisode': 3,
        'totalEpisodes': 10,
        'tvShowId': 'tv1',
        ...extra,
      });

  Future<void> pumpRow(
    WidgetTester tester, {
    required TvSeason tvSeason,
    required Future<void> Function(String id, int episode) onProgress,
    void Function()? onProgressCommitted,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: SeasonRow(
              season: tvSeason,
              onProgress: onProgress,
              onProgressCommitted: onProgressCommitted ?? () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('рендер: номер сезона, title, счётчик 3 / 10, бар', (tester) async {
    await pumpRow(tester, tvSeason: season({}), onProgress: (id, v) async {});

    expect(find.text('СЕЗОН 1'), findsOneWidget); // createModal.fields.season
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget); // счётчик степпера
  });

  testWidgets('полный цикл: +1 → optimistic 4 → debounce 3s → send(4) → '
      'committed', (tester) async {
    final sends = <(String, int)>[];
    var committedFired = 0;
    await pumpRow(
      tester,
      tvSeason: season({}),
      onProgress: (id, v) async => sends.add((id, v)),
      onProgressCommitted: () => committedFired += 1,
    );

    await tester.tap(find.bySemanticsLabel('Увеличить прогресс'));
    await tester.pump();

    // Optimistic: счётчик уже 4.
    expect(find.text('4 / 10'), findsOneWidget);
    expect(sends, isEmpty); // ещё в дебаунсе

    await tester.pump(const Duration(seconds: 3));
    expect(sends.length, 1);
    expect(sends.first.$1, 's1');
    expect(sends.first.$2, 4);
    expect(committedFired, 1);
  });

  testWidgets('burst +1 +1 +1 → один send с финальным значением',
      (tester) async {
    final sends = <int>[];
    await pumpRow(
      tester,
      tvSeason: season({}),
      onProgress: (id, v) async => sends.add(v),
    );

    await tester.tap(find.bySemanticsLabel('Увеличить прогресс'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Увеличить прогресс'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Увеличить прогресс'));
    await tester.pump();
    expect(find.text('6 / 10'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(sends, [6]); // burst → один send
  });

  testWidgets('ошибка send → откат к committed + rose-текст', (tester) async {
    Object? seen;
    await pumpRow(
      tester,
      tvSeason: season({}),
      onProgress: (id, v) async {
        seen = id;
        throw StateError('boom');
      },
    );

    await tester.tap(find.bySemanticsLabel('Увеличить прогресс'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // Откат к committedEpisode = 3.
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('Произошла непредвиденная ошибка.'), findsOneWidget);
    expect(seen, 's1');
  });

  testWidgets('кламп: + за границей totalEpisodes не уходит', (tester) async {
    final sends = <int>[];
    await pumpRow(
      tester,
      tvSeason: season({'currentEpisode': 10}),
      onProgress: (id, v) async => sends.add(v),
    );

    await tester.tap(find.bySemanticsLabel('Увеличить прогресс'));
    await tester.pump();
    expect(find.text('10 / 10'), findsOneWidget); // кламп

    await tester.pump(const Duration(seconds: 3));
    expect(sends, isEmpty); // next == current → schedule не вызван
  });

  testWidgets('смена сезона: счётчик сбрасывается на новый season',
      (tester) async {
    TvSeason current = season({});
    late StateSetter setter;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: StatefulBuilder(builder: (context, setState) {
            setter = setState;
            return SeasonRow(
              season: current,
              onProgress: (id, v) async {},
              onProgressCommitted: () {},
            );
          }),
        ),
      ),
    ));
    await tester.pump();

    setter(() => current = season({'id': 's2', 'currentEpisode': 7}));
    await tester.pump();
    await tester.pump();

    expect(find.text('7 / 10'), findsOneWidget);
    expect(find.text('СЕЗОН 1'), findsOneWidget);
  });
}
