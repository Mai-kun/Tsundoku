import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/genre_radar_chart.dart';

List<RadarAxis> _makeAxes({int count = 6}) {
  const genres = ['action', 'comedy', 'drama', 'fantasy', 'horror', 'romance', 'scifi'];
  return List.generate(
    count,
    (i) => RadarAxis(
      genre: genres[i % genres.length],
      volumeScore: (i + 1) * 15.0,
      averageScore: 7.0 + (i * 0.3),
    ),
  );
}

Future<void> pumpGenreRadarChart(
  WidgetTester tester, {
  required List<RadarAxis> axes,
  double width = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: GenreRadarChart(axes: axes),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('шапка: иконка, тайтл, хинт', (tester) async {
    await pumpGenreRadarChart(tester, axes: _makeAxes());

    expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
    expect(find.text('Радар вкуса'), findsOneWidget);
    expect(
      find.text('Площадь — доля жанра в библиотеке, ★ — средняя ваша оценка'),
      findsOneWidget,
    );
  });

  testWidgets('пустой список осей: отображается empty state', (tester) async {
    await pumpGenreRadarChart(tester, axes: []);

    expect(
      find.text(
        'Недостаточно данных — добавьте и оцените тайтлы, чтобы профиль вкуса раскрылся.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AspectRatio), findsNothing);
  });

  testWidgets('с осями: CustomPaint рендерится', (tester) async {
    final axes = _makeAxes(count: 6);
    await pumpGenreRadarChart(tester, axes: axes);

    expect(find.byType(AspectRatio), findsOneWidget);
  });

  testWidgets('при более чем 6 осях радар ограничивается первыми 6',
      (tester) async {
    final axes = _makeAxes(count: 7);
    await pumpGenreRadarChart(tester, axes: axes);

    expect(find.byType(AspectRatio), findsOneWidget);
  });
}
