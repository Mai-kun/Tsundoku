import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/manga_progress_section.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/movie_status_section.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/notes_section.dart';

/// Тесты `MovieStatusSection.svelte` + `MangaProgressSection.svelte` +
/// `NotesSection.svelte`.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media(Map<String, Object?> extra) => MediaDetail.fromJson({
        'id': 'm1',
        'type': 'movie',
        'title': 'Movie',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  group('MovieStatusSection', () {
    Future<void> pumpMovie(
      WidgetTester tester, {
      required MediaDetail media,
      required String statusLabel,
      void Function(MediaStatus)? onChangeStatus,
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Material(
            child: SingleChildScrollView(
              child: MovieStatusSection(
                media: media,
                statusLabel: statusLabel,
                onEdit: () {},
                onChangeStatus: onChangeStatus,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('хронометраж: 136 мин + «~2 ч. 16 мин.»', (tester) async {
      await pumpMovie(
        tester,
        media: media({'durationMinutes': 136}),
        statusLabel: 'Смотрю',
      );

      expect(find.text('ХРОНОМЕТРАЖ И СТАТУС'), findsOneWidget);
      expect(find.text('136 мин.'), findsOneWidget);
      expect(find.text('(~2 ч. 16 мин.)'), findsOneWidget);
    });

    testWidgets('inProgress: пилюля статуса amber + тап planned/completed',
        (tester) async {
      final changed = <MediaStatus>[];
      await pumpMovie(
        tester,
        media: media({}),
        statusLabel: 'Смотрю',
        onChangeStatus: changed.add,
      );

      // Ни planned, ни completed → amber-пилюля со статусом.
      expect(find.text('Смотрю'), findsOneWidget);
      expect(find.text('В планах'), findsOneWidget);
      expect(find.text('Завершено'), findsOneWidget);

      await tester.tap(find.text('В планах'));
      await tester.pump();
      expect(changed, [MediaStatus.planned]);
      await tester.tap(find.text('Завершено'));
      await tester.pump();
      expect(changed, [MediaStatus.planned, MediaStatus.completed]);
    });

    testWidgets('completed: бейдж-пилюля с галочкой, watchedOn-строка',
        (tester) async {
      await pumpMovie(
        tester,
        media: media({'status': 2, 'watchedOn': 'Кинотеатр'}),
        statusLabel: '',
      );

      // amber-пилюли нет (статус из быстрых кнопок).
      expect(find.text('Смотрю'), findsNothing);
      expect(find.textContaining('Где смотрено'), findsOneWidget);
      expect(find.text('Кинотеатр'), findsOneWidget);
    });
  });

  group('MangaProgressSection', () {
    testWidgets('главы: label, /total, pace-чипы [1,2,3,5]', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final manga = MediaDetail.fromJson({
        'id': 'm1',
        'type': 'manga',
        'title': 'Manga',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'finishedAt': null,
      });
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Material(
            child: SingleChildScrollView(
              child: MangaProgressSection(
                media: manga,
                totalChapters: 120,
                currentChapter: 0,
                progress: const ProgressInfo(
                    current: 0, total: 120, editable: true, label: 'Главы'),
                value: 4,
                percent: 3.3,
                error: null,
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('ГЛАВЫ'), findsOneWidget);
      expect(find.textContaining('/ 120'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // pace чип 5
      expect(find.text('50'), findsNothing); // не книжные темпы
    });
  });

  group('NotesSection', () {
    Future<void> pumpNotes(
      WidgetTester tester, {
      required String? notes,
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Material(
            child: SingleChildScrollView(
              child: NotesSection(notes: notes, onEdit: () {}),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('с заметками: заголовок, текст, Edit-кнопка', (tester) async {
      await pumpNotes(tester, notes: 'Первая строка\nВторая строка');

      expect(find.text('Ваши заметки и мысли'), findsOneWidget);
      expect(find.text('Редактировать'), findsOneWidget);
      expect(find.text('Первая строка\nВторая строка'), findsOneWidget);
    });

    testWidgets('пусто: dashed-приглашение с плейсхолдером', (tester) async {
      await pumpNotes(tester, notes: null);

      expect(find.text('Ваши заметки и мысли'), findsOneWidget);
      expect(find.textContaining('У вас пока нет личных заметок'),
          findsOneWidget);
      expect(find.byIcon(LucideIcons.pencil), findsOneWidget);
    });
  });
}
