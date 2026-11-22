import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/stats/taste-profile/taste_persona_card.dart';

Future<void> pumpTastePersonaCard(
  WidgetTester tester, {
  required TastePersona persona,
  Locale locale = Locale.ru,
  double width = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        i18nProvider.overrideWith(() => _FixedLocaleController(locale)),
        tProvider.overrideWithValue(I18nDictionary(locale)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: TastePersonaCard(persona: persona),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _FixedLocaleController extends I18nController {
  final Locale fixed;
  _FixedLocaleController(this.fixed);

  @override
  Locale build() => fixed;
}

void main() {
  testWidgets('известная персона (critic): иконка, локализованные тексты и черты',
      (tester) async {
    const persona = TastePersona(
      icon: 'critic',
      title: 'Fallback Critic',
      description: 'Fallback Description',
      traits: ['Fallback 1'],
    );

    await pumpTastePersonaCard(tester, persona: persona);

    // Иконка scale
    expect(find.byIcon(LucideIcons.scale), findsOneWidget);

    // Бейдж
    expect(find.text('АРХЕТИП ВКУСА'), findsOneWidget);

    // Локализованный заголовок
    expect(find.text('Строгий критик'), findsOneWidget);

    // Локализованное описание
    expect(
      find.textContaining('Вы держите свою медиатеку на самых высоких стандартах'),
      findsOneWidget,
    );

    // Черты
    expect(find.text('Высокие стандарты'), findsOneWidget);
    expect(find.text('Честные оценки'), findsOneWidget);
    expect(find.text('Неподкупный вкус'), findsOneWidget);
  });

  testWidgets('неизвестная персона: фолбэк на свойства модели и дефолтную иконку',
      (tester) async {
    const persona = TastePersona(
      icon: 'unknown_alien',
      title: 'Космический странник',
      description: 'Исследует неизведанные уголки медиапространства.',
      traits: ['all_formats', 'Необычная черта'],
    );

    await pumpTastePersonaCard(tester, persona: persona);

    // Дефолтная иконка sparkles
    expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);

    expect(find.text('Космический странник'), findsOneWidget);
    expect(
      find.text('Исследует неизведанные уголки медиапространства.'),
      findsOneWidget,
    );

    // all_formats локализуется через stats.taste.traits.all_formats ('Все форматы')
    expect(find.text('Все форматы'), findsOneWidget);
    // Неизвестная черта проходит как есть
    expect(find.text('Необычная черта'), findsOneWidget);
  });

  testWidgets('английская локаль: все тексты на английском', (tester) async {
    const persona = TastePersona(
      icon: 'critic',
      title: 'Fallback Critic',
      description: 'Fallback Description',
      traits: ['Fallback 1'],
    );

    await pumpTastePersonaCard(
      tester,
      persona: persona,
      locale: Locale.en,
    );

    expect(find.text('TASTE ARCHETYPE'), findsOneWidget);
    expect(find.text('Strict Critic'), findsOneWidget);
    expect(
      find.textContaining('You hold your library to sky-high standards'),
      findsOneWidget,
    );
    expect(find.text('High standards'), findsOneWidget);
    expect(find.text('Honest reviews'), findsOneWidget);
    expect(find.text('Uncompromising taste'), findsOneWidget);
  });

  testWidgets('адаптивный мобильный рендеринг', (tester) async {
    const persona = TastePersona(
      icon: 'gamer',
      title: 'Геймер',
      description: 'Описание геймера',
      traits: ['Гейминг'],
    );

    await pumpTastePersonaCard(tester, persona: persona, width: 360);

    expect(find.byIcon(LucideIcons.gamepad2), findsOneWidget);
    expect(find.text('АРХЕТИП ВКУСА'), findsOneWidget);
  });
}
