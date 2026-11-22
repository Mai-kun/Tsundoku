import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/create_modal.dart';
import 'package:tsundoku_flutter/features/edit-media/edit_media_workspace.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'id': 'm1',
          'type': 'game',
          'title': 'Elden Ring',
          'status': 0,
          'createdAt': '2024-01-01T00:00:00Z',
        }),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

MediaItem _sampleItem() {
  return MediaItem.fromJson(<String, dynamic>{
    'id': 'm1',
    'type': 'game',
    'title': 'Elden Ring',
    'status': 0,
    'source': 'manual',
    'createdAt': '2024-01-01T00:00:00Z',
    'updatedAt': '2024-01-01T00:00:00Z',
  });
}

Widget _buildTestSubject({
  required bool isOpen,
  VoidCallback? onClose,
  ValueChanged<MediaItem>? onCreated,
  MediaItem? editingItem,
}) {
  final dio = Dio()..httpClientAdapter = _StubAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ],
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: CreateModal(
          isOpen: isOpen,
          onClose: onClose ?? () {},
          onCreated: onCreated ?? (_) {},
          editingItem: editingItem,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders EditMediaWorkspace when isOpen is true', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject(isOpen: true));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(EditMediaWorkspace), findsOneWidget);
    expect(find.text('ОСНОВНЫЕ ДАННЫЕ И КАТЕГОРИЯ'), findsOneWidget);
  });

  testWidgets('hides content when isOpen is false', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildTestSubject(isOpen: false));
    await tester.pumpAndSettle();

    expect(find.text('ОСНОВНЫЕ ДАННЫЕ И КАТЕГОРИЯ'), findsNothing);
  });

  testWidgets('passes editingItem and renders item title', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final item = _sampleItem();
    await tester.pumpWidget(_buildTestSubject(
      isOpen: true,
      editingItem: item,
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.widgetWithText(TextField, 'Elden Ring'), findsOneWidget);
    expect(find.text('РЕДАКТИРОВАТЬ МЕДИА'), findsOneWidget);
  });
}
