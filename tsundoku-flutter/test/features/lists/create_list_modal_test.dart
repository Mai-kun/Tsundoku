import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/lists/create_list_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    lastRequest = options;
    lastBody = options.data;

    final path = options.uri.path;
    if (options.method == 'POST' && path.contains('/api/lists')) {
      return ResponseBody.fromString(
        jsonEncode({'id': 'new-list-id'}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (options.method == 'PUT' && path.contains('/api/lists/l1')) {
      return ResponseBody.fromString(
        jsonEncode(<String, dynamic>{}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }
    if (path.contains('/api/media')) {
      return ResponseBody.fromString(
        jsonEncode([]),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );
    }

    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{}),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _buildSubject({
  required bool isOpen,
  CustomListSummary? list,
  VoidCallback? onClose,
  VoidCallback? onSaved,
  SmartListBuilderWidget? smartListBuilder,
  _CapturingAdapter? adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _CapturingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: CreateListModal(
          isOpen: isOpen,
          list: list,
          onClose: onClose ?? () {},
          onSaved: onSaved ?? () {},
          smartListBuilder: smartListBuilder,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hides when isOpen is false', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildSubject(isOpen: false));
    await tester.pumpAndSettle();

    expect(find.text('Создать список'), findsNothing);
  });

  testWidgets('renders create form and saves new list', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final adapter = _CapturingAdapter();
    var saved = false;
    var closed = false;

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      onSaved: () => saved = true,
      onClose: () => closed = true,
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Создать список'), findsWidgets);
    expect(find.text('Обычный список'), findsOneWidget);
    expect(find.text('Умный список'), findsOneWidget);

    final saveButtonFinder =
        find.widgetWithText(ElevatedButton, 'Создать список');
    expect(saveButtonFinder, findsOneWidget);

    // Enter name & description
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Мой список');
    await tester.enterText(textFields.at(1), 'Описание списка');
    await tester.pumpAndSettle();

    // Select color (click second color)
    await tester.tap(find.byType(InkWell).at(4)); // color circles
    await tester.pumpAndSettle();

    // Select heart icon
    await tester.ensureVisible(find.byIcon(LucideIcons.heart));
    await tester.tap(find.byIcon(LucideIcons.heart));
    await tester.pumpAndSettle();

    // Click Save
    await tester.tap(saveButtonFinder);
    await tester.pumpAndSettle();

    expect(adapter.lastRequest?.method, 'POST');
    expect(adapter.lastRequest?.path, contains('/api/lists'));
    expect(adapter.lastBody, {
      'name': 'Мой список',
      'description': 'Описание списка',
      'icon': 'heart',
      'color': '#4a72b8',
      'smartQueryJson': null,
    });
    expect(saved, isTrue);
    expect(closed, isTrue);
  });

  testWidgets('renders edit mode with existing values and updates list',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final adapter = _CapturingAdapter();
    var saved = false;
    var closed = false;

    final existingList = CustomListSummary.fromJson(<String, dynamic>{
      'id': 'l1',
      'name': 'Существующий',
      'description': 'Существующее описание',
      'color': '#3f8f6b',
      'icon': 'star',
      'itemsCount': 5,
      'updatedAt': '2024-01-01T00:00:00Z',
      'isSmart': false,
    });

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      list: existingList,
      onSaved: () => saved = true,
      onClose: () => closed = true,
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Редактировать список'), findsOneWidget);
    // Type switcher should not be visible in edit mode
    expect(find.text('Обычный список'), findsNothing);

    // Existing values populated
    expect(find.text('Существующий'), findsOneWidget);
    expect(find.text('Существующее описание'), findsOneWidget);

    // Update name
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Обновленный');
    await tester.pumpAndSettle();

    // Click Save
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(adapter.lastRequest?.method, 'PUT');
    expect(adapter.lastRequest?.path, contains('/api/lists/l1'));
    expect(saved, isTrue);
    expect(closed, isTrue);
  });

  testWidgets('switches to smart list and renders smart list builder',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      smartListBuilder: (context, {
        required query,
        required onQueryChange,
        required onMatchesChange,
        required allMedia,
      }) {
        return Column(
          children: [
            const Text('Custom Smart List Builder'),
            ElevatedButton(
              onPressed: () {
                onMatchesChange([
                  MediaItem.fromJson(<String, dynamic>{
                    'id': 'm1',
                    'title': 'Test Media',
                    'type': 'game',
                    'status': 0,
                    'createdAt': '2024-01-01T00:00:00Z',
                  }),
                ]);
              },
              child: const Text('Simulate Matches'),
            ),
          ],
        );
      },
    ));
    await tester.pumpAndSettle();

    // Click Smart list tab
    await tester.tap(find.text('Умный список'));
    await tester.pumpAndSettle();

    expect(find.text('Custom Smart List Builder'), findsOneWidget);

    // Simulate matches
    await tester.tap(find.text('Simulate Matches'));
    await tester.pumpAndSettle();

    expect(find.text('⚡ 1'), findsOneWidget);
  });
}
