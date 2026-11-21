import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/movie_form_fields.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  testWidgets('MovieFormFields: длительность/студия + чекбокс аниме',
      (tester) async {
    String? duration;
    bool? anime;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 620,
            child: MovieFormFields(
              durationMinutes: '90',
              studio: '',
              isAnime: false,
              onDurationMinutesChange: (v) => duration = v,
              onStudioChange: (_) {},
              onIsAnimeChange: (v) => anime = v,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Длительность (мин.)'), findsOneWidget);
    expect(find.text('Студия'), findsWidgets);
    expect(find.text('Это аниме?'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '90'), '120');
    await tester.pump();
    expect(duration, '120');

    await tester.tap(find.text('Это аниме?'));
    await tester.pump();
    expect(anime, isTrue);
  });
}
