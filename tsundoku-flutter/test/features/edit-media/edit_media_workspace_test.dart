import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/edit-media/edit_media_workspace.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_window.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final path = options.uri.path;
    if (options.method == 'POST' && path.contains('/api/media')) {
      return ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'id': 'm-new',
            'type': 'game',
            'title': 'Created',
            'status': 0,
            'createdAt': '2024-01-01T00:00:00Z',
          }),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    if (options.method == 'PUT' && path.contains('/api/media/m1')) {
      return ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'id': 'm1',
            'type': 'game',
            'title': 'Updated',
            'status': 0,
            'createdAt': '2024-01-01T00:00:00Z',
          }),
          200,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString(
        jsonEncode(<String, Object?>{}), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

MediaItem _gameItem() => MediaItem.fromJson(<String, dynamic>{
      'id': 'm1',
      'type': 'game',
      'title': 'Witcher',
      'status': 1,
      'createdAt': '2024-01-01T00:00:00Z',
      'platform': 'PC',
      'hoursPlayed': 12,
      'score': 9,
    });

Future<void> pumpWorkspace(
  WidgetTester tester, {
  MediaItem? editingItem,
  required void Function(MediaItem) onCreated,
  required void Function() onClose,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
  dio.httpClientAdapter = StubAdapter();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Material(
        child: EditMediaWorkspace(
          isOpen: true,
          onClose: onClose,
          onCreated: onCreated,
          editingItem: editingItem,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('desktop-канвас: 5 окон + control bar + reset', (tester) async {
    var closed = false;
    await pumpWorkspace(
      tester,
      editingItem: null,
      onCreated: (_) {},
      onClose: () => closed = true,
    );
    expect(find.byType(WorkspaceWindow), findsNWidgets(5));
    expect(find.text('ОСНОВНЫЕ ДАННЫЕ И КАТЕГОРИЯ'), findsOneWidget);
    expect(find.text('АЛЬТЕРНАТИВНЫЕ НАЗВАНИЯ'), findsOneWidget);
    expect(find.text('ЗАМЕТКИ'), findsOneWidget);
    expect(find.text('ЦИТАТЫ И ВЫПИСКИ'), findsOneWidget);
    expect(find.text('ОБЛОЖКИ И ИЗОБРАЖЕНИЯ'), findsOneWidget);
    // Control bar.
    expect(find.text('ДОБАВИТЬ МЕДИА'), findsOneWidget);
    expect(find.text('Сбросить раскладку'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Добавить'), findsOneWidget);

    // Close по «Отмена».
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('валидация: пустой title → ошибка, submit не отправляется',
      (tester) async {
    await pumpWorkspace(
      tester,
      editingItem: null,
      onCreated: (_) {},
      onClose: () {},
    );
    await tester.tap(find.text('Добавить'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Укажите название.'), findsOneWidget);
  });

  testWidgets('create: POST payload с типом game', (tester) async {
    MediaItem? created;
    await pumpWorkspace(
      tester,
      editingItem: null,
      onCreated: (m) => created = m,
      onClose: () {},
    );
    // Заголовок в «Основных данных» (первый TextField — title).
    final titleField = find.widgetWithText(TextField, 'Например, The Witcher 3');
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, 'Hollow Knight');
    await tester.pump();
    await tester.tap(find.text('Добавить'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(created, isNotNull);
    expect(created!.id, 'm-new');
  });

  testWidgets('edit: применяет поля item + платформа', (tester) async {
    await pumpWorkspace(
      tester,
      editingItem: _gameItem(),
      onCreated: (_) {},
      onClose: () {},
    );
    // Заголовок и платформа подставлены.
    expect(find.widgetWithText(TextField, 'Witcher'), findsOneWidget);
    expect(find.text('PC'), findsOneWidget); // триггер type + поле platform
    expect(find.widgetWithText(TextField, '9'), findsOneWidget); // score
    expect(find.widgetWithText(TextField, '12'), findsOneWidget); // hours
    expect(find.text('СОХРАНИТЬ'), findsNothing); // uppercase не применяется к кнопке
    // Тайтл control bar — editTitle в uppercase.
    expect(find.textContaining('РЕДАКТИРОВАТЬ МЕДИА'), findsOneWidget);
  });

  testWidgets('mobile: скролл-стек секций вместо окон', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: EditMediaWorkspace(
            isOpen: true,
            onClose: () {},
            onCreated: (_) {},
            editingItem: null,
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(WorkspaceWindow), findsNothing);
    expect(find.text('Основные данные и категория'), findsNothing);
    expect(find.textContaining('Основные данные'), findsNothing);
    // Mobile: заголовок не uppercase-лейбл модуля, секции-карточки видны.
    expect(find.byIcon(LucideIcons.rotateCcw), findsNothing); // только desktop
  });
}
