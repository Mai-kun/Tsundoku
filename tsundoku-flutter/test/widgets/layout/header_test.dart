import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/offline_mode.dart';
import 'dart:convert';

import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/ui/button.dart';
import 'package:tsundoku_flutter/widgets/layout/header.dart';

class _NoopJobs extends JobsClientController {
  @override
  void connect() {}
}

/// Widget-тесты `Header.svelte`: заголовок, центральный поиск (шторка sm),
/// офлайн-бейдж, селектор языка, Power, спиннер обновления.
void main() {
  late ProviderContainer container;
  var searched = 0;
  var exited = 0;

  Future<void> pumpHeader(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    searched = 0;
    exited = 0;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 64,
            child: Header(
              title: 'Аниме',
              onSearch: () => searched += 1,
              onExitClick: () => exited += 1,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  setUp(() {
    container = ProviderContainer(overrides: [
      jobsClientProvider.overrideWith(_NoopJobs.new),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('рендерит заголовок, поиск с Ctrl K, язык RU, Power',
      (tester) async {
    await pumpHeader(tester);
    expect(find.text('Аниме'), findsOneWidget);
    expect(find.text('Поиск тайтлов'), findsOneWidget);
    expect(find.text('Ctrl K'), findsOneWidget);
    expect(find.text('RU'), findsOneWidget);
    expect(find.byIcon(LucideIcons.power), findsOneWidget);
    expect(find.byIcon(LucideIcons.languages), findsOneWidget);
  });

  testWidgets('тап по поиску → onSearch', (tester) async {
    await pumpHeader(tester);
    await tester.tap(find.text('Поиск тайтлов'));
    expect(searched, 1);
  });

  testWidgets('тап по Power → onExitClick', (tester) async {
    await pumpHeader(tester);
    await tester.tap(find.byIcon(LucideIcons.power));
    expect(exited, 1);
  });

  testWidgets('офлайн-режим → amber-бейдж «Офлайн»', (tester) async {
    container.read(offlineModeProvider.notifier).refresh(
        OfflineModeResponse.fromJson({'offlineMode': true, 'hasDatabases': false}));
    await pumpHeader(tester);
    expect(find.text('Офлайн'), findsOneWidget);
    expect(find.byIcon(LucideIcons.cloudOff), findsOneWidget);
  });

  testWidgets('активные задачи → спиннер обновления', (tester) async {
    container.read(jobsClientProvider.notifier).applyJson(jsonEncode({
      'jobId': 'j1',
      'title': 'T',
      'progressPercent': 10,
      'currentStep': 'step',
      'status': 'Running',
      'startedAt': '2024-01-01T00:00:00Z',
    }));
    await pumpHeader(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Таймеры задач гасим до teardown.
    container.read(jobsClientProvider.notifier).disconnect();
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('селектор языка: выбор EN → локаль меняется', (tester) async {
    await pumpHeader(tester);
    // Триггер языка — текст RU.
    await tester.tap(find.text('RU'));
    await tester.pump(const Duration(milliseconds: 300));
    // Поповер: опции RU/EN.
    expect(find.text('EN'), findsWidgets);
    // Выбор EN (опция в поповере — вторая находка).
    final enFinder = find.widgetWithText(GestureDetector, 'EN');
    await tester.tap(enFinder.last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(i18nProvider).wire, 'en');
  });

  testWidgets('компактный (<640px) → icon-only поиск', (tester) async {
    await pumpHeader(tester, size: const Size(500, 900));
    // Полная кнопка скрыта, иконка остаётся.
    expect(find.text('Поиск тайтлов'), findsNothing);
    expect(find.byIcon(LucideIcons.search), findsOneWidget);
    // Тап по иконке → onSearch (hover не нужен: icon-only кнопка).
    final center = tester.getCenter(find.byIcon(LucideIcons.search));
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(LucideIcons.search));
    expect(searched, 1);
  });

  testWidgets('поиск в Header имеет высоту 36px без нижнего падинга в Tooltip',
      (tester) async {
    await pumpHeader(tester);
    final searchButtonFinder = find.ancestor(
      of: find.text('Поиск тайтлов'),
      matching: find.byType(TsundokuButton),
    );
    final searchTooltipFinder = find.ancestor(
      of: searchButtonFinder,
      matching: find.byType(Tooltip),
    );
    final buttonRect = tester.getRect(searchButtonFinder);
    final tooltipRect = tester.getRect(searchTooltipFinder);
    expect(buttonRect.height, 36.0);
    expect(tooltipRect.height, 36.0);
    expect(tooltipRect.bottom, buttonRect.bottom);
  });
}
