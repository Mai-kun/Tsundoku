/// Порт `mediatracker-ui/src/features/edit-media/EditMediaWorkspace.svelte`.
///
/// Пространственный workspace редактирования: полноэкранный диалог с
/// плавающими окнами-модулями (desktop ≥1024) или скролл-стеком (мобайл),
/// живыми нитями между обложкой и окнами, персистентной раскладкой и теми же
/// контрактами submit, что у обычной модалки (create/update).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:tsundoku_flutter/entities/media/model/cover_url.dart';
import 'package:tsundoku_flutter/features/edit-media/alt_titles_module.dart';
import 'package:tsundoku_flutter/features/edit-media/base_media_module.dart';
import 'package:tsundoku_flutter/features/edit-media/category_fields_module.dart';
import 'package:tsundoku_flutter/features/edit-media/images_module.dart';
import 'package:tsundoku_flutter/features/edit-media/module_types.dart';
import 'package:tsundoku_flutter/features/edit-media/notes_module.dart';
import 'package:tsundoku_flutter/features/edit-media/quotes_module.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_layout.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_threads.dart';
import 'package:tsundoku_flutter/features/edit-media/workspace_window.dart';
import 'package:tsundoku_flutter/features/prefetch-details/media_detail_prefetch.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/i18n/index.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_tokens.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_scroll.dart';
import 'package:tsundoku_flutter/shared/ui/media_cover_placeholder.dart';
import 'package:tsundoku_flutter/shared/ui/tsundoku_image.dart';

class EditMediaWorkspace extends ConsumerStatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final void Function(MediaItem media) onCreated;
  final MediaItem? editingItem;

  const EditMediaWorkspace({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onCreated,
    required this.editingItem,
  });

  @override
  ConsumerState<EditMediaWorkspace> createState() =>
      _EditMediaWorkspaceState();
}

class _EditMediaWorkspaceState extends ConsumerState<EditMediaWorkspace>
    with SingleTickerProviderStateMixin {
  // -------------------------------------------------------------------------
  // Draft-стейт. Пространственный канвас — чистая презентация; все поля живут
  // здесь и текут вниз в переиспользуемые модули.
  // -------------------------------------------------------------------------
  String _type = 'game'; // CreateType = MediaType wire
  String _title = '';
  String _coverUrl = '';
  String _notes = '';
  String _score = '';
  String _startedAt = '';
  String _finishedAt = '';
  MediaStatus _status = MediaStatus.planned;
  List<String> _altTitles = <String>[];
  List<QuoteDraft> _quotes = <QuoteDraft>[];
  List<MediaCoverItem> _covers = <MediaCoverItem>[];
  CategoryDraft _category = CategoryDraft.empty();
  bool _submitting = false;
  Object? _submitError;
  String _validationError = '';
  bool _editingInitialized = false;

  // -------------------------------------------------------------------------
  // Пространственный канвас: трекинг вьюпорта, персистентная раскладка,
  // z-стек.
  // -------------------------------------------------------------------------
  bool get _isDesktop =>
      MediaQuery.sizeOf(context).width >= 1024; // (min-width: 1024px)

  WorkspaceLayout _layout =
      defaultLayout(1600, 900); // начальная, перезагружается при открытии
  final Map<String, double> _zMap = <String, double>{
    'cover': 1,
    'main': 2,
    'alt': 2,
    'notes': 2,
    'quotes': 2,
    'images': 2,
  };
  double _topZ = 10;
  String? _hoveredId;
  String? _draggingId;
  final Map<String, bool> _collapsedMap = <String, bool>{
    'main': false,
    'alt': false,
    'notes': false,
    'quotes': false,
    'images': false,
  };

  @override
  void initState() {
    super.initState();
    // Svelte $effect выполняется и на первом открытии: применить поля
    // редактируемого item при начальном монтировании.
    if (widget.isOpen && widget.editingItem != null) {
      _applyEditableFields(widget.editingItem!);
      _editingInitialized = true;
      final id = widget.editingItem!.id;
      loadMediaDetail(
        ref.read(mediaDetailCacheProvider),
        ref.read(apiClientProvider),
        id,
      ).then((detail) {
        if (!mounted || !widget.isOpen || widget.editingItem?.id != id) return;
        _applyEditableFields(detail);
      }).catchError((_) {});
    }
  }

  Ticker? _threadTicker;
  final Map<String, ThreadSpring> _springs = <String, ThreadSpring>{};
  final ThreadsNotifier _threadsNotifier = ThreadsNotifier();

  @override
  void dispose() {
    _threadTicker?.dispose();
    _threadsNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EditMediaWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);

    // $effect: применить редактируемые поля при открытии + подтянуть деталь.
    if (widget.isOpen && widget.editingItem != null && !_editingInitialized) {
      _applyEditableFields(widget.editingItem!);
      _editingInitialized = true;
      final id = widget.editingItem!.id;
      loadMediaDetail(
        ref.read(mediaDetailCacheProvider),
        ref.read(apiClientProvider),
        id,
      ).then((detail) {
        if (!mounted || !widget.isOpen || widget.editingItem?.id != id) return;
        _applyEditableFields(detail);
      }).catchError((_) {});
    }
    if (widget.isOpen && !oldWidget.isOpen) {
      _editingInitialized = false;
      _submitError = null;
      _validationError = '';
      // Загрузить (или переклампить) сохранённую раскладку при каждом открытии.
      final size = MediaQuery.sizeOf(context);
      loadLayout(size.width, size.height).then((layout) {
        if (mounted && widget.isOpen) setState(() => _layout = layout);
      });
    }

    // Живые нити: тикер активен, пока открыт + desktop.
    final desktop = MediaQuery.sizeOf(context).width >= 1024;
    if (widget.isOpen && desktop) {
      _startThreadLoop();
    } else {
      _threadTicker?.dispose();
      _threadTicker = null;
      if (!widget.isOpen) {
        setState(() {
          _draggingId = null;
          _hoveredId = null;
        });
      }
    }
  }

  void _startThreadLoop() {
    if (_threadTicker != null) return;
    final ticker = createTicker(_onTick);
    _threadTicker = ticker;
    // Инициализация пружин (фаза = index * 1.3, как в Svelte).
    _springs.clear();
    for (var index = 0; index < _kThreads.length; index++) {
      final thread = _kThreads[index];
      final target = nearestFaceAnchors(_nodeRect(thread.from), _nodeRect(thread.to));
      _springs[thread.key] = ThreadSpring(target, (index * 1.3 * 100).round());
    }
    ticker.start();
  }

  static const List<({String key, String from, String to})> _kThreads =
      <({String key, String from, String to})>[
    (key: 'cover-main', from: 'cover', to: 'main'),
    (key: 'cover-notes', from: 'cover', to: 'notes'),
    (key: 'cover-quotes', from: 'cover', to: 'quotes'),
    (key: 'cover-images', from: 'cover', to: 'images'),
    (key: 'main-alt', from: 'main', to: 'alt'),
  ];

  ThreadRect _nodeRect(String id) {
    if (id == 'cover') {
      return ThreadRect(
        x: _layout.cover.x,
        y: _layout.cover.y,
        w: kCoverSize.w,
        h: kCoverSize.h,
      );
    }
    final rect = _layout.windows[id]!;
    return _collapsedMap[id] == true
        ? ThreadRect(x: rect.x, y: rect.y, w: rect.w, h: 40)
        : ThreadRect(x: rect.x, y: rect.y, w: rect.w, h: rect.h);
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    for (var index = 0; index < _kThreads.length; index++) {
      final thread = _kThreads[index];
      final spring = _springs[thread.key];
      if (spring == null) continue;
      final target =
          nearestFaceAnchors(_nodeRect(thread.from), _nodeRect(thread.to));
      // Драгнутые кабели — жёсткая пружина: кабель прижимается к окну.
      final active =
          _draggingId == thread.from || _draggingId == thread.to;
      final path = spring.step(target, now, active ? 0.35 : 0.14);
      _threadsNotifier.setPath(thread.key, path);
    }
  }

  bool _isThreadActive(({String key, String from, String to}) thread) {
    final focus = _draggingId ?? _hoveredId;
    if (focus == null) return false;
    return thread.from == focus || thread.to == focus;
  }

  void _bringToFront(String id) {
    if (_zMap[id] == _topZ) return;
    setState(() {
      _topZ += 1;
      _zMap[id] = _topZ;
    });
  }

  Future<void> _persist() async => saveLayout(_layout);

  Future<void> _resetLayout() async {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _layout = defaultLayout(size.width, size.height);
      for (final id in kWorkspaceWindowIds) {
        _collapsedMap[id] = false;
        _zMap[id] = 2;
      }
      _zMap['cover'] = 1;
      _topZ = 10;
    });
    await _persist();
  }

  // -------------------------------------------------------------------------
  // Drag центральной обложки (позиция только).
  // -------------------------------------------------------------------------
  ({Offset start, OffsetPoint origin})? _coverDrag;

  void _startCoverDrag(DragStartDetails details) {
    _bringToFront('cover');
    setState(() {
      _draggingId = 'cover';
      _coverDrag = (
        start: details.globalPosition,
        origin: OffsetPoint(_layout.cover.x, _layout.cover.y),
      );
    });
  }

  void _moveCoverDrag(DragUpdateDetails details) {
    final drag = _coverDrag;
    if (drag == null) return;
    final size = MediaQuery.sizeOf(context);
    setState(() {
      _layout = WorkspaceLayout(
        cover: clampPoint(
          OffsetPoint(
            drag.origin.x + details.globalPosition.dx - drag.start.dx,
            drag.origin.y + details.globalPosition.dy - drag.start.dy,
          ),
          size.width,
          size.height,
        ),
        windows: _layout.windows,
      );
    });
  }

  void _finishCoverDrag() {
    if (_coverDrag == null) return;
    setState(() {
      _coverDrag = null;
      _draggingId = null;
    });
    _persist();
  }

  // -------------------------------------------------------------------------
  //applyEditableFields (1-в-1 с Svelte).
  // -------------------------------------------------------------------------
  void _applyEditableFields(MediaItem item) {
    setState(() {
      _type = item.type.wire;
      _title = item.title;
      _coverUrl = item.coverUrl ?? '';
      _notes = item is MediaDetail ? (item.notes ?? '') : '';
      _score = item.score?.toString() ?? '';
      _startedAt = item.startedAt?.substring(0, math.min(16, item.startedAt?.length ?? 0)) ?? '';
      _finishedAt = item.finishedAt?.substring(0, math.min(16, item.finishedAt?.length ?? 0)) ?? '';
      _status = item.status;

      // Бандл тип-специфичных полей сбрасывается при каждом apply: смена типа
      // с game на book не должна хранить платформу игры.
      _category = CategoryDraft.empty();
      // Только detail-payload несёт alt titles/quotes/covers.
      _altTitles = item is MediaDetail
          ? List<String>.from(item.altTitles ?? const <String>[])
          : <String>[];
      _quotes = item is MediaDetail
          ? _parseQuotes(item.quotesJson)
          : <QuoteDraft>[];
      _covers = item is MediaDetail
          ? List<MediaCoverItem>.from(item.covers ?? const <MediaCoverItem>[])
          : <MediaCoverItem>[];

      if (item.type == MediaType.game) {
        _category = _category.copyWith(
          platform: item.platform ?? '',
          hoursPlayed: item.hoursPlayed?.toString() ?? '',
        );
      } else if (item.type == MediaType.book) {
        _category = _category.copyWith(
          author: item.author ?? '',
          bookFormat: (item.format?.isNotEmpty ?? false) ? item.format! : 'book',
          totalPages: item.totalPages?.toString() ?? '',
          totalChapters: item.totalChapters?.toString() ?? '',
          bookTotalVolumes: item.totalVolumes?.toString() ?? '',
        );
      } else if (item.type == MediaType.manga) {
        _category = _category.copyWith(
          author: item.author ?? '',
          totalChapters: item.totalChapters?.toString() ?? '',
          currentVolume: item.currentVolume?.toString() ?? '',
          totalPages: item.totalVolumes?.toString() ?? '',
        );
      } else if (item.type == MediaType.movie) {
        _category = _category.copyWith(
          durationMinutes: item.durationMinutes?.toString() ?? '',
          isAnime: item.isAnime ?? false,
          studio: item.studio ?? '',
        );
      } else if (item.type == MediaType.tvshow) {
        _category = _category.copyWith(
          isAnime: item.isAnime ?? false,
          studio: item.studio ?? '',
          network: item.network ?? '',
          seasons: (item is MediaDetail
                  ? (item.seasons ?? const <TvSeason>[])
                  : const <TvSeason>[])
              .map((season) => SeasonDraft(
                    seasonNumber: season.seasonNumber.toString(),
                    title: season.title,
                    totalEpisodes: season.totalEpisodes.toString(),
                  ))
              .toList(),
        );
      }
    });
  }

  List<QuoteDraft> _parseQuotes(String? json) {
    if (json == null || json.isEmpty) return <QuoteDraft>[];
    try {
      final parsed = jsonDecodeNoThrow(json);
      if (parsed is List) {
        return parsed
            .whereType<Map>()
            .map((m) => MediaQuote.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      return <QuoteDraft>[];
    } catch (_) {
      return <QuoteDraft>[];
    }
  }

  // -------------------------------------------------------------------------
  // Submit: те же контракты, что у обычной модалки — workspace это просто
  // другой фронтенд над теми же payload'ами.
  // -------------------------------------------------------------------------
  int? _numberOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed != null) return parsed;
    return double.tryParse(trimmed)?.round();
  }

  String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<CreateSeasonPayload> _buildSeasons() {
    final t = ref.read(tProvider);
    final seasons = <CreateSeasonPayload>[];
    var index = 0;
    for (final season in _category.seasons) {
      if (season.title.trim().isEmpty && season.totalEpisodes.trim().isEmpty) {
        continue;
      }
      seasons.add(CreateSeasonPayload(
        seasonNumber: _numberOrNull(season.seasonNumber) ?? index + 1,
        title: season.title.trim().isNotEmpty
            ? season.title.trim()
            : '${t.tr('createModal.fields.season')} ${index + 1}',
        coverUrl: null,
        totalEpisodes: math.max(_numberOrNull(season.totalEpisodes) ?? 0, 0),
        status: MediaStatus.planned,
        score: null,
        notes: null,
        airDate: null,
        episodesData: null,
      ));
      index += 1;
    }
    return seasons;
  }

  CreateMediaBase _buildPayload() {
    final altTitleList =
        _altTitles.map((value) => value.trim()).where((v) => v.isNotEmpty).toList();
    final common = (
      title: _title.trim(),
      altTitles: altTitleList,
      coverUrl: _optionalText(_coverUrl),
      notes: _optionalText(_notes),
    );

    switch (_type) {
      case 'game':
        return CreateGamePayload(
          platform: _category.platform.trim(),
          hoursPlayed: _numberOrNull(_category.hoursPlayed),
          title: common.title,
          status: MediaStatus.planned,
          altTitles: common.altTitles,
          score: null,
          coverUrl: common.coverUrl,
          notes: common.notes,
          description: null,
          trailerVideoId: null,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: null,
          externalSource: null,
          importSource: null,
          externalRating: null,
          externalRatingVotes: null,
          externalRatingsJson: null,
          releaseDate: null,
          endDate: null,
          releaseStatus: null,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'book':
        final isNovel =
            _category.bookFormat == 'light_novel' || _category.bookFormat == 'web_novel';
        return CreateBookPayload(
          author: _category.author.trim(),
          studio: null,
          isbn: null,
          totalPages: isNovel ? null : _numberOrNull(_category.totalPages),
          format: _category.bookFormat.isEmpty ? 'book' : _category.bookFormat,
          currentChapter: null,
          totalChapters: isNovel ? _numberOrNull(_category.totalChapters) : null,
          currentVolume: null,
          totalVolumes: isNovel ? _numberOrNull(_category.bookTotalVolumes) : null,
          title: common.title,
          status: MediaStatus.planned,
          altTitles: common.altTitles,
          score: null,
          coverUrl: common.coverUrl,
          notes: common.notes,
          description: null,
          trailerVideoId: null,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: null,
          externalSource: null,
          importSource: null,
          externalRating: null,
          externalRatingVotes: null,
          externalRatingsJson: null,
          releaseDate: null,
          endDate: null,
          releaseStatus: null,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'manga':
        return CreateMangaPayload(
          author: _optionalText(_category.author.trim()) ?? '',
          romajiTitle: null,
          totalVolumes: _numberOrNull(_category.totalPages) ?? 1,
          totalChapters: _numberOrNull(_category.totalChapters),
          currentVolume: _numberOrNull(_category.currentVolume) ?? 1,
          volumes: null,
          title: common.title,
          status: MediaStatus.planned,
          altTitles: common.altTitles,
          score: null,
          coverUrl: common.coverUrl,
          notes: common.notes,
          description: null,
          trailerVideoId: null,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: null,
          externalSource: null,
          importSource: null,
          externalRating: null,
          externalRatingVotes: null,
          externalRatingsJson: null,
          releaseDate: null,
          endDate: null,
          releaseStatus: null,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'movie':
        return CreateMoviePayload(
          durationMinutes: _numberOrNull(_category.durationMinutes),
          director: null,
          isAnime: _category.isAnime,
          studio: _optionalText(_category.studio),
          romajiTitle: null,
          title: common.title,
          status: MediaStatus.planned,
          altTitles: common.altTitles,
          score: null,
          coverUrl: common.coverUrl,
          notes: common.notes,
          description: null,
          trailerVideoId: null,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: null,
          externalSource: null,
          importSource: null,
          externalRating: null,
          externalRatingVotes: null,
          externalRatingsJson: null,
          releaseDate: null,
          endDate: null,
          releaseStatus: null,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      default: // tvshow
        return CreateTvShowPayload(
          isAnime: _category.isAnime,
          studio: _optionalText(_category.studio),
          romajiTitle: null,
          network: _optionalText(_category.network),
          durationMinutes: null,
          episodeDurationMinutes: null,
          seasons: _buildSeasons(),
          title: common.title,
          status: MediaStatus.planned,
          altTitles: common.altTitles,
          score: null,
          coverUrl: common.coverUrl,
          notes: common.notes,
          description: null,
          trailerVideoId: null,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: null,
          externalSource: null,
          importSource: null,
          externalRating: null,
          externalRatingVotes: null,
          externalRatingsJson: null,
          releaseDate: null,
          endDate: null,
          releaseStatus: null,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
    }
  }

  /// ISO-строка из локального datetime-ввода (Svelte: new Date(x).toISOString()).
  String? _toIsoOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return null;
    // datetime-local без зоны → UTC-конверсия как в JS Date.
    return parsed.toUtc().toIso8601String();
  }

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    setState(() {
      _validationError = '';
      _submitError = null;
    });

    if (_title.trim().isEmpty) {
      setState(
          () => _validationError = t.tr('createModal.validation.titleRequired'));
      return;
    }

    if (!isValidCoverUrl(_coverUrl)) {
      setState(() =>
          _validationError = t.tr('createModal.validation.coverUrlInvalid'));
      return;
    }

    setState(() => _submitting = true);

    try {
      final editing = widget.editingItem;
      final isNovel =
          _category.bookFormat == 'light_novel' || _category.bookFormat == 'web_novel';
      final MediaItem saved;
      if (editing != null) {
        saved = await ref.read(apiClientProvider).updateMedia(editing.id,
            UpdateMediaPayload(
          title: _title.trim(),
          // Явный список (даже пустой) — интенция: бэкенд применит как есть.
          altTitles:
              _altTitles.map((value) => value.trim()).where((v) => v.isNotEmpty).toList(),
          score: _numberOrNull(_score),
          // Пустая строка = «очистить»; null сохранил бы значение.
          notes: _notes.trim(),
          quotesJson: jsonEncode(_quotes
              .map((q) => <String, Object?>{
                    'id': q.id,
                    'text': q.text,
                    if (q.pageOrContext != null) 'pageOrContext': q.pageOrContext,
                    'createdAt': q.createdAt,
                  })
              .toList()),
          coverUrl: _coverUrl.trim(),
          startedAt: _toIsoOrNull(_startedAt),
          finishedAt: _toIsoOrNull(_finishedAt),
          status: _status,
          platform: _type == 'game' ? _category.platform.trim() : null,
          format: _type == 'book'
              ? (_category.bookFormat.isEmpty ? 'book' : _category.bookFormat)
              : null,
          author: _type == 'book' || _type == 'manga'
              ? _category.author.trim()
              : null,
          totalPages: _type == 'book'
              ? (isNovel ? null : _numberOrNull(_category.totalPages))
              : null,
          totalChapters: _type == 'book'
              ? (isNovel ? _numberOrNull(_category.totalChapters) : null)
              : _type == 'manga'
                  ? _numberOrNull(_category.totalChapters)
                  : null,
          totalVolumes: _type == 'book'
              ? (isNovel ? _numberOrNull(_category.bookTotalVolumes) : null)
              : _type == 'manga'
                  ? _numberOrNull(_category.totalPages)
                  : null,
        ));
      } else {
        saved = await ref.read(apiClientProvider).createMedia(_buildPayload());
      }
      widget.onCreated(saved);
      widget.onClose();
    } catch (error) {
      if (mounted) setState(() => _submitError = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleCoversChange(MediaDetail updated) {
    setState(() => _covers = updated.covers ?? const <MediaCoverItem>[]);
  }

  // -------------------------------------------------------------------------
  // Окна: иконки/тайтлы/counts.
  // -------------------------------------------------------------------------
  IconData _windowIcon(String id) {
    switch (id) {
      case 'main':
        return LucideIcons.layers;
      case 'alt':
        return LucideIcons.tag;
      case 'notes':
        return LucideIcons.fileText;
      case 'quotes':
        return LucideIcons.quote;
      default:
        return LucideIcons.image;
    }
  }

  String _windowTitle(I18nDictionary t, String id) {
    // Ключ 'altTitles', а не 'alt' (Svelte: modules[id] с ключом altTitles).
    if (id == 'main') return t.tr('createModal.modules.main');
    if (id == 'alt') return t.tr('createModal.modules.altTitles');
    return t.tr('createModal.modules.$id');
  }

  int? _windowCount(String id) {
    if (id == 'alt') return _altTitles.length;
    if (id == 'quotes') return _quotes.length;
    if (id == 'images') return widget.editingItem != null ? _covers.length : null;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final desktop = size.width >= 1024;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Backdrop (blur имитируется полупрозрачным #0d0f14/80).
          Positioned.fill(
            child: GestureDetector(
              onSecondaryTap: () {}, // контекст-меню страницы не достаётся
              child: Container(color: const Color(0xCC0D0F14)),
            ),
          ),
          if (desktop) ..._buildDesktop(t, th, size),
          if (!desktop) ..._buildMobile(t, th),
          // Floating control bar.
          _buildControlBar(t, th),
        ],
      ),
    );
  }

  Widget _buildControlBar(I18nDictionary t, TsundokuTheme th) {
    return Positioned(
      top: 16, // top-4
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8), // px-4 py-2
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999), // rounded-full
                border: Border.all(
                    color: Colors.white.withAlpha(20)), // white/[0.08]
                color: const Color(0xF212151C), // bg-[#12151c]/95
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000), // shadow-xl shadow-black/40
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (widget.editingItem != null
                            ? t.tr('createModal.editTitle')
                            : t.tr('createModal.title'))
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.92, // tracking-[0.16em]
                      color: th.textPrimary, // text-ink
                    ),
                  ),
                  const SizedBox(width: 4), // mr-1
                  if (_isDesktop) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _resetLayout,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6), // px-2.5 py-1.5
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.rotateCcw,
                                size: 13, color: th.textMuted),
                            const SizedBox(width: 6), // gap-1.5
                            Text(
                              t.tr('editWorkspace.resetLayout'),
                              style: TextStyle(
                                fontSize: 12, // text-xs
                                fontWeight: FontWeight.w600,
                                color: th.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4), // mx-1
                      width: 1,
                      height: 20,
                      color: Colors.white24, // bg-white/10
                    ),
                  ],
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _submitting ? null : widget.onClose,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(
                        t.tr('common.cancel'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: th.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _submitting ? null : _submit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6), // px-4 py-1.5
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: _submitting
                            ? th.accent.withAlpha(178) // disabled:opacity-70
                            : th.accent,
                      ),
                      child: Text(
                        _submitting
                            ? t.tr('common.saving')
                            : widget.editingItem != null
                                ? t.tr('common.save')
                                : t.tr('common.add'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (!_isDesktop) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onClose,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        child: Icon(LucideIcons.x,
                            size: 15, color: th.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_validationError.isNotEmpty || _submitError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8), // mt-2
                child: Column(
                  children: [
                    if (_validationError.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6), // px-3 py-1.5
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0x4DF87171)), // rose-400/30
                          color: const Color(0x1AF87171), // bg-rose-400/10
                        ),
                        child: Text(
                          _validationError,
                          style: const TextStyle(
                            fontSize: 12, // text-xs
                            color: Color(0xFFFECDD3), // text-rose-200
                          ),
                        ),
                      ),
                    if (_submitError != null)
                      GestureDetector(
                        onTap: () => setState(() => _submitError = null),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0x4DF87171)),
                            color: const Color(0x1AF87171),
                          ),
                          child: Text(
                            errorMessage(
                                _submitError!, ref.read(i18nProvider)),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFECDD3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDesktop(
      I18nDictionary t, TsundokuTheme th, Size size) {
    // Окна в фиксированном DOM-порядке; z-стек — порядком детей Stack (по
    // возрастанию z), поэтому bringToFront при драге не «отрывает» узлы —
    // дети с ключами.
    final windowIds = List<String>.from(kWorkspaceWindowIds)
      ..sort((a, b) => (_zMap[a] ?? 2).compareTo(_zMap[b] ?? 2));

    return [
      // Thread layer (за окнами).
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _ThreadsPainter(
              notifier: _threadsNotifier,
              isThreadActive: _isThreadActive,
            ),
          ),
        ),
      ),
      // Центральный cover-узел.
      Positioned(
        left: _layout.cover.x,
        top: _layout.cover.y,
        width: kCoverSize.w,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hoveredId = 'cover'),
          onExit: (_) {
            if (_draggingId != 'cover') setState(() => _hoveredId = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _startCoverDrag,
            onPanUpdate: _moveCoverDrag,
            onPanEnd: (_) => _finishCoverDrag(),
            onPanCancel: () => _finishCoverDrag(),
            child: Container(
              height: kCoverSize.w * 3 / 2, // aspect-[2/3]
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12), // rounded-xl
                border: Border.all(
                    color: Colors.white.withAlpha(26)), // white/[0.1]
                color: const Color(0xFF12151C),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xB3000000), // shadow-2xl shadow-black/50
                    blurRadius: 25,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _coverUrl.isEmpty
                    ? MediaCoverPlaceholder(
                        label: t.tr('activity.coverMissing'))
                    : TsundokuImage(
                        imageUrl: fullSizeCoverUrl(_coverUrl),
                        fit: BoxFit.cover,
                        errorWidget: Container(color: th.bgSurface),
                      ),
              ),
            ),
          ),
        ),
      ),
      for (final winId in windowIds)
        WorkspaceWindow(
          key: ValueKey(winId),
          id: winId,
          title: _windowTitle(t, winId),
          icon: _windowIcon(winId),
          count: _windowCount(winId),
          rect: _layout.windows[winId]!,
          z: _zMap[winId] ?? 2,
          highlighted: _hoveredId == winId || _draggingId == winId,
          collapsed: _collapsedMap[winId] ?? false,
          onCollapsedChange: (v) =>
              setState(() => _collapsedMap[winId] = v),
          onFront: () => _bringToFront(winId),
          onHoverChange: (hovered) =>
              setState(() => _hoveredId = hovered ? winId : null),
          onDragStateChange: (dragging) =>
              setState(() => _draggingId = dragging ? winId : null),
          onSettled: _persist,
          onRectChange: (rect) => setState(
              () => _layout.windows[winId] = rect),
          viewportW: size.width,
          viewportH: size.height,
          child: _buildWindowBody(t, winId, flat: true, showLabel: false),
        ),
    ];
  }

  List<Widget> _buildMobile(I18nDictionary t, TsundokuTheme th) {
    Widget section(Widget child) => Container(
          padding: const EdgeInsets.all(16), // p-4
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // rounded-xl
            border: Border.all(
                color: Colors.white.withAlpha(15)), // white/[0.06]
            color: const Color(0xF212151C), // bg-[#12151c]/95
          ),
          child: child,
        );

    return [
      Positioned.fill(
        child: TsundokuSmoothScrollView(
          padding: const EdgeInsets.fromLTRB(16, 64, 16, 24), // px-4 pt-16 pb-6
          child: Column(
            children: [
              // Обложка w-32 по центру.
              SizedBox(
                width: 128, // w-32
                child: Container(
                  height: 192, // aspect 2/3
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withAlpha(26)), // white/[0.1]
                    color: const Color(0xFF12151C),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _coverUrl.isEmpty
                        ? MediaCoverPlaceholder(
                            label: t.tr('activity.coverMissing'))
                        : TsundokuImage(
                            imageUrl: fullSizeCoverUrl(_coverUrl),
                            fit: BoxFit.cover,
                            errorWidget: Container(color: th.bgSurface),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16), // mt-4
              Container(
                constraints: const BoxConstraints(maxWidth: 576), // max-w-xl
                child: Column(
                  children: [
                    section(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BaseMediaModule(
                          idPrefix: 'create',
                          type: MediaType.fromWire(_type),
                          title: _title,
                          score: _score,
                          status: _status,
                          startedAt: _startedAt,
                          finishedAt: _finishedAt,
                          onTypeChange: (v) => setState(() => _type = v.wire),
                          onTitleChange: (v) => setState(() => _title = v),
                          onScoreChange: (v) => setState(() => _score = v),
                          onStatusChange: (v) => setState(() => _status = v),
                          onStartedAtChange: (v) =>
                              setState(() => _startedAt = v),
                          onFinishedAtChange: (v) =>
                              setState(() => _finishedAt = v),
                        ),
                        const SizedBox(height: 12), // space-y-3
                        CategoryFieldsModule(
                          type: _type,
                          category: _category,
                          onCategoryChange: (next) =>
                              setState(() => _category = next),
                          isEditing: widget.editingItem != null,
                        ),
                      ],
                    )),
                    const SizedBox(height: 16), // gap-4
                    section(AltTitlesModule(
                      altTitles: _altTitles,
                      onChange: (next) => setState(() => _altTitles = next),
                    )),
                    const SizedBox(height: 16),
                    section(NotesModule(
                      notes: _notes,
                      onNotesChange: (v) => setState(() => _notes = v),
                    )),
                    const SizedBox(height: 16),
                    section(QuotesModule(
                      quotes: _quotes,
                      onChange: (next) => setState(() => _quotes = next),
                    )),
                    const SizedBox(height: 16),
                    section(ImagesModule(
                      mediaId: widget.editingItem?.id,
                      coverUrl: _coverUrl,
                      onCoverUrlChange: (v) =>
                          setState(() => _coverUrl = v),
                      title: _title,
                      covers: _covers,
                      onCoversChange: _handleCoversChange,
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildWindowBody(
    I18nDictionary t,
    String winId, {
    required bool flat,
    required bool showLabel,
  }) {
    switch (winId) {
      case 'main':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BaseMediaModule(
              flat: flat,
              idPrefix: 'create',
              type: MediaType.fromWire(_type),
              title: _title,
              score: _score,
              status: _status,
              startedAt: _startedAt,
              finishedAt: _finishedAt,
              onTypeChange: (v) => setState(() => _type = v.wire),
              onTitleChange: (v) => setState(() => _title = v),
              onScoreChange: (v) => setState(() => _score = v),
              onStatusChange: (v) => setState(() => _status = v),
              onStartedAtChange: (v) => setState(() => _startedAt = v),
              onFinishedAtChange: (v) => setState(() => _finishedAt = v),
            ),
            const SizedBox(height: 16), // space-y-4
            CategoryFieldsModule(
              flat: flat,
              type: _type,
              category: _category,
              onCategoryChange: (next) => setState(() => _category = next),
              isEditing: widget.editingItem != null,
            ),
          ],
        );
      case 'alt':
        return AltTitlesModule(
          flat: flat,
          showLabel: showLabel,
          altTitles: _altTitles,
          onChange: (next) => setState(() => _altTitles = next),
        );
      case 'notes':
        return NotesModule(
          flat: flat,
          showLabel: showLabel,
          notes: _notes,
          onNotesChange: (v) => setState(() => _notes = v),
        );
      case 'quotes':
        return QuotesModule(
          flat: flat,
          showLabel: showLabel,
          quotes: _quotes,
          onChange: (next) => setState(() => _quotes = next),
        );
      default: // images
        return ImagesModule(
          flat: flat,
          showLabel: showLabel,
          mediaId: widget.editingItem?.id,
          coverUrl: _coverUrl,
          onCoverUrlChange: (v) => setState(() => _coverUrl = v),
          title: _title,
          covers: _covers,
          onCoversChange: _handleCoversChange,
        );
    }
  }
}

/// Изменяемый реестр SVG-путей нитей (painter перерисовывается по notify).
class ThreadsNotifier extends ChangeNotifier {
  final Map<String, String> _paths = <String, String>{};

  String? pathOf(String key) => _paths[key];

  void setPath(String key, String path) {
    _paths[key] = path;
    notifyListeners();
  }
}

/// Рисование нитей (stroke 1.5; активная — accent 0.65, покой — white 0.16).
class _ThreadsPainter extends CustomPainter {
  final ThreadsNotifier notifier;
  final bool Function(({String key, String from, String to})) isThreadActive;

  _ThreadsPainter({
    required this.notifier,
    required this.isThreadActive,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    for (final thread in const <({String key, String from, String to})>[
      (key: 'cover-main', from: 'cover', to: 'main'),
      (key: 'cover-notes', from: 'cover', to: 'notes'),
      (key: 'cover-quotes', from: 'cover', to: 'quotes'),
      (key: 'cover-images', from: 'cover', to: 'images'),
      (key: 'main-alt', from: 'main', to: 'alt'),
    ]) {
      final d = notifier.pathOf(thread.key);
      if (d == null) continue;
      final path = _parseBezierPath(d);
      if (path == null) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = isThreadActive(thread)
            ? const Color(0xA68B7CF6) // rgba(139, 124, 246, 0.65)
            : const Color(0x29FFFFFF); // rgba(255, 255, 255, 0.16)
      canvas.drawPath(path, paint);
    }
  }

  /// Парсер строки `M x y C c1x c1y, c2x c2y, x y` (формат ThreadSpring.step).
  Path? _parseBezierPath(String d) {
    final numbers =
        RegExp(r'-?\d+(?:\.\d+)?').allMatches(d).map((m) => double.parse(m.group(0)!)).toList();
    if (numbers.length != 8) return null;
    return Path()
      ..moveTo(numbers[0], numbers[1])
      ..cubicTo(numbers[2], numbers[3], numbers[4], numbers[5], numbers[6], numbers[7]);
  }

  @override
  bool shouldRepaint(_ThreadsPainter oldDelegate) => false;
}

/// jsonDecode без throw (обёртка для parseQuotes).
dynamic jsonDecodeNoThrow(String source) {
  try {
    return const JsonDecoder().convert(source);
  } catch (_) {
    return null;
  }
}
