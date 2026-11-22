import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/views/calendar_view.dart';
import 'package:tsundoku_flutter/views/category_view.dart';
import 'package:tsundoku_flutter/views/goals_view.dart';
import 'package:tsundoku_flutter/views/history_view.dart';
import 'package:tsundoku_flutter/views/lists_view.dart';
import 'package:tsundoku_flutter/views/settings_view.dart';
import 'package:tsundoku_flutter/views/stats_view.dart';
import 'package:tsundoku_flutter/widgets/layout/app_shell.dart';
import 'package:tsundoku_flutter/widgets/layout/header.dart';
import 'package:tsundoku_flutter/widgets/layout/sidebar.dart';

class _CapturingStubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final p = options.path;
    dynamic data = <dynamic>[];
    if (p.contains('/api/settings/sources')) {
      data = <dynamic>[
        {
          'id': 'anilist',
          'name': 'AniList',
          'description': 'Аниме и манга база данных с GraphQL API',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': false,
          'optionalApiKey': false,
          'hasKey': false,
          'maskedKey': null,
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['anime', 'manga'],
        },
        {
          'id': 'shikimori',
          'name': 'Shikimori',
          'description': 'Энциклопедия аниме и манги на русском языке',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': false,
          'optionalApiKey': false,
          'hasKey': false,
          'maskedKey': null,
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['anime', 'manga'],
        },
        {
          'id': 'mangadex',
          'name': 'MangaDex',
          'description': 'Крупнейший открытый каталог манги',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': false,
          'optionalApiKey': false,
          'hasKey': false,
          'maskedKey': null,
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['manga'],
        },
        {
          'id': 'kitsu',
          'name': 'Kitsu',
          'description': 'Платформа для трекинга аниме и манги',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': false,
          'optionalApiKey': false,
          'hasKey': false,
          'maskedKey': null,
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['anime', 'manga'],
        },
        {
          'id': 'steam',
          'name': 'Steam',
          'description': 'Игровая платформа Valve',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': false,
          'optionalApiKey': true,
          'hasKey': false,
          'maskedKey': null,
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['game'],
        },
        {
          'id': 'rawg',
          'name': 'RAWG',
          'description': 'Крупнейшая база видеоигр',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': true,
          'optionalApiKey': false,
          'hasKey': true,
          'maskedKey': 'rawg_***_key',
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['game'],
        },
        {
          'id': 'tmdb',
          'name': 'TMDB',
          'description': 'The Movie Database — фильмы и сериалы',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': true,
          'optionalApiKey': false,
          'hasKey': true,
          'maskedKey': 'tmdb_***_key',
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['movie', 'tvshow'],
        },
        {
          'id': 'openlibrary',
          'name': 'Open Library',
          'description': 'Открытый каталог книг от Internet Archive',
          'isEnabled': true,
          'isConfigured': true,
          'requiresApiKey': false,
          'optionalApiKey': false,
          'hasKey': false,
          'maskedKey': null,
          'isScraper': false,
          'isProxied': false,
          'mediaTypes': ['book'],
        },
      ];
    } else if (p.contains('/api/settings/proxy')) {
      data = <String, dynamic>{
        'enabled': false,
        'proxyUrl': '',
        'username': null,
        'hasPassword': false,
        'maskedPassword': null,
        'proxiedSources': <String>[],
      };
    } else if (p.contains('/api/settings/search-priorities')) {
      data = <String, dynamic>{
        'priorities': {
          'anime': ['anilist', 'shikimori', 'kitsu'],
          'manga': ['mangadex', 'anilist', 'kitsu'],
          'game': ['steam', 'rawg'],
          'movie': ['tmdb', 'imdb'],
          'book': ['openlibrary', 'googlebooks'],
        },
      };
    } else if (p.contains('/stats/advanced')) {
      data = <String, dynamic>{
        'totalTitles': 50,
        'completedTitles': 35,
        'completionRatePercent': 70.0,
        'totalHours': 120.0,
        'totalDays': 5.0,
        'averageScore': 8.4,
        'currentStreakDays': 7,
        'gameHours': 50.0,
        'movieHours': 20.0,
        'seriesHours': 30.0,
        'animeHours': 15.0,
        'bookHours': 5.0,
        'mangaHours': 0.0,
        'totalMoviesWatched': 10,
        'totalEpisodesWatched': 45,
        'totalPagesRead': 1500,
        'totalChaptersRead': 0,
        'gamesCompleted': 5,
        'moviesCompleted': 10,
        'seriesCompleted': 4,
        'animeCompleted': 3,
        'booksCompleted': 2,
        'mangaCompleted': 0,
        'scoreDistribution': {'8': 10, '9': 15},
        'averageScoreByType': {
          'game': 8.0,
          'movie': 8.5,
          'series': 8.2,
          'anime': 9.0,
          'book': 7.5,
          'manga': 0.0,
        },
        'monthlyCompletions': [
          {'monthYear': '2026-01', 'count': 5},
        ],
        'topGenres': [
          {'genre': 'action', 'count': 15, 'percentage': 30.0},
        ],
        'topGenresByType': <String, dynamic>{},
        'dailyActivity': {'2026-01-01': 3.0},
        'plannedTitles': 10,
        'unlockedBadgesCount': 3,
        'badges': <dynamic>[],
      };
    } else if (p.contains('/stats/taste-profile')) {
      data = <String, dynamic>{
        'persona': {
          'icon': 'critic',
          'title': 'Строгий критик',
          'description': 'Высокие стандарты',
          'traits': ['Честные оценки'],
        },
        'sunkCost': {
          'lowScoreHours': 10.0,
          'percentageOfTotal': 5.0,
          'titlesCount': 2,
          'categoryBreakdown': {'game': 10.0},
        },
        'divergence': {
          'hiddenGem': null,
          'disappointment': null,
        },
        'genreParadox': <dynamic>[],
        'eraAffinity': <dynamic>[],
        'genreRadar': <dynamic>[],
        'dropAnalytics': null,
      };
    } else if (p.contains('/api/calendar/backlog-deadlines')) {
      data = <dynamic>[];
    } else if (p.contains('/api/calendar')) {
      data = <String, dynamic>{
        'from': '2026-11-01',
        'to': '2026-11-30',
        'days': <dynamic>[],
      };
    } else if (p.contains('/api/goals')) {
      data = <dynamic>[];
    } else if (p.contains('/api/lists')) {
      data = <dynamic>[
        {
          'id': 'l1',
          'name': 'Любимое аниме',
          'description': 'Коллекция лучших тайтлов',
          'icon': 'star',
          'color': '#f59e0b',
          'itemsCount': 14,
          'updatedAt': '2025-01-01T00:00:00Z',
          'previewCovers': [],
          'isSmart': false,
        },
        {
          'id': 'l2',
          'name': 'Умный топ',
          'description': 'Автоматический список лучших тайтлов',
          'icon': 'sparkles',
          'color': '#8b5cf6',
          'itemsCount': 25,
          'updatedAt': '2025-01-02T00:00:00Z',
          'previewCovers': [],
          'isSmart': true,
          'smartQueryJson': '{"categories":["anime"],"minScore":8}',
        },
      ];
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'x-total-count': ['42'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoopJobsClient extends JobsClientController {
  @override
  void connect() {}
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> goldenScreenshot(
    WidgetTester tester, {
    required Widget child,
    required String name,
    bool isSliver = false,
    bool noPadding = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = _CapturingStubAdapter();
    final api = TsundokuApi(dio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          jobsClientProvider.overrideWith(_NoopJobsClient.new),
          tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
        ],
        child: MaterialApp(
          theme: buildTsundokuTheme(),
          home: Material(
            color: const Color(0xFF0D0F14),
            child: AppShell(
              noPadding: noPadding,
              sidebar: Sidebar(
                activeView: 'home',
                onNavigate: (_) {},
                onCreate: () {},
              ),
              header: Header(
                title: 'Tsundoku',
                onSearch: () {},
              ),
              slivers: isSliver ? [child] : null,
              child: !isSliver ? child : null,
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('golden 01_category_view', (tester) async {
    await goldenScreenshot(
      tester,
      isSliver: true,
      child: CategoryView(
        category: 'anime',
        refreshKey: 0,
        onOpen: (_) {},
        onMediaChanged: () {},
      ),
      name: '01_category_view',
    );
  });

  testWidgets('golden 02_stats_view', (tester) async {
    await goldenScreenshot(
      tester,
      child: const StatsView(refreshKey: 0),
      name: '02_stats_view',
    );
  });

  testWidgets('golden 03_lists_view', (tester) async {
    await goldenScreenshot(
      tester,
      child: const ListsView(),
      name: '03_lists_view',
    );
  });

  testWidgets('golden 04_history_view', (tester) async {
    await goldenScreenshot(
      tester,
      child: const HistoryView(refreshKey: 0),
      name: '04_history_view',
    );
  });

  testWidgets('golden 05_calendar_view', (tester) async {
    await goldenScreenshot(
      tester,
      child: const CalendarView(),
      name: '05_calendar_view',
    );
  });

  testWidgets('golden 06_goals_view', (tester) async {
    await goldenScreenshot(
      tester,
      child: GoalsView(refreshKey: 0, onOpenMedia: (_) {}, onMediaChanged: () {}),
      name: '06_goals_view',
    );
  });

  testWidgets('golden 07_settings_sources', (tester) async {
    await goldenScreenshot(
      tester,
      noPadding: true,
      child: const SettingsView(initialTab: SettingsTab.sources),
      name: '07_settings_sources',
    );
  });

  testWidgets('golden 08_settings_search', (tester) async {
    await goldenScreenshot(
      tester,
      noPadding: true,
      child: const SettingsView(initialTab: SettingsTab.search),
      name: '08_settings_search',
    );
  });

  testWidgets('golden 09_settings_import', (tester) async {
    await goldenScreenshot(
      tester,
      noPadding: true,
      child: const SettingsView(initialTab: SettingsTab.importTab),
      name: '09_settings_import',
    );
  });
}
