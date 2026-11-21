import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/navigation_categories.dart';
import 'package:tsundoku_flutter/widgets/layout/sidebar.dart';

/// Widget-тесты `Sidebar.svelte`: десктоп-колонка/мобильная рельса по ширине
/// окна (lg 1024), активная подсветка, tools-блок, onCreate.
class _StubNavCategories extends NavigationCategoriesController {
  @override
  List<PromotedSubcategory> build() => const [
        PromotedSubcategory(
          id: 'comics',
          label: 'Комиксы',
          icon: 'book-open',
          parentType: 'Book',
          matchKind: 'format',
          matchValue: 'comics',
        ),
      ];

  @override
  bool get isLoaded => true;

  @override
  Future<List<PromotedSubcategory>> loadNavigationCategories(
          {bool force = false}) async =>
      state;
}

void main() {
  late ProviderContainer container;
  final navigated = <String>[];
  var created = 0;

  Future<void> pumpSidebar(
    WidgetTester tester, {
    required String activeView,
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    navigated.clear();
    created = 0;
    // Десктоп: рельса-колонка 240px; мобайл: рельса на всю ширину окна.
    final isMobile = size.width < 1024;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: isMobile
              ? Align(
                  // Рельса прижата к низу (как в AppShell) — поповер
                  // инструментов открывается НАД ней.
                  alignment: Alignment.bottomCenter,
                  child: Sidebar(
                    activeView: activeView,
                    onNavigate: navigated.add,
                    onCreate: () => created += 1,
                  ),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 240,
                    child: Sidebar(
                      activeView: activeView,
                      onNavigate: navigated.add,
                      onCreate: () => created += 1,
                    ),
                  ),
                ),
        ),
      ),
    ));
    // Ленивая загрузка вынесенных категорий (postFrameCallback).
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer(overrides: [
      navigationCategoriesProvider.overrideWith(_StubNavCategories.new),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('десктоп: бренд, пункты навигации, инструменты', (tester) async {
    await pumpSidebar(tester, activeView: 'home', size: const Size(1440, 900));
    expect(find.text('Tsundoku'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Сериалы'), findsOneWidget);
    expect(find.text('Книги'), findsOneWidget);
    expect(find.text('Статистика'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    // Инструменты-лейбл uppercase.
    expect(find.text('ИНСТРУМЕНТЫ'), findsOneWidget);
  });

  testWidgets('активный пункт — «Главная»: onNavigate по клику', (tester) async {
    await pumpSidebar(tester, activeView: 'home', size: const Size(1440, 900));
    await tester.tap(find.text('Книги'));
    expect(navigated, ['book']);
    await tester.tap(find.text('Статистика'));
    expect(navigated, ['book', 'stats']);
  });

  testWidgets('onCreate вызывается по «Добавить медиа»', (tester) async {
    await pumpSidebar(tester, activeView: 'home', size: const Size(1440, 900));
    await tester.tap(find.text('Добавить медиа'));
    expect(created, 1);
    expect(navigated, isEmpty);
  });

  testWidgets('мобайл (500px): рельса иконок, tools-поповер по Menu',
      (tester) async {
    await pumpSidebar(tester, activeView: 'home', size: const Size(500, 900));
    // Лейблы скрыты (icons-only): текст пунктов навигации отсутствует.
    expect(find.text('Главная'), findsNothing);
    // Menu-кнопка есть.
    expect(find.byIcon(LucideIcons.menu), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();
    // Поповер инструментов открылся.
    expect(find.text('ИНСТРУМЕНТЫ'), findsOneWidget);
    expect(find.text('Статистика'), findsOneWidget);

    // Клик по «История» — навигация и закрытие поповера.
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(navigated, ['history']);
    expect(find.text('ИНСТРУМЕНТЫ'), findsNothing);
  });

  testWidgets('вынесенные категории рендерятся после родителя', (tester) async {
    // Конфиг подменён _StubNavCategories (comics → Book).
    await pumpSidebar(tester, activeView: 'comics', size: const Size(1440, 900));
    expect(find.text('Комиксы'), findsOneWidget);
    // Комиксы после «Книг» (порядок).
    final widgets = tester.widgetList<Text>(find.byType(Text)).toList();
    final bookIndex = widgets.indexWhere((w) => w.data == 'Книги');
    final comicsIndex = widgets.indexWhere((w) => w.data == 'Комиксы');
    expect(bookIndex, greaterThan(0));
    expect(comicsIndex, greaterThan(bookIndex));
  });
}
