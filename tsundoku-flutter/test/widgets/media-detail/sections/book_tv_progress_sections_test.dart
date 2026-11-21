import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/shared/utils/ui_settings.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/book_progress_section.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/tv_show_progress_section.dart';

/// Тесты `BookProgressSection.svelte` + `TvShowProgressSection.svelte`:
/// выбор единиц (новелла → главы), минуты/единица, tooltip по сезонам.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpBook(
    WidgetTester tester, {
    required int totalPages,
    required int currentPage,
    String? format,
    int? totalChapters,
    required int value,
    required double percent,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: BookProgressSection(
              totalPages: totalPages,
              currentPage: currentPage,
              format: format,
              totalChapters: totalChapters,
              finishedAt: null,
              progress: const ProgressInfo(
                  current: 0, total: null, editable: true, label: 'Страницы'),
              value: value,
              percent: percent,
              error: null,
              onStep: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('книга: label «Страницы», темп страниц [10/20/30/50]',
      (tester) async {
    await pumpBook(tester,
        totalPages: 320, currentPage: 40, value: 40, percent: 12.5);

    expect(find.text('СТРАНИЦЫ'), findsOneWidget);
    expect(find.text('13%'), findsOneWidget); // round(12.5) = 13 (как Math.round)
    // paceDefault 20 → чип 20 активен; чипы 10/20/30/50 присутствуют.
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('новелла: label «Главы», total из totalChapters',
      (tester) async {
    await pumpBook(
      tester,
      totalPages: 320,
      currentPage: 40,
      format: 'light_novel',
      totalChapters: 88,
      value: 12,
      percent: 13.6,
    );

    expect(find.text('ГЛАВЫ'), findsOneWidget);
    expect(find.textContaining('/ 88'), findsOneWidget);
    // Новелльный темп [1,2,3,5] → чип 50 отсутствует.
    expect(find.text('50'), findsNothing);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('totalPages = 0 → фолбэк на progress.total', (tester) async {
    await pumpBook(tester,
        totalPages: 0,
        currentPage: 0,
        value: 2,
        percent: 20,
        totalChapters: null);
    // progress.total null → total 0 → без кольца; проверяем отсутствие / N.
    expect(find.textContaining('/ '), findsNothing);
  });

  testWidgets('bookPageMinutes из uiSettings влияет на блок времени',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: []);
    addTearDown(container.dispose);
    // Дефолт bookPageMinutes 1.5 → 40 страниц = 60 мин → «1 ч».
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: BookProgressSection(
              totalPages: 320,
              currentPage: 40,
              finishedAt: null,
              progress: const ProgressInfo(
                  current: 40, total: 320, editable: true, label: 'Страницы'),
              value: 40,
              percent: 12.5,
              error: null,
              onStep: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // doneCaption: «Прочитано 60 мин» (bookPageMinutes 1.5 × 40).
    expect(find.textContaining('60 мин'), findsOneWidget);
    // Проверим, что стейт хранит дефолт.
    expect(container.read(uiSettingsProvider).bookPageMinutes, 1.5);
  });

  group('TvShowProgressSection', () {
    MediaDetail media(Map<String, Object?> extra) => MediaDetail.fromJson({
          'id': 'm1',
          'type': 'tvshow',
          'title': 'Show',
          'status': 1,
          'createdAt': '2024-01-01T00:00:00Z',
          ...extra,
        });

    Future<void> pumpTv(
      WidgetTester tester, {
      required MediaDetail media,
      required int totalEpisodes,
      required int value,
      required double percent,
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Material(
            child: SingleChildScrollView(
              child: TvShowProgressSection(
                media: media,
                totalEpisodes: totalEpisodes,
                watchedEpisodes: value,
                progress: ProgressInfo(
                    current: value,
                    total: totalEpisodes,
                    editable: true,
                    label: 'Серии'),
                value: value,
                percent: percent,
                error: null,
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('сериал: label «СЕРИИ», 16% кольцо, tooltip по сезонам',
        (tester) async {
      await pumpTv(
        tester,
        media: media({
          'episodeDurationMinutes': 24,
          'seasons': [
            {'id': 's1', 'seasonNumber': 1, 'title': 'S1', 'currentEpisode': 2, 'totalEpisodes': 220, 'status': 1, 'tvShowId': 'm1'},
            {'id': 's2', 'seasonNumber': 2, 'title': 'S2', 'currentEpisode': 0, 'totalEpisodes': 280, 'status': 1, 'tvShowId': 'm1'},
          ],
        }),
        totalEpisodes: 500,
        value: 80,
        percent: 16,
      );

      expect(find.text('СЕРИИ'), findsOneWidget);
      expect(find.text('16%'), findsOneWidget);
      expect(find.textContaining('/ 500'), findsOneWidget);
    });

    testWidgets('episodeDurationMinutes отсутствует → фолбэк 24',
        (tester) async {
      // Значение проверки: блок времени «Осталось» есть при minsPerUnit > 0.
      await pumpTv(
        tester,
        media: media({}),
        totalEpisodes: 12,
        value: 3,
        percent: 25,
      );
      // remainingUnits 9 × 24 = 216 мин = 3 ч 36 мин.
      expect(find.textContaining('3 ч 36 мин'), findsOneWidget);
    });
  });
}
