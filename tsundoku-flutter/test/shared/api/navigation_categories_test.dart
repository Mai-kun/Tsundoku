import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/navigation_categories.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

MediaItem item({String type = 'book', String? format, List<String>? genres,
    List<String>? tags}) {
  return MediaItem.fromJson({
    'id': 'm1', 'type': type, 'title': 'T', 'status': 0,
    'createdAt': '2026-11-21T00:00:00Z',
    'format': format, 'genres': genres, 'tags': tags,
  });
}


ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('matchesSubcategory (клиентский матчер = SQL-контракт)', () {
    const comics = PromotedSubcategory(
      id: 'comics', label: 'Комиксы', icon: 'bookmark',
      parentType: 'Book', matchKind: 'format', matchValue: 'comics',
    );

    test('format: не совпадает, если тип родителя другой', () {
      expect(matchesSubcategory(item(type: 'game', format: 'comics'), comics),
          isFalse);
    });

    test('format: точное сравнение с trim/lowercase', () {
      expect(matchesSubcategory(item(format: 'comics'), comics), isTrue);
      // 1-в-1: item.format НЕ тримится (тримится только matchValue) —
      // 'Comics ' с хвостовым пробелом не матчится:
      expect(matchesSubcategory(item(format: 'Comics '), comics), isFalse);
      expect(matchesSubcategory(item(format: 'novel'), comics), isFalse);
    });

    test('genre: нормализация пробелов (строка → список → lower)', () {
      const manga = PromotedSubcategory(
        id: 'x', label: 'X', icon: 'bookmark', parentType: 'Manga',
        matchKind: 'genre', matchValue: '4 koma',
      );
      // genre «4 Koma» нормализуется в '4koma':
      expect(
        matchesSubcategory(item(type: 'manga', genres: ['Comedy', '4 Koma']),
            manga),
        isTrue,
      );
      expect(
        matchesSubcategory(item(type: 'manga', genres: ['Comedy']), manga),
        isFalse,
      );
    });

    test('tag: матч по тегу', () {
      const tag = PromotedSubcategory(
        id: 'y', label: 'Y', icon: 'bookmark', parentType: 'Book',
        matchKind: 'tag', matchValue: 'light novel',
      );
      expect(matchesSubcategory(item(tags: ['Light Novel']), tag), isTrue);
      expect(matchesSubcategory(item(tags: ['Comedy']), tag), isFalse);
    });

    test('неизвестный matchKind → false', () {
      const weird = PromotedSubcategory(
        id: 'z', label: 'Z', icon: 'bookmark', parentType: 'Book',
        matchKind: 'magic', matchValue: 'x',
      );
      expect(matchesSubcategory(item(), weird), isFalse);
    });
  });

  test('promotedCategoryOfItem: первая совпавшая категория', () {
    const a = PromotedSubcategory(
      id: 'comics', label: 'Комиксы', icon: 'bookmark', parentType: 'Book',
      matchKind: 'format', matchValue: 'comics',
    );
    const b = PromotedSubcategory(
      id: 'ln', label: 'Ранобэ', icon: 'sparkle', parentType: 'Book',
      matchKind: 'format', matchValue: 'light_novel',
    );
    final categories = [a, b];

    final got = promotedCategoryOfItem(item(format: 'light_novel'), categories);
    expect(got?.id, 'ln',
        reason: 'первая совпавшая в порядке списка — но a не матч format');
    expect(promotedCategoryOfItem(item(format: 'comics'), categories)?.id,
        'comics');
    expect(promotedCategoryOfItem(item(format: 'novel'), categories), isNull);
  });

  test('promotedParentType: Book → book (для MediaFilters)', () {
    const comics = PromotedSubcategory(
      id: 'comics', label: 'Комиксы', icon: 'bookmark', parentType: 'Book',
      matchKind: 'format', matchValue: 'comics',
    );
    expect(promotedParentType(comics), 'book');
  });

  test('promotedPresets 1-в-1 с исходником', () {
    expect(promotedPresets.length, 2);
    expect(promotedPresets[0].id, 'comics');
    expect(promotedPresets[0].label, 'Комиксы');
    expect(promotedPresets[0].icon, 'bookmark');
    expect(promotedPresets[0].parentType, 'Book');
    expect(promotedPresets[0].matchKind, 'format');
    expect(promotedPresets[0].matchValue, 'comics');
    expect(promotedPresets[1].id, 'light-novels');
    expect(promotedPresets[1].label, 'Ранобэ');
    expect(promotedPresets[1].icon, 'sparkle');
    expect(promotedPresets[1].matchValue, 'light_novel');
  });

  test('promotedIcon: известные имена → иконки, unknown → bookmark', () {
    const known = {
      'bookmark', 'book-open', 'clapperboard', 'gamepad', 'library',
      'sparkle', 'tv',
    };
    expect(promotedIcons.keys.toSet(), known);
    expect(promotedIcon('bookmark'), promotedIcons['bookmark']);
    // fallback 1-в-1 (`ICONS[name] ?? Bookmark`):
    expect(promotedIcon('no-such-icon'), promotedIcons['bookmark']);
  });

  test('loadNavigationCategories: кэш и force; save обновляет + сброс кэша',
      () async {
    var sourcesCalls = 0;
    var navigationGets = 0;
    ResponseBody handler(RequestOptions options) {
      if (options.path == '/api/settings/navigation-categories') {
        navigationGets += 1;
        if (options.method == 'PUT') {
          // Сервер возвращает подтверждённый список.
          return jsonBody(
              (options.data['categories'] as List<dynamic>)
                  .cast<Map<String, dynamic>>(),
              200);
        }
        return jsonBody([
          {'id': 'comics', 'label': 'Комиксы', 'icon': 'bookmark',
           'parentType': 'Book', 'matchKind': 'format', 'matchValue': 'comics'},
        ], 200);}
      if (options.path == '/api/settings/sources') {
        sourcesCalls += 1;
        return jsonBody(<Map<String, dynamic>>[], 200);}
      return ResponseBody.fromBytes(<int>[], 200);
    }

    final adapter = StubAdapter(handler);
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    final api = TsundokuApi(dio);
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(navigationCategoriesProvider.notifier);

    final first = await ctrl.loadNavigationCategories();
    expect(first.single.id, 'comics');
    expect(container.read(navigationCategoriesProvider).single.id, 'comics');

    // Повторный load из кэша (loaded=true):
    await ctrl.loadNavigationCategories();
    expect(navigationGets, 1);

    // force — перечитывает:
    await ctrl.loadNavigationCategories(force: true);
    expect(navigationGets, 2);

    // Прогрев sources-кэша, затем save должен его инвалидировать:
    await api.getSources();
    expect(sourcesCalls, 1);

    await ctrl.saveNavigationCategories([
      const PromotedSubcategory(
        id: 'light-novels', label: 'Ранобэ', icon: 'sparkle',
        parentType: 'Book', matchKind: 'format', matchValue: 'light_novel',
      ),
    ]);
    expect(container.read(navigationCategoriesProvider).single.id,
        'light-novels');
    // Серверный кэш сброшен:
    await api.getSources();
    expect(sourcesCalls, 2);
  });

  test('saveNavigationCategories: ошибка сервера → detail из ProblemDetails',
      () async {
    final adapter = StubAdapter((options) =>
        jsonBody({'detail': 'slug busy'}, 400));
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    final api = TsundokuApi(dio);
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(navigationCategoriesProvider.notifier);
    await expectLater(
      ctrl.saveNavigationCategories([promotedPresets.first]),
      throwsA(isA<Exception>().having(
        (e) => e.toString(), 'message', contains('slug busy'),
      )),
    );
  });

  test('loadNavigationCategories: ошибка сервера бросает статус', () async {
    final adapter = StubAdapter((options) =>
        jsonBody(null, 500));
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..options.baseUrl = 'http://127.0.0.1:5150';
    final api = TsundokuApi(dio);
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(navigationCategoriesProvider.notifier);
    await expectLater(
      ctrl.loadNavigationCategories(),
      throwsA(isA<ApiError>()),
    );
  });
}
