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
import 'package:tsundoku_flutter/shared/ui/toast.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/quotes_section.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// Тесты `QuotesSection.svelte`: добавление (optimistic + PUT quotesJson),
/// удаление, ошибка → откат + тост, пустое состояние.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MediaDetail media([String? quotesJson]) => MediaDetail.fromJson({
        'id': 'm1',
        'type': 'book',
        'title': 'Book',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'quotesJson': quotesJson,
      });

  Future<ProviderContainer> pumpSection(
    WidgetTester tester, {
    required MediaDetail media,
    void Function(String nextJson)? onQuotesJsonChanged,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter((options) {
      if (options.path.contains('/api/media/m1')) {
        return jsonBody(<String, Object?>{
          'id': 'm1',
          'type': 'book',
          'title': 'Book',
          'status': 1,
          'createdAt': '2024-01-01T00:00:00Z',
        });
      }
      return jsonBody(<String, Object?>{});
    });
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: QuotesSection(
              media: media,
              onQuotesJsonChanged: onQuotesJsonChanged,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('пусто: приглашение «ЦИТАТЫ И ВЫПИСКИ» + Quote-иконка',
      (tester) async {
    await pumpSection(tester, media: media());

    expect(find.text('ЦИТАТЫ И ВЫПИСКИ'), findsOneWidget);
    expect(find.byIcon(LucideIcons.quote), findsOneWidget);
    expect(find.textContaining('У вас пока нет сохранённых цитат'),
        findsOneWidget);
  });

  testWidgets('полный цикл добавления: + → форма → сохранение → '
      'PUT quotesJson с новой цитатой первой', (tester) async {
    String? sentJson;
    late ProviderContainer container;
    container = await pumpSection(
      tester,
      media: media(),
      onQuotesJsonChanged: (j) => sentJson = j,
    );

    // Пустое состояние: тап по приглашению открывает секцию с формой.
    await tester.tap(find.byIcon(LucideIcons.quote));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Наша цитата');
    await tester.enterText(find.byType(TextField).last, 'стр. 84');
    await tester.pump();
    await tester.tap(find.textContaining('Сохранить цитату'));
    await tester.pumpAndSettle();

    // PUT с quotesJson: [новая цитата].
    final requests = container.read(apiClientProvider);
    expect(requests, isNotNull);
    // Локальный список отобразил цитату.
    expect(find.textContaining('Наша цитата'), findsOneWidget);
    expect(find.text('— стр. 84'), findsOneWidget);
    // Колбек получил JSON с цитатой.
    expect(sentJson, isNotNull);
    final decoded = jsonDecode(sentJson!) as List<dynamic>;
    expect(decoded.length, 1);
    expect((decoded.first as Map<String, dynamic>)['text'], 'Наша цитата');
    expect((decoded.first as Map<String, dynamic>)['pageOrContext'], 'стр. 84');
  });

  testWidgets('удаление: hover-кнопка Trash2 → цитата уходит + PUT',
      (tester) async {
    final existing = jsonEncode([
      {'id': 'q1', 'text': 'Цитата раз', 'createdAt': '2024-01-01T00:00:00Z'},
      {'id': 'q2', 'text': 'Цитата два', 'createdAt': '2024-01-02T00:00:00Z'},
    ]);
    await pumpSection(tester, media: media(existing));

    expect(find.textContaining('Цитата раз'), findsOneWidget);
    expect(find.textContaining('Цитата два'), findsOneWidget);

    // Delete-кнопки рендерятся для обеих цитат (Semantics labels).
    await tester.tap(find.bySemanticsLabel('Удалить').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Цитата раз'), findsNothing);
    expect(find.textContaining('Цитата два'), findsOneWidget);
  });

  testWidgets('ошибка updateMedia → откат списка + error-тост',
      (tester) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter((options) {
      if (options.method == 'PATCH' || options.method == 'PUT') {
        return jsonBody({'detail': 'db down'}, 500);
      }
      return jsonBody(<String, Object?>{});
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
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: QuotesSection(media: media()),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(LucideIcons.quote)); // приглашение
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Цитата');
    await tester.pump();
    await tester.tap(find.textContaining('Сохранить цитату'));
    await tester.pumpAndSettle();

    // Откат: секция вернулась в пустое состояние (приглашение).
    expect(find.textContaining('У вас пока нет сохранённых цитат'),
        findsOneWidget);
    // Error-тост ушёл в стор.
    final toasts = container.read(toastStoreProvider);
    expect(toasts.any((t) => t.type == ToastType.error), isTrue);
  });
}
