import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/utils/ui_settings.dart';

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

/// Полный цикл uiSettings: persisted-ключи (аналог localStorage) → серверные
/// ReadingSettings перекрывают → setters persist → voice-memory.

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  late StubAdapter adapter;
  late TsundokuApi api;
  late ProviderContainer container;
  late UiSettingsController ctrl;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) {
      if (options.path == '/api/settings/reading') {
        return jsonBody({'bookPageMinutes': 2, 'mangaChapterMinutes': 8}, 200);
      }
      return jsonBody(null, 200);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    ctrl = container.read(uiSettingsProvider.notifier);
  });

  test('дефолты 1-в-1 с исходником', () {
    final s = container.read(uiSettingsProvider);
    expect(s.lastView, 'home');
    expect(s.groupByType, isFalse);
    expect(s.sortOption, 'newest');
    expect(s.statusFilter, 'all');
    expect(s.bookPageMinutes, defaultBookPageMinutes);
    expect(s.mangaChapterMinutes, defaultMangaChapterMinutes);
    expect(s.statsScope, 'completed');
    expect(s.onCloseAction, OnCloseActionPref.tray);
    expect(s.appIcon, 'default');
    expect(s.theme, 'obsidian');
    expect(s.isLoaded, isFalse);
  });

  test('loadPersisted: persisted-значения → стейт; load(): сервер перекрывает',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tsundoku_last_view': jsonEncode('history'),
      'tsundoku_group_by_type': jsonEncode(true),
      'tsundoku_reading_book_page_minutes': '3',
      'tsundoku_reading_manga_chapter_minutes': '12',
      'stats_scope': 'all',
      'tsundoku_on_close_action': 'ask',
      'tsundoku_theme': 'obsidian',
    });
    await ctrl.loadPersisted();

    final s = container.read(uiSettingsProvider);
    expect(s.lastView, 'history');
    expect(s.groupByType, isTrue);
    // Сервер (2/8) перекрыл persisted (3/12):
    expect(s.bookPageMinutes, 2);
    expect(s.mangaChapterMinutes, 8);
    expect(s.statsScope, 'all');
    expect(s.onCloseAction, OnCloseActionPref.ask);
    expect(s.isLoaded, isTrue);
  });

  test('load(): чтение недоступно → persisted/дефолты сохраняются, isLoaded',
      () async {
    // Адаптер всегда 500.
    adapter = StubAdapter(
        (options) => ResponseBody.fromString(jsonEncode(null), 500));
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    ctrl = container.read(uiSettingsProvider.notifier);

    await ctrl.loadPersisted();
    final s = container.read(uiSettingsProvider);
    expect(s.isLoaded, isTrue);
    expect(s.bookPageMinutes, defaultBookPageMinutes);
  });

  test('setLastView: detail/seasons не пишутся (deep-link)', () async {
    await ctrl.setLastView('stats');
    expect(container.read(uiSettingsProvider).lastView, 'stats');

    await ctrl.setLastView('detail');
    expect(container.read(uiSettingsProvider).lastView, 'stats');
    await ctrl.setLastView('seasons');
    expect(container.read(uiSettingsProvider).lastView, 'stats');
  });

  test('setters persist: повторная загрузка возвращает сохранённое', () async {
    await ctrl.setGroupByType(true);
    await ctrl.setSortOption('title');
    await ctrl.setStatusFilter('2');
    await ctrl.setStatsScope('all');
    await ctrl.setOnCloseAction(OnCloseActionPref.exit);
    await ctrl.setAppIcon('alt');
    await ctrl.setTheme('obsidian');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tsundoku_group_by_type'), jsonEncode(true));
    expect(prefs.getString('tsundoku_sort_option'), jsonEncode('title'));
    expect(prefs.getString('tsundoku_status_filter'), jsonEncode('2'));
    expect(prefs.getString('stats_scope'), 'all');
    expect(prefs.getString('tsundoku_on_close_action'), 'exit');
    expect(prefs.getString('tsundoku_app_icon'), jsonEncode('alt'));

    // Новый контроллер/контейнер — persisted возвращается:
    final container2 = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container2.dispose);
    final ctrl2 = container2.read(uiSettingsProvider.notifier);
    await ctrl2.loadPersisted();
    expect(container2.read(uiSettingsProvider).groupByType, isTrue);
    expect(container2.read(uiSettingsProvider).sortOption, 'title');
    expect(container2.read(uiSettingsProvider).statusFilter, '2');
    expect(container2.read(uiSettingsProvider).statsScope, 'all');
    expect(container2.read(uiSettingsProvider).onCloseAction,
        OnCloseActionPref.exit);
    expect(container2.read(uiSettingsProvider).appIcon, 'alt');
  });

  test('cast/staff size: get/set с дефолтом compact', () async {
    expect(ctrl.getCastSize('anime'), PeopleCardSize.compact);
    await ctrl.setCastSize('anime', PeopleCardSize.large);
    expect(ctrl.getCastSize('anime'), PeopleCardSize.large);
    expect(ctrl.getCastSize('manga'), PeopleCardSize.compact,
        reason: 'пер-категория: смена anime не трогает manga');

    await ctrl.setStaffSize('manga', PeopleCardSize.large);
    expect(ctrl.getStaffSize('manga'), PeopleCardSize.large);
    expect(ctrl.getCastSize('anime'), PeopleCardSize.large,
        reason: 'cast и staff — независимые карты');
  });

  test('voice memory: remember добавляет и starred, toggle снимает', () async {
    await ctrl.rememberVoiceOption(VoiceOptionScope.read, ' Light Novel ');
    var mem = ctrl.getVoiceOptions(VoiceOptionScope.read);
    expect(mem.custom, ['Light Novel']);
    expect(mem.favorites, ['Light Novel'], reason: 'авто-starred');

    // Повторное remember — без дублей:
    await ctrl.rememberVoiceOption(VoiceOptionScope.read, 'Light Novel');
    expect(ctrl.getVoiceOptions(VoiceOptionScope.read).custom.length, 1);

    await ctrl.rememberVoiceOption(VoiceOptionScope.read, 'Censored');
    mem = ctrl.getVoiceOptions(VoiceOptionScope.read);
    expect(mem.favorites, ['Light Novel', 'Censored']);

    await ctrl.toggleVoiceFavorite(VoiceOptionScope.read, 'Light Novel');
    mem = ctrl.getVoiceOptions(VoiceOptionScope.read);
    expect(mem.favorites, ['Censored']);
    expect(mem.custom, ['Light Novel', 'Censored'],
        reason: 'кастомное значение остаётся в списке');

    // watch/read — независимые скоупы:
    expect(ctrl.getVoiceOptions(VoiceOptionScope.watch).favorites, isEmpty);
  });

  test('rememberVoiceOption: пустое значение игнорируется', () async {
    await ctrl.rememberVoiceOption(VoiceOptionScope.watch, '   ');
    expect(ctrl.getVoiceOptions(VoiceOptionScope.watch).custom, isEmpty);
  });

  test('setReadingSpeed: persist + серверный PUT', () async {
    final saved = await ctrl.setReadingSpeed(2.5, 9);
    expect(saved.bookPageMinutes, 2);
    expect(saved.mangaChapterMinutes, 8);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tsundoku_reading_book_page_minutes'), '2.5');
    expect(prefs.getString('tsundoku_reading_manga_chapter_minutes'), '9.0');
    expect(container.read(uiSettingsProvider).bookPageMinutes, 2.5);
    expect(container.read(uiSettingsProvider).mangaChapterMinutes, 9.0);
  });

  test('voice memory persist: пересоздание возвращает память', () async {
    await ctrl.rememberVoiceOption(VoiceOptionScope.watch, 'Studio Ghibli');

    final container2 = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container2.dispose);
    final ctrl2 = container2.read(uiSettingsProvider.notifier);
    await ctrl2.loadPersisted();
    expect(ctrl2.getVoiceOptions(VoiceOptionScope.watch).favorites,
        ['Studio Ghibli']);
  });

  test('enum-wires 1-в-1 (PeopleCardSize/OnCloseAction/VoiceOptionScope)',
      () {
    expect(PeopleCardSize.compact.wire, 'compact');
    expect(PeopleCardSize.large.wire, 'large');
    expect(OnCloseActionPref.tray.wire, 'tray');
    expect(OnCloseActionPref.exit.wire, 'exit');
    expect(OnCloseActionPref.ask.wire, 'ask');
    expect(VoiceOptionScope.watch.wire, 'watch');
    expect(VoiceOptionScope.read.wire, 'read');
  });
}
