import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/game_form_fields.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  testWidgets('GameFormFields: платформа + часы, bindable-ввод',
      (tester) async {
    String? platform;
    String? hours;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SizedBox(
            width: 620,
            child: GameFormFields(
              platform: 'PC',
              hoursPlayed: '120',
              onPlatformChange: (v) => platform = v,
              onHoursPlayedChange: (v) => hours = v,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Платформа'), findsOneWidget);
    expect(find.text('Часы'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'PC'), findsOneWidget);
    expect(find.widgetWithText(TextField, '120'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'PC'), 'Switch');
    await tester.pump();
    expect(platform, 'Switch');
    await tester.enterText(find.widgetWithText(TextField, '120'), '130');
    await tester.pump();
    expect(hours, '130');
  });
}
