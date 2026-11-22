/// 1:1 port of `mediatracker-ui/src/features/search-external/SearchModal.svelte`.
///
/// Модалка внешнего поиска тайтлов: поиск по источникам (AniList, Shikimori,
/// TMDB, MangaDex, RAWG, Steam, OpenLibrary и др.), группировка по категориям
/// или фильтрация по одной, предпросмотр тайтлов, фильтр по создателю,
/// распознавание прямых ссылок/ISBN, добавление/удаление тайтлов в библиотеку.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/cover_url.dart';
import '../prefetch-details/external_detail_prefetch.dart';
import '../../shared/api/api.dart';
import '../../shared/api/jobs_client.dart';
import '../../shared/i18n/index.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/toast.dart';
import '../../shared/utils/url_media_parser.dart';
import '../../widgets/media-detail/external_detail_modal.dart';

const List<String> kSearchCategories = [
  'all',
  'anime',
  'manga',
  'movie',
  'tvshow',
  'game',
  'book',
];

const int kSearchDebounceMs = 2000;
const int kMinQueryLength = 3;
const String kFallbackPlatform = 'PC';

({Color bg, Color text, Color border}) sourceBadgeColors(String? source) {
  final s = (source ?? '').toLowerCase();
  if (s.contains('anilist')) {
    return (
      bg: const Color(0x1F38BDF8),
      text: const Color(0xFF38BDF8),
      border: const Color(0x4D38BDF8),
    );
  }
  if (s.contains('sociallib') ||
      s.contains('ranobelib') ||
      s.contains('mangalib') ||
      s.contains('animelib') ||
      s.contains('slashlib') ||
      s.contains('hentailib')) {
    return (
      bg: const Color(0x1FFA7268),
      text: const Color(0xFFFA7268),
      border: const Color(0x4DFA7268),
    );
  }
  if (s.contains('shikimori')) {
    return (
      bg: const Color(0x1F2CA5FF),
      text: const Color(0xFF2CA5FF),
      border: const Color(0x4D2CA5FF),
    );
  }
  if (s.contains('mangadex')) {
    return (
      bg: const Color(0x1FFF6740),
      text: const Color(0xFFFF6740),
      border: const Color(0x4DFF6740),
    );
  }
  if (s.contains('mal') || s.contains('myanimelist') || s.contains('jikan')) {
    return (
      bg: const Color(0x1F2E51A2),
      text: const Color(0xFF6B8BFF),
      border: const Color(0x4D2E51A2),
    );
  }
  if (s.contains('mangaupdate')) {
    return (
      bg: const Color(0x1F94A3B8),
      text: const Color(0xFF94A3B8),
      border: const Color(0x3394A3B8),
    );
  }
  if (s.contains('tmdb')) {
    return (
      bg: const Color(0x1F01B4E4),
      text: const Color(0xFF01B4E4),
      border: const Color(0x4D01B4E4),
    );
  }
  if (s.contains('kitsu')) {
    return (
      bg: const Color(0x1FFD755C),
      text: const Color(0xFFFD755C),
      border: const Color(0x4DFD755C),
    );
  }
  if (s.contains('rawg')) {
    return (
      bg: const Color(0x1AFFFFFF),
      text: const Color(0xFFE2E8F0),
      border: const Color(0x24FFFFFF),
    );
  }
  if (s.contains('steam')) {
    return (
      bg: const Color(0xFF171A21),
      text: const Color(0xFF66C0F4),
      border: const Color(0x6666C0F4),
    );
  }
  if (s.contains('igdb')) {
    return (
      bg: const Color(0x1F9146FF),
      text: const Color(0xFFA970FF),
      border: const Color(0x4D9146FF),
    );
  }
  if (s.contains('openlibrary')) {
    return (
      bg: const Color(0x26F59E0B),
      text: const Color(0xFFFCD34D),
      border: const Color(0x4DF59E0B),
    );
  }
  return (
    bg: const Color(0x1AFFFFFF),
    text: const Color(0xFF94A3B8),
    border: const Color(0x14FFFFFF),
  );
}

class SearchModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final String initialType;
  final String initialQuery;
  final String initialSource;
  final bool byCreator;
  final VoidCallback onClose;
  final void Function(MediaItem media) onMediaAdded;
  final void Function(String id)? onMediaRemoved;
  final void Function(String id)? onNavigateToMedia;
  final int debounceMs;

  const SearchModal({
    super.key,
    required this.isOpen,
    this.initialType = 'all',
    this.initialQuery = '',
    this.initialSource = '',
    this.byCreator = false,
    required this.onClose,
    required this.onMediaAdded,
    this.onMediaRemoved,
    this.onNavigateToMedia,
    this.debounceMs = kSearchDebounceMs,
  });

  @override
  ConsumerState<SearchModal> createState() => _SearchModalState();
}

class _SearchModalState extends ConsumerState<SearchModal> {
  late final TextEditingController _queryController;
  late String _activeType;
  late String _selectedSource;
  String? _creatorFilter;

  List<ExternalMedia> _results = [];
  Map<String, List<ExternalMedia>> _resultsByCategory = {};
  Map<String, bool> _loadingByCategory = {};

  bool _searching = false;
  Object? _searchError;
  Object? _addError;
  String _addingKey = '';
  Map<String, String> _addedKeys = {};

  ExternalMedia? _previewItem;
  List<String> _categoryOrder = [
    'anime',
    'manga',
    'movie',
    'tvshow',
    'game',
    'book',
  ];
  List<SourceInfo> _availableSources = [];

  int _requestSequence = 0;
  CancelToken? _cancelToken;
  Timer? _debounceTimer;
  Timer? _hoverTimer;
  String? _hoverPrefetchKey;
  CancelToken? _hoverCancelToken;
  bool _coverForceRefresh = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _activeType = widget.initialType;
    _selectedSource = widget.initialSource;
    _creatorFilter = widget.byCreator ? widget.initialQuery : null;

    if (widget.isOpen) {
      _initModal();
    }
  }

  @override
  void didUpdateWidget(SearchModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isOpen && widget.isOpen) {
      _queryController.text = widget.initialQuery;
      _activeType = widget.initialType;
      _selectedSource = widget.initialSource;
      _creatorFilter = widget.byCreator ? widget.initialQuery : null;
      _previewItem = null;
      _initModal();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cancelToken?.cancel();
    _hoverTimer?.cancel();
    _hoverCancelToken?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _initModal() {
    final api = ref.read(apiClientProvider);

    // Load sources
    api.getSources(forceRefresh: true).then((res) {
      if (mounted && res.isNotEmpty) {
        setState(() => _availableSources = res);
      }
    }).catchError((_) {});

    // Load category order
    api.getCategoryOrder().then((order) {
      if (mounted && order.isNotEmpty) {
        setState(() => _categoryOrder = order);
      }
    }).catchError((_) {});

    // Load library media to populate addedKeys
    api.getMedia().then((items) {
      if (!mounted) return;
      final map = <String, String>{};
      for (final item in items) {
        if (item.externalId != null && item.externalId!.isNotEmpty) {
          final isAnime = (item.type == MediaType.tvshow ||
                  item.type == MediaType.movie) &&
              item.isAnime == true;
          final effectiveType =
              item.type == MediaType.tvshow && isAnime ? 'anime' : item.type.name;
          map['$effectiveType:${item.externalId}'] = item.id;
          map['title:${item.title.toLowerCase()}'] = item.id;
        }
      }
      setState(() => _addedKeys = map);
    }).catchError((_) {});

    if (_queryController.text.trim().length >= kMinQueryLength) {
      _triggerSearch(immediate: true);
    }
  }

  bool _sourceSupports(String sourceId, String type) {
    return _availableSources.any((s) =>
        s.isEnabled &&
        (s.id.toLowerCase() == sourceId.toLowerCase() ||
            s.name.toLowerCase() == sourceId.toLowerCase()) &&
        (type == 'all' || s.mediaTypes.contains(type)));
  }

  String _formatSourceLabel(SourceInfo source) {
    if (source.id.startsWith('offline:')) {
      final cleanName = source.name
          .replaceFirst(RegExp(r'^\[Офлайн\]\s*', caseSensitive: false), '');
      return '💾 $cleanName (Офлайн)';
    }
    return source.name;
  }

  String _effectiveType(ExternalMedia result) {
    final t = result.type;
    if (t.isNotEmpty) return t;
    return _activeType != 'all' ? _activeType : 'tvshow';
  }

  String _resultKey(ExternalMedia result, [int? index]) {
    final base = '${result.type}:${result.externalId.isNotEmpty ? result.externalId : result.title}';
    return index != null ? '$base:$index' : base;
  }

  String _labelForCategory(String category, I18nDictionary t) {
    if (category == 'all') return t.tr('searchModal.allCategories');
    if (category == 'anime') return t.tr('navigation.anime');
    return t.tr('types.$category');
  }

  String _metaLine(ExternalMedia result) {
    return [
      result.releaseYear?.toString(),
      result.studio,
      result.author,
      result.platform,
    ].where((e) => e != null && e.isNotEmpty).join(' · ');
  }

  String? _countLabel(ExternalMedia result, I18nDictionary t) {
    if (result.totalCount == null) return null;
    final type = _effectiveType(result);
    final isNovel = result.type == 'book' &&
        (result.mangaFormat == 'light_novel' ||
            result.mangaFormat == 'web_novel' ||
            result.format == 'NOVEL');

    final String unit;
    if (type == 'anime' || type == 'tvshow') {
      unit = t.tr('searchModal.countUnits.tvshow');
    } else if (type == 'manga' || isNovel) {
      unit = t.tr('searchModal.countUnits.manga');
    } else if (type == 'movie') {
      unit = t.tr('searchModal.countUnits.movie');
    } else if (type == 'game') {
      unit = t.tr('searchModal.countUnits.game');
    } else {
      unit = t.tr('searchModal.countUnits.book');
    }

    return '${result.totalCount} $unit';
  }

  List<String> get _orderedSearchTypes {
    const typesToSearch = [
      'anime',
      'manga',
      'movie',
      'tvshow',
      'game',
      'book',
    ];
    return [
      ..._categoryOrder.where((c) => typesToSearch.contains(c)),
      ...typesToSearch.where((c) => !_categoryOrder.contains(c)),
    ];
  }

  CreateMediaBase _buildPayload(ExternalMedia result, I18nDictionary t) {
    final releaseDate = normalizeIsoDate(result.releaseDate, result.releaseYear);
    final endDate = normalizeIsoDate(result.endDate);
    final ratingsJson = result.ratings != null && result.ratings!.isNotEmpty
        ? jsonEncode(result.ratings!.map((r) => r.toJson()).toList())
        : null;
    final effective = _effectiveType(result);

    switch (effective) {
      case 'anime':
        final totalEpisodes =
            result.totalCount ?? result.episodes?.length ?? 0;
        final episodesData = result.episodes != null && result.episodes!.isNotEmpty
            ? jsonEncode(result.episodes!.map((e) => e.toJson()).toList())
            : null;
        return CreateTvShowPayload(
          isAnime: true,
          studio: result.studio,
          romajiTitle: result.romajiTitle ?? result.originalTitle,
          network: result.studio,
          durationMinutes: result.runtimeMinutes,
          episodeDurationMinutes: result.runtimeMinutes,
          seasons: [
            CreateSeasonPayload(
              seasonNumber: 1,
              title: 'Season 1',
              totalEpisodes: totalEpisodes,
              airDate: releaseDate,
              episodesData: episodesData,
              coverUrl: null,
              status: MediaStatus.planned,
              score: null,
              notes: null,
            ),
          ],
          title: result.title,
          status: MediaStatus.planned,
          altTitles: null,
          score: null,
          coverUrl: result.coverUrl,
          notes: null,
          description: result.description,
          trailerVideoId: result.trailerVideoId,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: result.externalId,
          externalSource: result.externalSource,
          importSource: null,
          externalRating: result.rating,
          externalRatingVotes: result.ratingVotes,
          externalRatingsJson: ratingsJson,
          releaseDate: releaseDate,
          endDate: endDate,
          releaseStatus: result.releaseStatus,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'tvshow':
        final episodesData = result.episodes != null && result.episodes!.isNotEmpty
            ? jsonEncode(result.episodes!.map((e) => e.toJson()).toList())
            : null;
        return CreateTvShowPayload(
          isAnime: false,
          studio: result.studio,
          romajiTitle: result.romajiTitle ?? result.originalTitle,
          network: result.studio,
          durationMinutes: result.runtimeMinutes,
          episodeDurationMinutes: result.runtimeMinutes,
          seasons: result.episodes != null
              ? [
                  CreateSeasonPayload(
                    seasonNumber: 1,
                    title: 'Season 1',
                    totalEpisodes:
                        result.totalCount ?? result.episodes!.length,
                    airDate: releaseDate,
                    episodesData: episodesData,
                    coverUrl: null,
                    status: MediaStatus.planned,
                    score: null,
                    notes: null,
                  ),
                ]
              : null,
          title: result.title,
          status: MediaStatus.planned,
          altTitles: null,
          score: null,
          coverUrl: result.coverUrl,
          notes: null,
          description: result.description,
          trailerVideoId: result.trailerVideoId,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: result.externalId,
          externalSource: result.externalSource,
          importSource: null,
          externalRating: result.rating,
          externalRatingVotes: result.ratingVotes,
          externalRatingsJson: ratingsJson,
          releaseDate: releaseDate,
          endDate: endDate,
          releaseStatus: result.releaseStatus,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'manga':
        return CreateMangaPayload(
          author: result.author,
          romajiTitle: result.romajiTitle ?? result.originalTitle,
          totalChapters: result.chapters ?? result.totalCount,
          totalVolumes: result.volumes ?? 1,
          currentVolume: 1,
          format: result.mangaFormat ?? result.format,
          volumes: null,
          title: result.title,
          status: MediaStatus.planned,
          altTitles: null,
          score: null,
          coverUrl: result.coverUrl,
          notes: null,
          description: result.description,
          trailerVideoId: result.trailerVideoId,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: result.externalId,
          externalSource: result.externalSource,
          importSource: null,
          externalRating: result.rating,
          externalRatingVotes: result.ratingVotes,
          externalRatingsJson: ratingsJson,
          releaseDate: releaseDate,
          endDate: endDate,
          releaseStatus: result.releaseStatus,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'book':
        final isNovel = result.mangaFormat == 'light_novel' ||
            result.mangaFormat == 'web_novel' ||
            result.format == 'NOVEL';
        return CreateBookPayload(
          author: (result.author != null && result.author!.trim().isNotEmpty)
              ? result.author!.trim()
              : t.tr('searchModal.unknownAuthor'),
          studio: result.studio,
          isbn: result.isbn,
          format: isNovel ? 'light_novel' : (result.format ?? 'book'),
          totalPages: isNovel ? null : result.totalCount,
          totalChapters:
              isNovel ? (result.chapters ?? result.totalCount) : null,
          totalVolumes: isNovel ? result.volumes : null,
          currentChapter: null,
          currentVolume: null,
          title: result.title,
          status: MediaStatus.planned,
          altTitles: null,
          score: null,
          coverUrl: result.coverUrl,
          notes: null,
          description: result.description,
          trailerVideoId: result.trailerVideoId,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: result.externalId,
          externalSource: result.externalSource,
          importSource: null,
          externalRating: result.rating,
          externalRatingVotes: result.ratingVotes,
          externalRatingsJson: ratingsJson,
          releaseDate: releaseDate,
          endDate: endDate,
          releaseStatus: result.releaseStatus,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'game':
        return CreateGamePayload(
          platform: (result.platform != null && result.platform!.trim().isNotEmpty)
              ? result.platform!.trim()
              : kFallbackPlatform,
          hoursPlayed: null,
          title: result.title,
          status: MediaStatus.planned,
          altTitles: null,
          score: null,
          coverUrl: result.coverUrl,
          notes: null,
          description: result.description,
          trailerVideoId: result.trailerVideoId,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: result.externalId,
          externalSource: result.externalSource,
          importSource: null,
          externalRating: result.rating,
          externalRatingVotes: result.ratingVotes,
          externalRatingsJson: ratingsJson,
          releaseDate: releaseDate,
          endDate: endDate,
          releaseStatus: result.releaseStatus,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
      case 'movie':
      default:
        return CreateMoviePayload(
          durationMinutes: result.runtimeMinutes ?? result.totalCount,
          director: null,
          isAnime: result.type == 'anime',
          studio: result.studio,
          romajiTitle: result.romajiTitle ?? result.originalTitle,
          title: result.title,
          status: MediaStatus.planned,
          altTitles: null,
          score: null,
          coverUrl: result.coverUrl,
          notes: null,
          description: result.description,
          trailerVideoId: result.trailerVideoId,
          franchiseId: null,
          franchiseName: null,
          franchiseOrder: null,
          externalId: result.externalId,
          externalSource: result.externalSource,
          importSource: null,
          externalRating: result.rating,
          externalRatingVotes: result.ratingVotes,
          externalRatingsJson: ratingsJson,
          releaseDate: releaseDate,
          endDate: endDate,
          releaseStatus: result.releaseStatus,
          genres: null,
          tags: null,
          unlockedAchievements: null,
          userPlatform: null,
        );
    }
  }

  void _triggerSearch({bool immediate = false, bool forceRefresh = false}) {
    final term = _queryController.text.trim();
    if (term.length < kMinQueryLength) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      setState(() {
        _results = [];
        _resultsByCategory = {};
        _loadingByCategory = {};
        _searching = false;
        _searchError = null;
      });
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = null;

    if (immediate) {
      _executeSearch(forceRefresh: forceRefresh);
    } else {
      _debounceTimer = Timer(Duration(milliseconds: widget.debounceMs), () {
        _executeSearch(forceRefresh: forceRefresh);
      });
    }
  }

  Future<void> _executeSearch({bool forceRefresh = false}) async {
    final term = _queryController.text.trim();
    if (term.length < kMinQueryLength) return;

    final sequence = ++_requestSequence;
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;

    setState(() {
      _searching = true;
      _searchError = null;
      _coverForceRefresh = forceRefresh;
    });

    final parsedUrl = parseMediaUrl(term);
    if (parsedUrl != null) {
      await _loadUrlResult(parsedUrl, sequence, token);
      return;
    }

    if (term.startsWith('http://') || term.startsWith('https://')) {
      final t = ref.read(tProvider);
      if (mounted) {
        setState(() {
          _results = [];
          _resultsByCategory = {};
          _loadingByCategory = {};
          _searching = false;
          _searchError = t.tr('searchModal.unsupportedLinkError');
        });
      }
      return;
    }

    await _loadResults(
      type: _activeType,
      term: term,
      sequence: sequence,
      token: token,
      source: _selectedSource.isNotEmpty ? _selectedSource : null,
      byCreator: _creatorFilter != null,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _loadUrlResult(
    ParsedMediaUrl parsed,
    int sequence,
    CancelToken token,
  ) async {
    if (token.isCancelled) return;
    final api = ref.read(apiClientProvider);
    final t = ref.read(tProvider);

    setState(() {
      _activeType = parsed.type;
      _searching = true;
      _searchError = null;
      _results = [];
      _resultsByCategory = {};
      _loadingByCategory = {parsed.type: true};
    });

    try {
      final details = await api.getExternalDetails(
        parsed.type,
        parsed.id,
        '',
        source: parsed.source,
        cancelToken: token,
      );

      if (sequence != _requestSequence || token.isCancelled || !mounted) return;

      if (details != null) {
        final item = details.copyWith(
          externalId: details.externalId.isNotEmpty ? details.externalId : parsed.id,
          type: details.type.isNotEmpty ? details.type : parsed.type,
          externalSource: details.externalSource ?? parsed.source,
          isDirectUrl: true,
        );

        setState(() {
          _results = [item];
          _resultsByCategory = {parsed.type: [item]};
          _loadingByCategory = {parsed.type: false};
          _searching = false;
        });
      } else {
        setState(() {
          _results = [];
          _resultsByCategory = {};
          _loadingByCategory = {};
          _searching = false;
          _searchError = t.tr('searchModal.directLinkError');
        });
      }
    } catch (e) {
      if (token.isCancelled || sequence != _requestSequence || !mounted) return;
      setState(() {
        _results = [];
        _resultsByCategory = {};
        _loadingByCategory = {};
        _searching = false;
        _searchError = e;
      });
    }
  }

  Future<void> _loadResults({
    required String type,
    required String term,
    required int sequence,
    required CancelToken token,
    String? source,
    bool? byCreator,
    bool? forceRefresh,
  }) async {
    if (token.isCancelled) return;
    final api = ref.read(apiClientProvider);

    if (type != 'all') {
      try {
        final found = await api.searchExternal(
          type,
          term,
          cancelToken: token,
          source: source,
          byCreator: byCreator,
          forceRefresh: forceRefresh,
        );

        if (sequence == _requestSequence && mounted) {
          setState(() {
            _results = found;
            _resultsByCategory = {type: found};
            _loadingByCategory = {type: false};
            _searching = false;
          });
        }
      } catch (e) {
        if (token.isCancelled || sequence != _requestSequence || !mounted) return;
        setState(() {
          _results = [];
          _resultsByCategory = {};
          _loadingByCategory = {type: false};
          _searching = false;
          _searchError = e;
        });
      }
      return;
    }

    final ordered = _orderedSearchTypes;
    setState(() {
      _results = [];
      _resultsByCategory = {};
      _loadingByCategory = {for (final cat in ordered) cat: true};
      _searching = true;
      _searchError = null;
    });

    var completed = 0;
    await Future.wait(ordered.map((cat) async {
      List<ExternalMedia> found = [];
      try {
        if (source != null && !_sourceSupports(source, cat)) {
          found = [];
        } else {
          found = await api.searchExternal(
            cat,
            term,
            cancelToken: token,
            source: source,
            byCreator: byCreator,
            forceRefresh: forceRefresh,
          );
        }
      } catch (_) {
        found = [];
      }

      if (sequence != _requestSequence || !mounted) return;

      final updated = Map<String, List<ExternalMedia>>.from(_resultsByCategory);
      for (final item in found) {
        final itemCat = item.type.isNotEmpty ? item.type : cat;
        updated.putIfAbsent(itemCat, () => []);
        if (!updated[itemCat]!.any((r) =>
            r.externalId == item.externalId &&
            r.externalSource == item.externalSource)) {
          updated[itemCat]!.add(item);
        }
      }
      updated.putIfAbsent(cat, () => []);

      final updatedLoading = Map<String, bool>.from(_loadingByCategory);
      updatedLoading[cat] = false;

      completed++;
      setState(() {
        _resultsByCategory = updated;
        _loadingByCategory = updatedLoading;
        _results = ordered.expand((c) => updated[c] ?? <ExternalMedia>[]).toList();
        if (completed >= ordered.length) {
          _searching = false;
        }
      });

    }));
  }

  void _scheduleHoverPrefetch(ExternalMedia result) {
    final type = _effectiveType(result);
    final key = detailsKey(type, result);

    final cache = ref.read(externalDetailsCacheProvider);
    if (cache.has(key)) return;
    if (_hoverPrefetchKey == key && (_hoverTimer?.isActive == true || _hoverCancelToken != null)) {
      return;
    }

    _cancelHoverPrefetch();
    _hoverPrefetchKey = key;

    _hoverTimer = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      final cancelToken = CancelToken();
      _hoverCancelToken = cancelToken;
      try {
        await cache.load(key, () async {
          final res = await ref.read(apiClientProvider).getExternalDetails(
            type,
            result.externalId,
            result.title,
            source: result.externalSource,
            cancelToken: cancelToken,
          );
          if (res == null) throw StateError('External details unavailable');
          return res;
        });
      } catch (_) {
        // Speculative prefetch errors are ignored
      } finally {
        if (_hoverCancelToken == cancelToken) {
          _hoverCancelToken = null;
        }
      }
    });
  }

  void _cancelHoverPrefetch([ExternalMedia? result]) {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    if (result != null) {
      final key = detailsKey(_effectiveType(result), result);
      if (_hoverPrefetchKey == key) {
        _hoverCancelToken?.cancel();
        _hoverCancelToken = null;
        _hoverPrefetchKey = null;
      }
    } else {
      _hoverCancelToken?.cancel();
      _hoverCancelToken = null;
      _hoverPrefetchKey = null;
    }
  }

  Future<void> _addResult(ExternalMedia result) async {
    final key = _resultKey(result);
    if (_addingKey.isNotEmpty) return;

    final api = ref.read(apiClientProvider);
    final t = ref.read(tProvider);

    // Toggle: if already in library, remove it
    final existingId = _addedKeys[key];
    if (existingId != null) {
      final updated = Map<String, String>.from(_addedKeys);
      updated.remove(key);
      setState(() => _addedKeys = updated);

      widget.onMediaRemoved?.call(existingId);
      try {
        await api.deleteMedia(existingId);
      } catch (e) {
        if (mounted) {
          final rollback = Map<String, String>.from(_addedKeys);
          rollback[key] = existingId;
          setState(() {
            _addedKeys = rollback;
            _addError = e;
          });
        }
      }
      return;
    }

    setState(() {
      _addingKey = key;
      _addError = null;
    });

    try {
      ExternalMedia targetResult = result;
      if (result.type == 'game' &&
          result.releaseDate == null &&
          result.externalId.isNotEmpty) {
        try {
          final details = await api.getExternalDetails(
            'game',
            result.externalId,
            result.title,
            source: result.externalSource,
          );
          if (details != null) {
            targetResult = result.copyWith(
              releaseDate: details.releaseDate ?? result.releaseDate,
              releaseYear: details.releaseYear ?? result.releaseYear,
              releaseStatus:
                  details.releaseStatus ?? result.releaseStatus,
              genres: details.genres ?? result.genres,
              platform: details.platform ?? result.platform,
            );
          }
        } catch (_) {}
      }

      final payload = _buildPayload(targetResult, t);
      final created = await api.createMedia(payload);

      if (mounted) {
        final updated = Map<String, String>.from(_addedKeys);
        updated[key] = created.id;
        setState(() => _addedKeys = updated);
      }

      widget.onMediaAdded(created);
      ref.read(jobsClientProvider.notifier).refreshPendingMatches();
    } catch (e) {
      if (mounted) {
        setState(() => _addError = e);
        final locale = ref.read(i18nProvider);
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: _formatErrorMessage(e, locale),
            type: ToastType.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingKey = '');
      }
    }
  }

  void _openPreview(ExternalMedia result) {
    setState(() => _previewItem = result);
  }

  String _formatErrorMessage(Object? error, Locale locale) {
    if (error == null) return '';
    if (error is String) return error;
    return errorMessage(error, locale);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox.shrink();

    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);
    final queryText = _queryController.text;
    final term = queryText.trim();
    final canSearch = term.length >= kMinQueryLength;
    final badge = detectQueryBadge(term);

    final disabledSources = _availableSources
        .where((s) => !s.isEnabled)
        .expand((s) => [s.name.toLowerCase(), s.id.toLowerCase()])
        .toSet();

    final enabledSources = _availableSources
        .where((s) =>
            s.isEnabled &&
            (_activeType == 'all' || s.mediaTypes.contains(_activeType)))
        .toList();

    return Stack(
      children: [
        TsundokuModal(
          isOpen: widget.isOpen,
          onClose: widget.onClose,
          size: ModalSize.search,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.tr('searchModal.eyebrow'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: Color(0xFFA78BFA), // accent-soft
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.tr('searchModal.title'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      color: const Color(0xFF94A3B8),
                      hoverColor: const Color(0x1AFFFFFF),
                      tooltip: t.tr('common.close'),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // Search bar + filter controls
              Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: Color(0x1AFFFFFF)),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Search text field
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0x14FFFFFF),
                              prefixIcon: const Icon(
                                LucideIcons.search,
                                size: 16,
                                color: Color(0xFF94A3B8),
                              ),
                              suffixIcon: badge != null
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0x0FFFFFFF),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0x1AFFFFFF),
                                            ),
                                          ),
                                          child: Text(
                                            badge.type == QueryBadgeType.link
                                                ? t.tr('searchModal.badgeLink')
                                                : t.tr('searchModal.badgeIsbn'),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              color: Color(0xB3FFFFFF),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                              hintText: t.tf('searchModal.placeholder',
                                  [_labelForCategory(_activeType, t)]),
                              hintStyle: const TextStyle(
                                  color: Color(0xFF64748B), fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x14FFFFFF)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x14FFFFFF)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x806366F1)),
                              ),
                            ),
                            onChanged: (_) => _triggerSearch(),
                            onSubmitted: (_) => _triggerSearch(immediate: true),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Force refresh button
                        SizedBox(
                          height: 40,
                          width: 40,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: const BorderSide(color: Color(0x1AFFFFFF)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              backgroundColor: const Color(0x0AFFFFFF),
                            ),
                            onPressed: () => _triggerSearch(
                              immediate: true,
                              forceRefresh: true,
                            ),
                            child: _searching
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFA78BFA),
                                    ),
                                  )
                                : const Icon(
                                    LucideIcons.refreshCw,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Category selector dropdown
                        SizedBox(
                          width: 130,
                          height: 40,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _activeType,
                            dropdownColor: const Color(0xFF1E2230),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: const Color(0x0AFFFFFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x1AFFFFFF)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x1AFFFFFF)),
                              ),
                            ),
                            items: kSearchCategories.map((cat) {
                              return DropdownMenuItem<String>(
                                value: cat,
                                child: Text(
                                  _labelForCategory(cat, t),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _activeType = val;
                                  if (_selectedSource.isNotEmpty &&
                                      !_sourceSupports(
                                          _selectedSource, val)) {
                                    _selectedSource = '';
                                  }
                                });
                                _triggerSearch(immediate: true);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Source selector dropdown
                        SizedBox(
                          width: 160,
                          height: 40,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedSource,
                            dropdownColor: const Color(0xFF1E2230),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: const Color(0x0AFFFFFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x1AFFFFFF)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0x1AFFFFFF)),
                              ),
                            ),
                            items: [
                              DropdownMenuItem<String>(
                                value: '',
                                child: Text(
                                  t.tr('searchModal.allSources'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ...enabledSources.map((s) {
                                return DropdownMenuItem<String>(
                                  value: s.id,
                                  child: Text(
                                    _formatSourceLabel(s),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedSource = val ?? '');
                              _triggerSearch(immediate: true);
                            },
                          ),
                        ),
                      ],
                    ),

                    // Creator chip
                    if (_creatorFilter != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x1A6366F1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0x4D6366F1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.tf('searchModal.creatorFilter',
                                      [_creatorFilter!]),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFA78BFA),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    setState(() => _creatorFilter = null);
                                    _triggerSearch(immediate: true);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: const Icon(
                                    LucideIcons.x,
                                    size: 14,
                                    color: Color(0xFFA78BFA),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Content body
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: _buildBody(t, locale, canSearch, disabledSources),
                ),
              ),
            ],
          ),
        ),

        // Preview modal
        if (_previewItem != null)
          ExternalDetailModal(
            item: _previewItem!,
            type: _effectiveType(_previewItem!),
            onClose: () => setState(() => _previewItem = null),
            actions: _buildPreviewActions(_previewItem!, t),
          ),
      ],
    );
  }

  Widget _buildPreviewActions(ExternalMedia item, I18nDictionary t) {
    final key = _resultKey(item);
    final isAdded = _addedKeys.containsKey(key);
    final isAdding = _addingKey == key;

    if (isAdded) {
      final targetId = _addedKeys[key]!;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0x1A10B981),
              side: const BorderSide(color: Color(0x3310B981)),
            ),
            onPressed: isAdding ? null : () => _addResult(item),
            icon: isAdding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF43F5E),
                    ),
                  )
                : const Icon(LucideIcons.check,
                    size: 14, color: Color(0xFF34D399)),
            label: Text(
              isAdding
                  ? t.tr('common.adding')
                  : t.tr('searchModal.inLibrary'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF34D399),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0x0AFFFFFF),
              side: const BorderSide(color: Color(0x1AFFFFFF)),
            ),
            onPressed: () {
              setState(() => _previewItem = null);
              widget.onNavigateToMedia?.call(targetId);
            },
            icon: const Icon(LucideIcons.arrowRight,
                size: 14, color: Colors.white),
            label: Text(
              t.tr('searchModal.preview'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6366F1),
      ),
      onPressed: isAdding ? null : () => _addResult(item),
      icon: isAdding
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(LucideIcons.plus, size: 14, color: Colors.white),
      label: Text(
        isAdding ? t.tr('common.adding') : t.tr('common.add'),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBody(
    I18nDictionary t,
    Locale locale,
    bool canSearch,
    Set<String> disabledSources,
  ) {
    if (_addError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x1AF43F5E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x4DF43F5E)),
            ),
            child: Text(
              _formatErrorMessage(_addError, locale),
              style: const TextStyle(fontSize: 13, color: Color(0xFFFECDD3)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildInnerBody(t, locale, canSearch, disabledSources)),
        ],
      );
    }

    return _buildInnerBody(t, locale, canSearch, disabledSources);
  }

  Widget _buildInnerBody(
    I18nDictionary t,
    Locale locale,
    bool canSearch,
    Set<String> disabledSources,
  ) {
    if (!canSearch) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: const Color(0x0FFFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.search,
                size: 22,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.tr('searchModal.emptyQueryTitle'),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('searchModal.emptyQueryHint'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    if (_searching && _activeType != 'all') {
      return _buildSkeletons();
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatErrorMessage(_searchError, locale),
              style: const TextStyle(fontSize: 14, color: Color(0xFFFECDD3)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              t.tr('searchModal.errorHint'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty && !_searching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              t.tr('searchModal.emptyTitle'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.tr('searchModal.emptyHint'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    if (_activeType == 'all') {
      return _buildGroupedResults(t, disabledSources);
    }

    return _buildSingleCategoryList(t, _results, disabledSources);
  }

  Widget _buildSkeletons() {
    return ListView.separated(
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 112,
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 200,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupedResults(
    I18nDictionary t,
    Set<String> disabledSources,
  ) {
    final ordered = _orderedSearchTypes;

    return ListView(
      children: [
        for (final cat in ordered) ...[
          Builder(builder: (context) {
            final items = _resultsByCategory[cat] ?? [];
            final loading = _loadingByCategory[cat] == true;
            if (items.isEmpty && !loading) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header
                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0x12FFFFFF)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              _labelForCategory(cat, t).toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: Color(0xFFA78BFA),
                              ),
                            ),
                            if (loading) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFA78BFA),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!loading)
                          InkWell(
                            onTap: () {
                              setState(() => _activeType = cat);
                              _triggerSearch(immediate: true);
                            },
                            child: Row(
                              children: [
                                Text(
                                  t.tf('searchModal.showMoreCount',
                                      [items.length]),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  LucideIcons.chevronRight,
                                  size: 14,
                                  color: Color(0xFF94A3B8),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (loading)
                    _buildSkeletons()
                  else
                    Column(
                      children: [
                        for (int i = 0; i < items.take(5).length; i++) ...[
                          _buildResultCard(
                            t,
                            items[i],
                            disabledSources,
                            index: i,
                          ),
                          if (i < items.take(5).length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSingleCategoryList(
    I18nDictionary t,
    List<ExternalMedia> items,
    Set<String> disabledSources,
  ) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildResultCard(
          t,
          items[index],
          disabledSources,
          index: index,
        );
      },
    );
  }

  Widget _buildResultCard(
    I18nDictionary t,
    ExternalMedia result,
    Set<String> disabledSources, {
    int? index,
  }) {
    final key = _resultKey(result);
    final isAdded = _addedKeys.containsKey(key);
    final isAdding = _addingKey == key;
    final isNovel = result.type == 'book' &&
        (result.mangaFormat == 'light_novel' ||
            result.mangaFormat == 'web_novel' ||
            result.format == 'NOVEL');

    final meta = _metaLine(result);
    final count = _countLabel(result, t);

    return MouseRegion(
      onEnter: (_) => _scheduleHoverPrefetch(result),
      onExit: (_) => _cancelHoverPrefetch(result),
      child: InkWell(
        onTap: () => _openPreview(result),
        borderRadius: BorderRadius.circular(8),
        child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x0FFFFFFF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover poster
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 72,
                height: 104,
                color: const Color(0xFF151821),
                child: result.coverUrl != null && result.coverUrl!.isNotEmpty
                    ? Image.network(
                        proxiedExternalCoverUrl(
                          result.coverUrl!,
                          forceRefresh: _coverForceRefresh,
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            LucideIcons.image,
                            size: 24,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          LucideIcons.image,
                          size: 24,
                          color: Color(0xFF64748B),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Action button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (result.originalTitle != null &&
                                result.originalTitle!.isNotEmpty)
                              Text(
                                result.originalTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Add / Added buttons
                      if (isAdded) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              iconSize: 14,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0x1A10B981),
                                shape: const CircleBorder(
                                  side: BorderSide(color: Color(0x3310B981)),
                                ),
                              ),
                              tooltip: t.tr('searchModal.added'),
                              onPressed:
                                  isAdding ? null : () => _addResult(result),
                              icon: isAdding
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFF43F5E),
                                      ),
                                    )
                                  : const Icon(LucideIcons.check,
                                      color: Color(0xFF34D399)),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              iconSize: 14,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0x0AFFFFFF),
                                shape: const CircleBorder(
                                  side: BorderSide(color: Color(0x1AFFFFFF)),
                                ),
                              ),
                              tooltip: t.tr('searchModal.goToTitle'),
                              onPressed: () {
                                final targetId = _addedKeys[key];
                                if (targetId != null) {
                                  widget.onClose();
                                  widget.onNavigateToMedia?.call(targetId);
                                }
                              },
                              icon: const Icon(LucideIcons.arrowRight,
                                  color: Color(0xFFA78BFA)),
                            ),
                          ],
                        ),
                      ] else ...[
                        IconButton(
                          iconSize: 14,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0x0AFFFFFF),
                            shape: const CircleBorder(
                              side: BorderSide(color: Color(0x1AFFFFFF)),
                            ),
                          ),
                          tooltip: t.tr('common.add'),
                          onPressed: isAdding ? null : () => _addResult(result),
                          icon: isAdding
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFA78BFA),
                                  ),
                                )
                              : const Icon(LucideIcons.plus,
                                  color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Badges line
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (result.isDirectUrl == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x2610B981),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0x6610B981)),
                          ),
                          child: Text(
                            t.tr('searchModal.foundViaDirectLink'),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6EE7B7),
                            ),
                          ),
                        ),
                      if (result.externalSource != null &&
                          result.externalSource!.isNotEmpty) ...[
                        Builder(builder: (context) {
                          final colors =
                              sourceBadgeColors(result.externalSource);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.bg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: colors.border),
                            ),
                            child: Text(
                              result.externalSource!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                              ),
                            ),
                          );
                        }),
                      ],
                      if (isNovel)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x26A855F7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0x4DA855F7)),
                          ),
                          child: const Text(
                            'Ранобэ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD8B4FE),
                            ),
                          ),
                        ),
                      if (result.rating != null &&
                          (result.externalSource == null ||
                              !disabledSources.contains(
                                  result.externalSource!.toLowerCase())))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.star,
                              size: 11,
                              color: Color(0xFFFBBF24),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              result.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      if (count != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x14FFFFFF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            count,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Description clamp
                  if (result.description != null &&
                      result.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      result.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
