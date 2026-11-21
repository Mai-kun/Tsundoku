import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/trailer_section.dart';

/// Тесты `TrailerSection.svelte`: превью с Play, отсутствие трейлера →
/// заглушка.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpWithTrailer(WidgetTester tester, String videoId) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: TrailerSection(trailerVideoId: videoId, title: 'Тайтл'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('без трейлера: заглушка «Трейлер не найден» + иконка Film',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: const MaterialApp(
        home: Material(
          child: TrailerSection(trailerVideoId: null, title: 'Тайтл'),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Трейлер не найден'), findsOneWidget);
    expect(find.byIcon(LucideIcons.film), findsOneWidget);
    expect(find.byIcon(LucideIcons.play), findsNothing);
  });

  testWidgets('с трейлером: Play-кнопка + подпись «Трейлер»', (tester) async {
    await pumpWithTrailer(tester, 'dQw4w9WgXcQ');

    expect(find.byIcon(LucideIcons.play), findsOneWidget);
    expect(find.text('Трейлер'), findsOneWidget);
    // Thumbnail YouTube (img.youtube.com) — Image.network присутствует.
    final images =
        tester.widgetList<Image>(find.byType(Image)).toList();
    expect(
      images.any((img) =>
          img.image is NetworkImage &&
          (img.image as NetworkImage).url.contains('img.youtube.com')),
      isTrue,
    );
  });

  testWidgets('tap Play → тап не роняет дерево (URL уходит в фасад #48)',
      (tester) async {
    await pumpWithTrailer(tester, 'dQw4w9WgXcQ');
    await tester.tap(find.byIcon(LucideIcons.play));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
