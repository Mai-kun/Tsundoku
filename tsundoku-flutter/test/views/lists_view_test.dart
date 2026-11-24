import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/confirm_modal.dart';
import 'package:tsundoku_flutter/views/lists_view.dart';
import 'package:tsundoku_flutter/widgets/layout/toast_container.dart';

MediaItem _makeItem({
  required String id,
  required String title,
  MediaType type = MediaType.tvshow,
  MediaStatus status = MediaStatus.completed,
}) {
  return MediaItem.fromJson(<String, dynamic>{
    'id': id,
    'type': type.wire,
    'title': title,
    'status': status.value,
    'source': 'manual',
    'createdAt': '2024-01-01T00:00:00Z',
    'updatedAt': '2024-01-01T00:00:00Z',
  });
}

List<CustomListSummary> _sampleLists() {
  return [
    const CustomListSummary(
      id: 'list-1',
      name: 'Избранное аниме',
      description: 'Любимые сериалы и фильмы',
      icon: 'star',
      color: '#f59e0b',
      itemsCount: 2,
      updatedAt: '2024-05-15T12:00:00Z',
      previewCovers: ['/c1.jpg', '/c2.jpg'],
      isSmart: false,
      smartQueryJson: null,
    ),
    const CustomListSummary(
      id: 'list-2',
      name: 'Умный топ',
      description: 'Автоматический список лучших тайтлов',
      icon: 'sparkles',
      color: '#8b5cf6',
      itemsCount: 1,
      updatedAt: '2024-05-16T12:00:00Z',
      previewCovers: [],
      isSmart: true,
      smartQueryJson: '{"categories":["anime"],"minScore":8,"maxEpisodes":24}',
    ),
  ];
}

CustomListDetail _sampleDetail(String id) {
  if (id == 'list-2') {
    return CustomListDetail(
      id: 'list-2',
      name: 'Умный топ',
      description: 'Автоматический список лучших тайтлов',
      icon: 'sparkles',
      color: '#8b5cf6',
      createdAt: '2024-05-16T12:00:00Z',
      items: [
        _makeItem(id: 'm3', title: 'Sousou no Frieren'),
      ],
      isSmart: true,
      smartQueryJson: '{"categories":["anime"],"minScore":8,"maxEpisodes":24}',
    );
  }
  return CustomListDetail(
    id: 'list-1',
    name: 'Избранное аниме',
    description: 'Любимые сериалы и фильмы',
    icon: 'star',
    color: '#f59e0b',
    createdAt: '2024-05-15T12:00:00Z',
    items: [
      _makeItem(id: 'm1', title: 'Steins;Gate'),
      _makeItem(id: 'm2', title: 'Fullmetal Alchemist'),
    ],
    isSmart: false,
    smartQueryJson: null,
  );
}

class _StubListsApi extends TsundokuApi {
  final Future<List<CustomListSummary>> Function()? onGetLists;
  final Future<CustomListDetail> Function(String id)? onGetListDetail;
  final Future<void> Function(String id)? onDeleteList;
  final Future<void> Function(String listId, String mediaId)?
      onRemoveMediaFromList;

  _StubListsApi({
    this.onGetLists,
    this.onGetListDetail,
    this.onDeleteList,
    this.onRemoveMediaFromList,
  }) : super(Dio());

  @override
  Future<List<CustomListSummary>> getLists() {
    if (onGetLists != null) return onGetLists!();
    return Future.value(_sampleLists());
  }

  @override
  Future<CustomListDetail> getListDetail(String id) {
    if (onGetListDetail != null) return onGetListDetail!(id);
    return Future.value(_sampleDetail(id));
  }

  @override
  Future<void> deleteList(String id) {
    if (onDeleteList != null) return onDeleteList!(id);
    return Future.value();
  }

  @override
  Future<void> removeMediaFromList(String listId, String mediaId) {
    if (onRemoveMediaFromList != null) {
      return onRemoveMediaFromList!(listId, mediaId);
    }
    return Future.value();
  }
}

Future<void> _pumpListsView(
  WidgetTester tester, {
  TsundokuApi? api,
  ValueChanged<MediaItem>? onOpen,
  void Function(CustomListSummary? list)? onOpenCreateList,
  VoidCallback? onOpenImport,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api ?? _StubListsApi()),
        tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
      ],
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: Stack(
            children: [
              ListsView(
                onOpen: onOpen,
                onOpenCreateList: onOpenCreateList,
                onOpenImport: onOpenImport,
              ),
              const ConfirmModal(),
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

  testWidgets('renders empty state when there are no lists', (tester) async {
    CustomListSummary? createdList;
    final api = _StubListsApi(onGetLists: () => Future.value(const []));

    await _pumpListsView(
      tester,
      api: api,
      onOpenCreateList: (l) => createdList = l,
    );

    expect(find.text('Создайте свою первую коллекцию'), findsOneWidget);
    expect(find.text('Создать первый список'), findsOneWidget);

    await tester.tap(find.text('Создать первый список'));
    await tester.pumpAndSettle();
    expect(createdList, isNull);
  });

  testWidgets('renders gallery of lists with titles, counts and smart badges',
      (tester) async {
    await _pumpListsView(tester);

    expect(find.text('Списки'), findsOneWidget);
    expect(find.text('МЕДИАТЕКА'), findsOneWidget);
    expect(find.text('Избранное аниме'), findsOneWidget);
    expect(find.text('Умный топ'), findsOneWidget);

    // Smart list badge
    expect(find.text('⚡ Умный'), findsOneWidget);
    expect(find.text('anime'), findsOneWidget);
    expect(find.text('★8+'), findsOneWidget);
    expect(find.text('≤24 эп.'), findsOneWidget);
  });

  testWidgets('clicking a list card opens list detail and shows media grid',
      (tester) async {
    MediaItem? openedItem;
    await _pumpListsView(
      tester,
      onOpen: (item) => openedItem = item,
    );

    // Click on "Избранное аниме" card
    await tester.tap(find.text('Избранное аниме'));
    await tester.pumpAndSettle();

    // In detail view: shows back button and list items
    expect(find.text('Назад к спискам'), findsOneWidget);
    expect(find.text('Steins;Gate'), findsOneWidget);
    expect(find.text('Fullmetal Alchemist'), findsOneWidget);

    // Clicking an item calls onOpen
    await tester.tap(find.text('Steins;Gate'));
    await tester.pumpAndSettle();
    expect(openedItem?.title, 'Steins;Gate');

    // Clicking back button returns to gallery
    await tester.tap(find.text('Назад к спискам'));
    await tester.pumpAndSettle();
    expect(find.text('МЕДИАТЕКА'), findsOneWidget);
  });

  testWidgets('smart list detail view shows smart rules banner', (tester) async {
    await _pumpListsView(tester);

    // Click on "Умный топ" card
    await tester.tap(find.text('Умный топ'));
    await tester.pumpAndSettle();

    expect(find.text('Sousou no Frieren'), findsOneWidget);
    expect(find.text('Изменить правила'), findsOneWidget);
    expect(find.text('⚡ Умный'), findsOneWidget);
  });

  testWidgets('deleting a list shows confirmation dialog and removes it',
      (tester) async {
    var deletedListId = '';
    final api = _StubListsApi(
      onDeleteList: (id) async {
        deletedListId = id;
      },
    );

    await _pumpListsView(tester, api: api);

    // Find delete button on card (LucideIcons.trash2)
    final deleteButtons = find.byIcon(LucideIcons.trash2);
    expect(deleteButtons, findsWidgets);

    await tester.tap(deleteButtons.first);
    await tester.pumpAndSettle();

    // Confirm dialog is shown
    expect(find.textContaining('Удалить список «Избранное аниме»?'),
        findsOneWidget);

    // Tap confirm button
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(deletedListId, 'list-1');
  });

  testWidgets('import button triggers onOpenImport', (tester) async {
    var importTriggered = false;
    await _pumpListsView(
      tester,
      onOpenImport: () => importTriggered = true,
    );

    final importBtn = find.text('Начать импорт');
    expect(importBtn, findsOneWidget);
    await tester.tap(importBtn);
    await tester.pumpAndSettle();

    expect(importTriggered, isTrue);
  });

  testWidgets('error state shows error message and retry button',
      (tester) async {
    var retried = false;
    final api = _StubListsApi(
      onGetLists: () {
        if (!retried) {
          throw Exception('Failed to load lists');
        }
        return Future.value(_sampleLists());
      },
    );

    await _pumpListsView(tester, api: api);

    expect(find.text('Повторить'), findsOneWidget);

    retried = true;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.text('Избранное аниме'), findsOneWidget);
  });

  testWidgets(
      'removing an item from a list optimistically removes it and calls removeMediaFromList',
      (tester) async {
    String? removedListId;
    String? removedMediaId;
    final items = [
      _makeItem(id: 'm1', title: 'Steins;Gate'),
      _makeItem(id: 'm2', title: 'Fullmetal Alchemist'),
    ];
    final api = _StubListsApi(
      onGetListDetail: (id) => Future.value(CustomListDetail(
        id: 'list-1',
        name: 'Избранное аниме',
        description: null,
        icon: 'star',
        color: '#f59e0b',
        createdAt: '2024-05-15T12:00:00Z',
        items: List.of(items),
        isSmart: false,
        smartQueryJson: null,
      )),
      onRemoveMediaFromList: (listId, mediaId) async {
        removedListId = listId;
        removedMediaId = mediaId;
        items.removeWhere((i) => i.id == mediaId);
      },
    );

    await _pumpListsView(tester, api: api);

    // Open "Избранное аниме"
    await tester.tap(find.text('Избранное аниме'));
    await tester.pumpAndSettle();

    expect(find.text('Steins;Gate'), findsOneWidget);
    expect(find.text('Fullmetal Alchemist'), findsOneWidget);

    // Tap remove button (X) on Steins;Gate card
    final removeBtn = find.byIcon(LucideIcons.x).first;
    await tester.tap(removeBtn);
    await tester.pumpAndSettle();

    expect(removedListId, 'list-1');
    expect(removedMediaId, 'm1');
    expect(find.text('Steins;Gate'), findsNothing);
    expect(find.text('Fullmetal Alchemist'), findsOneWidget);
  });

  testWidgets(
      'empty state create button opens CreateListModal even inside SingleChildScrollView',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _StubListsApi(onGetLists: () => Future.value(const []));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tProvider.overrideWithValue(const I18nDictionary(Locale.ru)),
        ],
        child: MaterialApp(
          theme: buildTsundokuTheme(),
          home: const Material(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: ListsView(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать первый список'));
    await tester.pumpAndSettle();

    expect(find.text('Создать список'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
