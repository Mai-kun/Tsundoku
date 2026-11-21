import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/category_fields_module.dart';
import 'package:tsundoku_flutter/features/edit-media/module_card.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  CategoryDraft draftFrom(Map<String, Object?> overrides) {
    var draft = CategoryDraft.empty();
    if (overrides['platform'] is String) {
      draft = draft.copyWith(platform: overrides['platform'] as String);
    }
    if (overrides['hoursPlayed'] is String) {
      draft = draft.copyWith(hoursPlayed: overrides['hoursPlayed'] as String);
    }
    if (overrides['author'] is String) {
      draft = draft.copyWith(author: overrides['author'] as String);
    }
    if (overrides['bookFormat'] is String) {
      draft = draft.copyWith(bookFormat: overrides['bookFormat'] as String);
    }
    if (overrides['totalPages'] is String) {
      draft = draft.copyWith(totalPages: overrides['totalPages'] as String);
    }
    if (overrides['totalChapters'] is String) {
      draft =
          draft.copyWith(totalChapters: overrides['totalChapters'] as String);
    }
    if (overrides['bookTotalVolumes'] is String) {
      draft = draft.copyWith(
          bookTotalVolumes: overrides['bookTotalVolumes'] as String);
    }
    if (overrides['currentVolume'] is String) {
      draft = draft.copyWith(currentVolume: overrides['currentVolume'] as String);
    }
    if (overrides['durationMinutes'] is String) {
      draft =
          draft.copyWith(durationMinutes: overrides['durationMinutes'] as String);
    }
    if (overrides['studio'] is String) {
      draft = draft.copyWith(studio: overrides['studio'] as String);
    }
    if (overrides['network'] is String) {
      draft = draft.copyWith(network: overrides['network'] as String);
    }
    if (overrides['isAnime'] is bool) {
      draft = draft.copyWith(isAnime: overrides['isAnime'] as bool);
    }
    if (overrides['seasons'] is List<SeasonDraft>) {
      draft =
          draft.copyWith(seasons: overrides['seasons'] as List<SeasonDraft>);
    }
    return draft;
  }

  Future<void> pumpModule(
    WidgetTester tester, {
    required String type,
    required CategoryDraft category,
    required void Function(CategoryDraft) onCategoryChange,
    bool isEditing = false,
  }) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(
              width: 620,
              child: CategoryFieldsModule(
                type: type,
                category: category,
                onCategoryChange: onCategoryChange,
                isEditing: isEditing,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('game-ветка: платформа и часы (делегация GameFormFields)',
      (tester) async {
    await pumpModule(
      tester,
      type: 'game',
      category: draftFrom({'platform': 'PC', 'hoursPlayed': '12'}),
      onCategoryChange: (_) {},
    );
    expect(find.byType(ModuleCard), findsOneWidget);
    expect(find.text('КАТЕГОРИЯ'), findsOneWidget);
    expect(find.text('Платформа'), findsWidgets);
    expect(find.text('Часы'), findsOneWidget);
    expect(find.text('Длительность (мин.)'), findsNothing);
  });

  testWidgets('book-ветка: формат-селект и страницы', (tester) async {
    await pumpModule(
      tester,
      type: 'book',
      category: draftFrom({'author': 'a', 'totalPages': '320'}),
      onCategoryChange: (_) {},
    );
    expect(find.text('Страницы'), findsWidgets);
    expect(find.text('Главы'), findsNothing);
    expect(find.text('Обычная книга'), findsOneWidget);
  });

  testWidgets('manga-ветка: главы и тома', (tester) async {
    await pumpModule(
      tester,
      type: 'manga',
      category:
          draftFrom({'author': 'a', 'totalChapters': '120', 'currentVolume': '7'}),
      onCategoryChange: (_) {},
    );
    expect(find.text('Главы'), findsOneWidget);
    expect(find.text('Текущий том'), findsOneWidget);
    expect(find.text('Тома'), findsOneWidget);
  });

  testWidgets('movie-ветка: длительность + аниме-чекбокс', (tester) async {
    CategoryDraft? next;
    await pumpModule(
      tester,
      type: 'movie',
      category: draftFrom({'durationMinutes': '90', 'studio': 'Toei'}),
      onCategoryChange: (v) => next = v,
    );
    expect(find.text('Длительность (мин.)'), findsOneWidget);
    expect(find.text('Это аниме?'), findsOneWidget);
    expect(find.text('Toei'), findsOneWidget);

    await tester.tap(find.text('Это аниме?'));
    await tester.pump();
    expect(next?.isAnime, isTrue);
  });

  testWidgets('tvshow + isEditing: read-only сезоны', (tester) async {
    CategoryDraft? next;
    await pumpModule(
      tester,
      type: 'tvshow',
      isEditing: true,
      category: draftFrom({
        'studio': 'Madhouse',
        'seasons': [
          const SeasonDraft(
              seasonNumber: '1', title: 'Первый', totalEpisodes: '12'),
          const SeasonDraft(seasonNumber: '2', title: '', totalEpisodes: '24'),
        ],
      }),
      onCategoryChange: (v) => next = v,
    );
    expect(find.text('Сезоны'), findsOneWidget);
    // Read-only строки (не EditableText).
    expect(find.text('Сезон 1 — Первый'), findsOneWidget);
    expect(find.text('Эпизоды: 12'), findsOneWidget);
    expect(find.text('Сезон 2'), findsOneWidget);
    expect(find.text('Эпизоды: 24'), findsOneWidget);
    expect(find.text('Сезоны редактируются на странице сериала'), findsOneWidget);
    // Редактирование студии всё ещё доступно.
    await tester.enterText(find.widgetWithText(TextField, 'Madhouse'),
        'Madhouse 2');
    await tester.pump();
    expect(next?.studio, 'Madhouse 2');
  });

  testWidgets('tvshow без isEditing: редактор сезонов (создание)',
      (tester) async {
    CategoryDraft? next;
    await pumpModule(
      tester,
      type: 'tvshow',
      category: draftFrom({}),
      onCategoryChange: (v) => next = v,
    );
    expect(find.text('Добавить сезон'), findsOneWidget);
    await tester.tap(find.text('Добавить сезон'));
    await tester.pump();
    expect(next?.seasons, hasLength(1));
    expect(next?.seasons.single.seasonNumber, '1');
  });
}
