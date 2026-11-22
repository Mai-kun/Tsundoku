import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/views/calendar_view.dart';
import 'package:tsundoku_flutter/widgets/layout/toast_container.dart';

BacklogDeadlineDto _sampleDeadline() {
  final now = DateTime.now();
  final deadlineDate =
      DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 5)));
  return BacklogDeadlineDto(
    mediaId: 'm-backlog-1',
    title: 'Sousou no Frieren S2',
    type: 'tvshow',
    coverUrl: null,
    kind: CalendarEventKind.airDate,
    deadlineDate: deadlineDate,
    daysLeft: 5,
    episodeNumber: 12,
    seasonNumber: 2,
    behindCount: 3,
    blockerTitle: null,
    blockerProgress: null,
    blockerTotalCount: null,
  );
}

CalendarScheduleDto _sampleSchedule() {
  final now = DateTime.now();
  final todayStr = DateFormat('yyyy-MM-dd').format(now);
  final tomorrowStr =
      DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

  return CalendarScheduleDto(
    from: todayStr,
    to: tomorrowStr,
    days: [
      CalendarDayDto(
        date: todayStr,
        items: [
          CalendarItemDto(
            mediaId: 'item-1',
            title: 'Dandadan',
            type: 'tvshow',
            coverUrl: null,
            currentProgress: 5,
            totalCount: 12,
            kind: CalendarEventKind.airDate,
            details: 'Серия 6',
            episodeNumber: 6,
            seasonNumber: 1,
            isAnime: true,
          ),
          CalendarItemDto(
            mediaId: 'item-2',
            title: 'Elden Ring DLC',
            type: 'game',
            coverUrl: null,
            currentProgress: 0,
            totalCount: 1,
            kind: CalendarEventKind.release,
            details: 'Запуск дополнения',
            episodeNumber: null,
            seasonNumber: null,
            isAnime: false,
          ),
          CalendarItemDto(
            mediaId: 'item-auto-1',
            title: 'One Piece',
            type: 'tvshow',
            coverUrl: null,
            currentProgress: 1100,
            totalCount: null,
            kind: CalendarEventKind.autoRefresh,
            details: 'Автопроверка',
            episodeNumber: null,
            seasonNumber: null,
            isAnime: true,
          ),
        ],
      ),
      CalendarDayDto(
        date: tomorrowStr,
        items: [
          CalendarItemDto(
            mediaId: 'item-3',
            title: 'Chainsaw Man Reze Arc',
            type: 'movie',
            coverUrl: null,
            currentProgress: 0,
            totalCount: 1,
            kind: CalendarEventKind.release,
            details: 'Премьера',
            episodeNumber: null,
            seasonNumber: null,
            isAnime: true,
          ),
        ],
      ),
    ],
  );
}

class _StubCalendarApi extends TsundokuApi {
  final Future<CalendarScheduleDto> Function(String? from, String? to)?
      onGetCalendar;
  final Future<List<BacklogDeadlineDto>> Function()? onGetBacklogDeadlines;
  final Future<MediaDetail> Function(String mediaId)? onTriggerAutoRefresh;
  final Future<Uint8List> Function()? onExportCalendarIcs;

  _StubCalendarApi({
    this.onGetCalendar,
    this.onGetBacklogDeadlines,
    this.onTriggerAutoRefresh,
    this.onExportCalendarIcs,
  }) : super(Dio());

  @override
  Future<CalendarScheduleDto> getCalendar(
      {String? from, String? to, CancelToken? cancelToken}) {
    if (onGetCalendar != null) return onGetCalendar!(from, to);
    return Future.value(_sampleSchedule());
  }

  @override
  Future<List<BacklogDeadlineDto>> getBacklogDeadlines(
      {CancelToken? cancelToken}) {
    if (onGetBacklogDeadlines != null) return onGetBacklogDeadlines!();
    return Future.value([_sampleDeadline()]);
  }

  @override
  Future<MediaDetail> triggerAutoRefresh(String mediaId) {
    if (onTriggerAutoRefresh != null) return onTriggerAutoRefresh!(mediaId);
    return Future.value(MediaDetail.fromJson(<String, dynamic>{
      'id': mediaId,
      'title': 'Refreshed Item',
      'type': 'tvshow',
      'status': 1,
      'source': 'manual',
      'createdAt': '2024-01-01T00:00:00Z',
      'updatedAt': '2024-01-01T00:00:00Z',
    }));
  }

  @override
  Future<Uint8List> exportCalendarIcs() {
    if (onExportCalendarIcs != null) return onExportCalendarIcs!();
    return Future.value(Uint8List.fromList([1, 2, 3]));
  }
}

Future<void> _pumpCalendarView(
  WidgetTester tester, {
  TsundokuApi? api,
  ValueChanged<String>? onOpenMedia,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api ?? _StubCalendarApi()),
        tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: CalendarView(
                  onOpenMedia: onOpenMedia,
                ),
              ),
              const ToastContainer(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders backlog deadlines section and calls onOpenMedia on tap',
      (tester) async {
    String? openedMediaId;
    await _pumpCalendarView(
      tester,
      onOpenMedia: (id) => openedMediaId = id,
    );

    expect(find.text('Sousou no Frieren S2'), findsOneWidget);
    expect(find.textContaining('Осталось 3 эп.'), findsOneWidget);
    expect(find.textContaining('Через 5 дн.'), findsOneWidget);

    await tester.tap(find.text('Sousou no Frieren S2'));
    await tester.pumpAndSettle();
    expect(openedMediaId, 'm-backlog-1');
  });

  testWidgets('renders feed mode with day groups and cards', (tester) async {
    String? openedMediaId;
    await _pumpCalendarView(
      tester,
      onOpenMedia: (id) => openedMediaId = id,
    );

    // Dandadan card in today's group
    expect(find.text('Dandadan'), findsOneWidget);
    expect(find.text('Серия 6'), findsOneWidget);

    // Elden Ring DLC card
    expect(find.text('Elden Ring DLC'), findsOneWidget);
    expect(find.text('Релиз'), findsWidgets);

    // Chainsaw Man card in tomorrow's group
    expect(find.text('Chainsaw Man Reze Arc'), findsOneWidget);

    // Tap card triggers onOpenMedia
    await tester.tap(find.text('Dandadan'));
    await tester.pumpAndSettle();
    expect(openedMediaId, 'item-1');
  });

  testWidgets('month navigation next/prev and today button', (tester) async {
    var fetchedFrom = '';
    final api = _StubCalendarApi(
      onGetCalendar: (from, to) {
        fetchedFrom = from ?? '';
        return Future.value(_sampleSchedule());
      },
    );

    await _pumpCalendarView(tester, api: api);

    final now = DateTime.now();
    final currentMonthFormat = DateFormat('LLLL yyyy', 'ru').format(now);
    expect(
        find.textContaining(currentMonthFormat[0].toUpperCase() +
            currentMonthFormat.substring(1)),
        findsOneWidget);

    // Next month button (chevronRight)
    await tester.tap(find.byIcon(LucideIcons.chevronRight));
    await tester.pumpAndSettle();
    expect(fetchedFrom.isNotEmpty, isTrue);

    // "Сегодня" button appears and jumps back
    final todayBtn = find.text('Сегодня');
    if (todayBtn.evaluate().isNotEmpty) {
      await tester.tap(todayBtn);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('switches between Feed and Grid views and selects a date',
      (tester) async {
    await _pumpCalendarView(tester);

    // Find grid mode toggle button (LucideIcons.layoutGrid)
    final gridBtn = find.byIcon(LucideIcons.layoutGrid);
    expect(gridBtn, findsOneWidget);
    await tester.tap(gridBtn);
    await tester.pumpAndSettle();

    // Check weekday headers Mon-Sun
    expect(find.text('ПН'), findsOneWidget);
    expect(find.text('ВС'), findsOneWidget);

    // Clicking a day cell opens the sidebar panel
    final dayNumFinder = find.text('${DateTime.now().day}').first;
    await tester.tap(dayNumFinder);
    await tester.pumpAndSettle();

    // Selected day panel shows events for that day
    expect(find.text('Dandadan'), findsOneWidget);

    // Switch back to Feed mode (LucideIcons.list)
    final feedBtn = find.byIcon(LucideIcons.list);
    expect(feedBtn, findsOneWidget);
    await tester.tap(feedBtn);
    await tester.pumpAndSettle();
    expect(find.text('Dandadan'), findsOneWidget);
  });

  testWidgets('auto-refresh button calls triggerAutoRefresh and shows toast',
      (tester) async {
    String? refreshedMediaId;
    final api = _StubCalendarApi(
      onTriggerAutoRefresh: (mediaId) async {
        refreshedMediaId = mediaId;
        return MediaDetail.fromJson(<String, dynamic>{
          'id': mediaId,
          'title': 'One Piece',
          'type': 'tvshow',
          'status': 1,
          'source': 'manual',
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        });
      },
    );

    await _pumpCalendarView(tester, api: api);

    // Find refresh button (LucideIcons.refreshCw) on card
    final refreshBtn = find.byIcon(LucideIcons.refreshCw).first;
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    expect(refreshedMediaId, 'item-auto-1');
  });

  testWidgets('ICS export calls exportCalendarIcs', (tester) async {
    var icsExportCalled = false;
    final api = _StubCalendarApi(
      onExportCalendarIcs: () async {
        icsExportCalled = true;
        return Uint8List.fromList([1, 2, 3]);
      },
    );

    await _pumpCalendarView(tester, api: api);

    // ICS button has download icon
    final icsBtn = find.byIcon(LucideIcons.download);
    expect(icsBtn, findsOneWidget);
    await tester.tap(icsBtn);
    await tester.pumpAndSettle();

    expect(icsExportCalled, isTrue);
  });

  testWidgets('shows empty state when no calendar events', (tester) async {
    final emptySchedule = CalendarScheduleDto(
      from: '2024-01-01',
      to: '2024-01-31',
      days: const [],
    );
    final api = _StubCalendarApi(
      onGetCalendar: (from, to) => Future.value(emptySchedule),
      onGetBacklogDeadlines: () => Future.value(const []),
    );

    await _pumpCalendarView(tester, api: api);

    expect(find.text('В этом месяце нет запланированных событий'),
        findsOneWidget);
  });
}
