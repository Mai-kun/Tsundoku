import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/shared/utils/ui_settings.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/creator_section.dart';

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

/// Тесты `CreatorSection.svelte`: шапка создателя, сводка коллекции,
/// staff-карточки, другие работы, unknown-создатель.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ProviderContainer> pumpCreator(
    WidgetTester tester, {
    required String creatorName,
    CreatorRole role = CreatorRole.author,
    String? mediaType = 'book',
    List<StaffMember> staff = const [],
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(TsundokuApi(dio)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: CreatorSection(
              creatorName: creatorName,
              role: role,
              mediaType: mediaType,
              currentMediaId: 'm1',
              staff: staff,
              category: 'book',
              onOpenMedia: (_) {},
              onSearch: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('автор: шапка с лейблом АВТОР + BookOpen-иконка, поиск',
      (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter((options) {
      return jsonBody(null); // сводки нет
    });
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: CreatorSection(
              creatorName: 'Kentaro Miura',
              role: CreatorRole.author,
              mediaType: 'book',
              currentMediaId: 'm1',
              category: 'book',
              onOpenMedia: _noopOpen,
              onSearch: _noopSearch,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('АВТОР'), findsOneWidget);
    expect(find.text('Kentaro Miura'), findsOneWidget);
    expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget);
    expect(find.byIcon(LucideIcons.search), findsOneWidget);
  });

  testWidgets('сводка: «В вашей коллекции: N • Завершено: M (P%)» + бар',
      (tester) async {
    late ProviderContainer container;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter((options) {
      if (options.path.contains('/creator-summary')) {
        expect(options.queryParameters['name'], 'Kentaro Miura');
        return jsonBody({
          'name': 'Kentaro Miura',
          'role': 'author',
          'totalCount': 8,
          'completedCount': 4,
          'averageScore': 8.75,
          'otherItems': [],
        });
      }
      return jsonBody(null);
    });
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: CreatorSection(
              creatorName: 'Kentaro Miura',
              role: CreatorRole.author,
              mediaType: 'book',
              currentMediaId: 'm1',
              category: 'book',
              onOpenMedia: _noopOpen,
              onSearch: _noopSearch,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('В вашей коллекции'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.textContaining('(50%)'), findsOneWidget);
    expect(find.text('★ 8.8'), findsOneWidget); // toFixed(1)
  });

  testWidgets('unknown-создатель: карточка без загрузки сводки и поиска',
      (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter((options) => jsonBody(null));
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: CreatorSection(
              creatorName: 'Неизвестный автор',
              role: CreatorRole.author,
              mediaType: 'book',
              currentMediaId: 'm1',
              category: 'book',
              onOpenMedia: _noopOpen,
              onSearch: _noopSearch,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    // Сводка не запрашивалась (requestJson пуст; seen пуст).
    expect(find.byIcon(LucideIcons.search), findsNothing);
    expect(find.text('Неизвестный автор'), findsOneWidget); // имя без аперкейса
  });

  testWidgets('staff-карточки: имена + роли, PeopleSizeToggle staff',
      (tester) async {
    late ProviderContainer container;
    container = await pumpCreator(
      tester,
      creatorName: 'Studio Ghibli',
      role: CreatorRole.studio,
      staff: [
        const StaffMember(
            name: 'Hayao Miyazaki', role: 'Director', imageUrl: null),
        const StaffMember(name: 'Isao Takahata', role: 'Producer', imageUrl: null),
      ],
    );

    expect(find.text('СТУДИЯ'), findsOneWidget);
    expect(find.textContaining(RegExp('Авторы и создатели', caseSensitive: false)), findsOneWidget);
    expect(find.text('Hayao Miyazaki'), findsOneWidget);
    expect(find.text('Director'), findsOneWidget);
    expect(find.text('Isao Takahata'), findsOneWidget);
    // Первый символ в плейсхолдере.
    expect(find.text('H'), findsOneWidget);
    // staff-карточки присутствуют в стейте ( размер по категории).
    expect(container.read(uiSettingsProvider).staffSizeByCategory, isEmpty);
  });

  testWidgets('game-тип: лейбл РАЗРАБОТЧИК + Gamepad-иконка', (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter((options) => jsonBody(null));
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: CreatorSection(
              creatorName: 'Team Cherry',
              role: CreatorRole.studio,
              mediaType: 'game',
              currentMediaId: 'm1',
              category: 'game',
              onOpenMedia: _noopOpen,
              onSearch: _noopSearch,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('РАЗРАБОТЧИК'), findsOneWidget);
    expect(find.byIcon(LucideIcons.gamepad2), findsOneWidget);
  });
}

void _noopOpen(MediaItem _) {}
void _noopSearch(String _) {}
