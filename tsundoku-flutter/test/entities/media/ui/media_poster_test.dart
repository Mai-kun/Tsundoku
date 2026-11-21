import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/entities/media/ui/media_poster.dart';
import 'package:tsundoku_flutter/entities/media/ui/placeholder404.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';

/// Фиксированный baseUrl: порт 1 → мгновенный отказ соединения (детерминированная
/// ошибка загрузки обложки в тестах).
class _RefusedBaseUrl extends ApiBaseUrlController {
  @override
  String build() => 'http://127.0.0.1:1';
}

/// Widget-тесты `MediaPoster.svelte`: ветка плейсхолдера, onerror-fallback,
/// syncing-оверлей, needsReview → jobsClient.openModal(review), слоты
/// badges/actions.
void main() {
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    String? src = '/media-assets/x/thumb.webp',
    bool syncing = false,
    bool needsReview = false,
    Key? badgesKey,
    Key? actionsKey,
  }) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SizedBox(
          width: 200,
          height: 300,
          child: MediaPoster(
            src: src,
            alt: 'Тестовое название',
            syncing: syncing,
            needsReview: needsReview,
            badges: badgesKey != null ? SizedBox(key: badgesKey) : null,
            actions: actionsKey != null ? SizedBox(key: actionsKey) : null,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  setUp(() {
    container = ProviderContainer(overrides: [
      apiBaseUrlProvider.overrideWith(_RefusedBaseUrl.new),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('src null → Placeholder404', (tester) async {
    await pump(tester, src: null);
    expect(find.byType(Placeholder404), findsOneWidget);
  });

  testWidgets('внешний URL без прокси → Placeholder404 (1-в-1: only /)',
      (tester) async {
    await pump(tester, src: 'https://cdn.example/cover.jpg');
    expect(find.byType(Placeholder404), findsOneWidget);
  });

  testWidgets('server-relative src при ошибке загрузки → Placeholder404 '
      '(onerror, не retry-loop)', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(Placeholder404), findsOneWidget);
  });

  testWidgets('syncing → спиннер + «Синхронизация»', (tester) async {
    await pump(tester, syncing: true);
    expect(find.text('Синхронизация'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('needsReview: тап → jobsClient.openModal(review)',
      (tester) async {
    await pump(tester, needsReview: true);
    await tester.tap(find.text('Уточнить'));
    await tester.pump();

    final jobs = container.read(jobsClientProvider);
    expect(jobs.isModalOpen, isTrue);
    expect(jobs.modalTab, JobsModalTab.review);
  });

  testWidgets('слоты badges/actions рендерятся в постере', (tester) async {
    await pump(tester, badgesKey: const Key('badges'), actionsKey: const Key('actions'));
    expect(find.byKey(const Key('badges')), findsOneWidget);
    expect(find.byKey(const Key('actions')), findsOneWidget);
  });
}
