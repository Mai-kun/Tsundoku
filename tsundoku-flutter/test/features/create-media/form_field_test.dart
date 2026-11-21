import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/create-media/form_field.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';

void main() {
  testWidgets('FormField: лейбл + контрол (space-y-1.5)', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: const Material(
          child: TsundokuFormField(
            label: 'Название',
            child: Text('Контрол'),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Название'), findsOneWidget);
    expect(find.text('Контрол'), findsOneWidget);
  });
}
