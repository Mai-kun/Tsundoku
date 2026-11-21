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
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/media_files_section.dart';

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

/// Тесты `MediaFilesSection.svelte`: рендер вложений, удаление через
/// confirm, пустое состояние, иконки по расширению.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<MediaAttachment> attachments() => [
        MediaAttachment.fromJson({
          'id': 'f1',
          'fileName': 'book.epub',
          'fileSizeBytes': 2048,
          'addedAt': '2024-01-01T00:00:00Z',
        }),
        MediaAttachment.fromJson({
          'id': 'f2',
          'fileName': 'scan.pdf',
          'fileSizeBytes': 1048576,
          'addedAt': '2024-01-02T00:00:00Z',
        }),
      ];

  Future<ProviderContainer> pumpFiles(
    WidgetTester tester, {
    required List<MediaAttachment> attachments,
    required StubAdapter Function(StubAdapter stub) stubBuilder,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = stubBuilder(StubAdapter((o) => jsonBody([])));
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: MediaFilesSection(mediaId: 'm1', attachments: attachments),
              ),
              const ConfirmModal(),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('пусто: «Пока нет прикреплённых файлов»', (tester) async {
    await pumpFiles(
      tester,
      attachments: [],
      stubBuilder: (stub) => stub,
    );
    expect(find.textContaining('Пока нет прикреплённых файлов'),
        findsOneWidget);
    expect(find.text('Файлы и документы'), findsOneWidget);
  });

  testWidgets('вложения: имена, размеры (Б/МБ), иконки по расширению',
      (tester) async {
    await pumpFiles(
      tester,
      attachments: attachments(),
      stubBuilder: (stub) => stub,
    );

    expect(find.text('book.epub'), findsOneWidget);
    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.text('2.0 КБ'), findsOneWidget); // 2048 ≥ 1024
    expect(find.textContaining('1.0 МБ'), findsOneWidget);
    // Счётчик 2.
    expect(find.text('2'), findsOneWidget);
    // Иконки: BookOpen для epub, FileText для pdf.
    expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget);
    expect(find.byIcon(LucideIcons.fileText), findsOneWidget);
  });

  testWidgets('удаление: confirm (danger) → DELETE → тост', (tester) async {
    late ProviderContainer container;
    container = await pumpFiles(
      tester,
      attachments: attachments(),
      stubBuilder: (stub) => StubAdapter((options) {
        if (options.method == 'DELETE' &&
            options.path.contains('/api/media/m1/files/f1')) {
          return jsonBody([
            {'id': 'f2', 'fileName': 'scan.pdf', 'fileSizeBytes': 1048576, 'addedAt': '2024-01-02T00:00:00Z'},
          ]);
        }
        return jsonBody([]);
      }),
    );

    await tester.tap(find.bySemanticsLabel('Удалить файл').first);
    await tester.pumpAndSettle();

    // Confirm-модалка: danger-диалог.
    expect(find.textContaining('Удалить файл «book.epub»'), findsOneWidget);
    await tester.tap(find.text('Удалить')); // confirmLabel = common.delete
    await tester.pumpAndSettle();

    expect(
        container.read(toastStoreProvider).any((t) =>
            t.title == 'Файл удалён'),
        isTrue);
  });
}
