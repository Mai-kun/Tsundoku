/// 1:1 port of `mediatracker-ui/src/views/MediaDetailView.svelte`.
///
/// Детальная страница: скелетон/error-box, DetailSidebar + DetailHeader +
/// DetailTabs + панель табов (AnimatedSwitcher — directional panelIn/panelOut),
/// Related (sequence + stored-restore + persist), preview-модал, прогресс-
/// баннер (optimistic + debounce + promote/undo/keepStatus), серии (season
/// writes + series counter), статусы/оценки, refresh/relink/fillMissing/
/// overwrite-модалки, achievements/recommendations, jobs-наблюдатель.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../entities/media/model/progress_rules.dart';
import '../entities/media/model/series_step.dart';
import '../features/drop-reason/drop_reason_prompt.dart';
import '../features/prefetch-details/media_detail_prefetch.dart';
import '../features/update-progress/optimistic_progress.dart';
import '../features/update-progress/status_promotion_toast.dart';
import '../shared/api/api.dart';
import '../shared/api/jobs_client.dart';
import '../shared/i18n/index.dart';
import '../shared/types/dtos.dart';
import '../shared/types/enums.dart';
import '../shared/types/models.dart';
import '../shared/theme/tsundoku_theme.dart';
import '../shared/theme/tsundoku_tokens.dart';
import '../shared/ui/toast.dart';
import '../shared/utils/prefetch_cache.dart';
import '../shared/utils/progress_debounce.dart';
import '../widgets/media-detail/detail_formatters.dart';
import '../widgets/media-detail/detail_header.dart' as detail_header;
import '../widgets/media-detail/detail_sidebar.dart';
import '../widgets/media-detail/detail_tabs.dart';
import '../widgets/media-detail/detail_types.dart';
import '../widgets/media-detail/external_mapping.dart';
import '../widgets/media-detail/fill_missing_modal.dart';
import '../widgets/media-detail/overwrite_confirm_modal.dart';
import '../widgets/media-detail/panels/related_preview_modal.dart';
import '../widgets/media-detail/rating_badges.dart';
import '../widgets/media-detail/related_matching.dart';
import '../widgets/media-detail/relation_sources.dart';
import '../widgets/media-detail/relink_source_modal.dart';
import '../widgets/media-detail/sync_rows_skeleton.dart';
import '../widgets/media-detail/tabs/episodes_tab.dart';
import '../widgets/media-detail/tabs/gallery_tab.dart';
import '../widgets/media-detail/tabs/overview_tab.dart';
import '../widgets/media-detail/tabs/recommendations_tab.dart';
import '../widgets/media-detail/tabs/related_tab.dart';

// ---------------------------------------------------------------------------
// Module-level (script module Svelte).
// ---------------------------------------------------------------------------

/// Offline database rating rows ("Offline Database", "[Офлайн] файл") never
/// render as badges.
final RegExp _offlineSourceRe =
    RegExp('offline|офлайн', caseSensitive: false);

/// The LibSocial umbrella and all of its per-site spellings share one rating
/// row.
final RegExp _libFamilyRe = RegExp(
    'sociallib|mangalib|animelib|ranobelib|slashlib|hentailib',
    caseSensitive: false);

/// Обновление после мутации: кэш заведомо устарел, поэтому идём в сеть и
/// перезаписываем его.
Future<MediaDetail> _refreshMediaDetail(ProviderContainer container, String id) {
  container.read(mediaDetailCacheProvider).invalidate(id);
  return loadMediaDetailRef(container, id);
}

/// TMDb and RAWG report a date string rather than a year; the timeline needs
/// the year alone.
int? _yearOf(String? releaseDate) =>
    (releaseDate != null && releaseDate.length >= 4)
        ? int.tryParse(releaseDate.substring(0, 4))
        : null;

// ---------------------------------------------------------------------------
// Stored Related-tab payload (localStorage-копия Svelte → поле строки
// relatedMediaJson; нормализация — 1-в-1 с normalizeStoredRelatedEntry).
// ---------------------------------------------------------------------------

/// Normalizes a raw stored related entry. Can be either an ExternalRelation
/// shape (from backend MediaEnrichmentJob: RelationType/relationType + Media)
/// or a RelatedEntry shape (from client persistRelated).
RelatedEntry _normalizeStoredRelatedEntry(
    Object? raw, int index, I18nDictionary t) {
  if (raw is! Map<String, Object?>) {
    return const RelatedEntry(
        id: 'rel-?', title: 'Unknown', type: 'anime');
  }

  final media = (raw['Media'] ?? raw['media']) as Map<String, Object?>?;
  if (media != null) {
    final rawRelType = (raw['RelationType'] ?? raw['relationType'] ??
            raw['rawRelationType'] ?? 'OTHER') as String;
    final score = _num(_firstNum(media, const ['Rating', 'rating', 'score']));
    final extSource =
        _firstStr(media, const ['ExternalSource', 'externalSource']);
    final ratingsRaw = media['Ratings'] ?? media['ratings'];
    List<({String source, double rating})>? ratings;
    if (ratingsRaw is List) {
      ratings = ratingsRaw
          .whereType<Map<String, Object?>>()
          .map((r) => (
                source: (_firstStr(r, const ['Source', 'source']) ??
                    extSource ??
                    ''),
                rating: _num(_firstNum(r, const ['Rating', 'rating'])) ?? 0.0,
              ))
          .toList();
    } else if (score != null && extSource != null) {
      ratings = [(source: extSource, rating: score)];
    }

    final releaseDate = _firstStr(media, const ['ReleaseDate', 'releaseDate']);
    final releaseYear =
        _intOrNull(_firstNum(media, const ['ReleaseYear', 'releaseYear']));
    final year = releaseYear ?? _yearOf(releaseDate);

    final relId = _firstStr(media, const ['ExternalId', 'externalId', 'id']) ??
        (raw['id']?.toString()) ??
        'rel-\$index';

    return RelatedEntry(
      id: relId,
      title: _firstStr(media, const ['Title', 'title']) ?? 'Title',
      originalTitle:
          _firstStr(media, const ['OriginalTitle', 'originalTitle']),
      romajiTitle: _firstStr(media, const ['RomajiTitle', 'romajiTitle']),
      coverUrl: _firstStr(media, const ['CoverUrl', 'coverUrl']),
      bannerUrl: _firstStr(media, const ['BannerUrl', 'bannerUrl']),
      type: _firstStr(media, const ['Type', 'type']) ?? 'anime',
      format: _firstStr(media, const ['Format', 'format']),
      year: year,
      releaseDate: releaseDate,
      endDate: _firstStr(media, const ['EndDate', 'endDate']),
      releaseStatus: _firstStr(media, const ['ReleaseStatus', 'releaseStatus']),
      score: score,
      ratings: ratings
          ?.map((r) =>
              RatingBadge(source: r.source, score: r.rating))
          .toList(),
      trailerVideoId:
          _firstStr(media, const ['TrailerVideoId', 'trailerVideoId']),
      duration:
          _intOrNull(_firstNum(media, const ['RuntimeMinutes', 'runtimeMinutes', 'duration'])),
      episodes:
          _intOrNull(_firstNum(media, const ['TotalCount', 'totalCount', 'episodes'])),
      chapters: _intOrNull(_firstNum(media, const ['Chapters', 'chapters'])),
      volumes: _intOrNull(_firstNum(media, const ['Volumes', 'volumes'])),
      studio: _firstStr(media, const ['Studio', 'studio']),
      author: _firstStr(media, const ['Author', 'author']),
      externalSource: extSource,
      rawRelationType: rawRelType,
      relationType: (raw['relationType'] is String &&
              (raw['relationType'] as String) != rawRelType)
          ? raw['relationType'] as String
          : formatRelationType(rawRelType, t),
    );
  }

  final rawRelType = ((raw['rawRelationType'] ??
          raw['RelationType'] ??
          raw['relationType']) as String?);
  final score = _num(_firstNum(raw, const ['score', 'rating', 'Rating']));
  final releaseDate = _firstStr(raw, const ['releaseDate', 'ReleaseDate']);
  final year = _intOrNull(_firstNum(raw, const ['year', 'ReleaseYear'])) ??
      _yearOf(releaseDate);
  final relId = (raw['id'] ?? raw['externalId'] ?? raw['ExternalId'])
          ?.toString() ??
      'rel-\$index';

  return RelatedEntry(
    id: relId,
    title: _firstStr(raw, const ['title', 'Title']) ?? 'Title',
    originalTitle: _firstStr(raw, const ['originalTitle', 'OriginalTitle']),
    romajiTitle: _firstStr(raw, const ['romajiTitle', 'RomajiTitle']),
    coverUrl: _firstStr(raw, const ['coverUrl', 'CoverUrl']),
    bannerUrl: _firstStr(raw, const ['bannerUrl', 'BannerUrl']),
    type: _firstStr(raw, const ['type', 'Type']) ?? 'anime',
    format: _firstStr(raw, const ['format', 'Format']),
    year: year,
    releaseDate: releaseDate,
    endDate: _firstStr(raw, const ['endDate', 'EndDate']),
    releaseStatus: _firstStr(raw, const ['releaseStatus', 'ReleaseStatus']),
    score: score,
    ratings: (raw['ratings'] ?? raw['Ratings']) is List
        ? ((raw['ratings'] ?? raw['Ratings']) as List)
            .whereType<Map<String, Object?>>()
            .map((r) => RatingBadge(
                  source: r['source'] as String? ?? r['Source'] as String? ?? '',
                  score: _num(r['rating'] ?? r['Rating']),
                ))
            .toList()
        : null,
    description: _firstStr(raw, const ['description', 'Description']),
    trailerVideoId: _firstStr(raw, const ['trailerVideoId', 'TrailerVideoId']),
    duration: _intOrNull(
        _firstNum(raw, const ['duration', 'runtimeMinutes', 'RuntimeMinutes'])),
    episodes:
        _intOrNull(_firstNum(raw, const ['episodes', 'totalCount', 'TotalCount'])),
    chapters: _intOrNull(_firstNum(raw, const ['chapters', 'Chapters'])),
    volumes: _intOrNull(_firstNum(raw, const ['volumes', 'Volumes'])),
    studio: _firstStr(raw, const ['studio', 'Studio']),
    author: _firstStr(raw, const ['author', 'Author']),
    externalSource: _firstStr(raw, const ['externalSource', 'ExternalSource']),
    rawRelationType: rawRelType,
    relationType: (raw['relationType'] is String &&
            (raw['relationType'] as String) != rawRelType)
        ? raw['relationType'] as String
        : (rawRelType != null
            ? formatRelationType(rawRelType, t)
            : null),
  );
}

/// TS RelatedEntry-шейп для relatedMediaJson (detail_types без toJson —
/// YAGNI-конвенция; сериализация локальная).
Map<String, Object?> _relatedEntryToJson(RelatedEntry e) => <String, Object?>{
      'id': e.id,
      'title': e.title,
      'originalTitle': e.originalTitle,
      'romajiTitle': e.romajiTitle,
      'coverUrl': e.coverUrl,
      'bannerUrl': e.bannerUrl,
      'type': e.type,
      'format': e.format,
      'year': e.year,
      'relationType': e.relationType,
      'rawRelationType': e.rawRelationType,
      'score': e.score,
      'ratings': e.ratings
          ?.map((r) => {'source': r.source, 'rating': r.score})
          .toList(),
      'description': e.description,
      'trailerVideoId': e.trailerVideoId,
      'duration': e.duration,
      'episodes': e.episodes,
      'chapters': e.chapters,
      'volumes': e.volumes,
      'studio': e.studio,
      'author': e.author,
      'releaseDate': e.releaseDate,
      'endDate': e.endDate,
      'releaseStatus': e.releaseStatus,
      'externalSource': e.externalSource,
      'localItem': e.localItem?.toJson(),
    };

num? _firstNum(Map<String, Object?> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v;
  }
  return null;
}

String? _firstStr(Map<String, Object?> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is String) return v;
  }
  return null;
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

/// The Related tab is the one panel whose content lives outside the database,
/// so a reload used to come back empty and the user had to name a source
/// again. Reading the copy stored on the row costs nothing and puts the list
/// back on F5.
List<RelatedEntry>? _readStoredRelated(MediaDetail? item, I18nDictionary t) {
  final json = item?.relatedMediaJson;
  if (json == null || json.isEmpty) return null;
  try {
    final parsed = jsonDecode(json);
    if (parsed is! List) return null;
    return [
      for (var i = 0; i < parsed.length; i++)
        _normalizeStoredRelatedEntry(parsed[i], i, t),
    ];
  } catch (_) {
    return null;
  }
}

/// Persisted alongside the list so the source picker opens on the provider
/// that produced it. Svelte мутировал item на месте → иммутабельная копия +
/// fire-and-forget updateMedia.
void _persistRelated(
    ProviderContainer container,
    MediaDetail item,
    List<RelatedEntry> entries,
    String source) {
  final payload = jsonEncode(entries.map(_relatedEntryToJson).toList());
  unawaited(container
      .read(apiClientProvider)
      .updateMedia(item.id, UpdateMediaPayload(
        relatedMediaJson: payload,
        relatedSource: source,
      ))
      .then((_) {}, onError: (Object _) {}));
}

/// Achievements are an external payload that only changes when the provider
/// updates, so they are stored on the row on first fetch and replayed on every
/// later open.
void _persistGamePayloads(
    ProviderContainer container,
    MediaDetail item,
    List<GameAchievementItem> achievements,
    int total) {
  if (item.achievementsJson != null) return;
  if (achievements.isEmpty) return;
  final payload = jsonEncode(<String, Object?>{
    'total': total,
    'items': [
      for (final a in achievements)
        {'name': a.name, 'description': a.description, 'iconUrl': a.iconUrl},
    ],
  });
  unawaited(container
      .read(apiClientProvider)
      .updateMedia(item.id, UpdateMediaPayload(achievementsJson: payload))
      .then((_) {}, onError: (Object _) {}));
}

// ---------------------------------------------------------------------------
// Вью.
// ---------------------------------------------------------------------------

class MediaDetailView extends ConsumerStatefulWidget {
  final String mediaId;
  final int refreshKey;
  final VoidCallback onBack;
  final VoidCallback onUpdate;
  final Future<void> Function(String id) onDelete;
  final void Function(MediaItem item) onEdit;
  final void Function(MediaItem item) onOpenRelated;
  final void Function(Object? context) onSearch;
  final VoidCallback onOpenLists;
  final SubTab initialSubTab;

  const MediaDetailView({
    super.key,
    required this.mediaId,
    required this.refreshKey,
    required this.onBack,
    required this.onUpdate,
    required this.onDelete,
    required this.onEdit,
    required this.onOpenRelated,
    required this.onSearch,
    required this.onOpenLists,
    this.initialSubTab = SubTab.overview,
  });

  @override
  ConsumerState<MediaDetailView> createState() => _MediaDetailViewState();
}

class _MediaDetailViewState extends ConsumerState<MediaDetailView> {
  static const List<SubTab> _tabOrder = <SubTab>[
    SubTab.overview,
    SubTab.episodes,
    SubTab.gallery,
    SubTab.related,
    SubTab.recommendations,
  ];

  MediaDetail? _media;
  bool _isLoading = true;
  Object? _loadError;
  int _requestSequence = 0;
  String? _trackedMediaId;

  late SubTab _activeSubTab = widget.initialSubTab;

  /// Directional tab panels: forward tabs enter from the right, backward from
  /// the left.
  int _tabDirection = 1;

  String _episodeSortOrder = 'asc';
  bool _synopsisExpanded = false;
  bool _userRatingPopoverOpen = false;
  List<SourceInfo> _availableSources = const <SourceInfo>[];
  Timer? _ratingCloseTimer;

  List<RelatedEntry> _related = const <RelatedEntry>[];
  bool _relatedLoading = false;
  Object? _relatedError;
  int _relatedSequence = 0;
  RelatedViewMode _relatedViewMode = RelatedViewMode.grouped;
  String? _lastRelatedSource;
  String? _autoRelatedAttemptedId;

  RelatedEntry? _previewRelatedItem;
  MediaStatus _previewStatus = MediaStatus.planned;
  bool _previewAddingBusy = false;
  bool _previewRelatedLoading = false;
  // Svelte: isEnriching пишется, но нигде не читается — 1-в-1 стейт.
  // ignore: unused_field
  bool _isEnriching = false;

  List<ExternalRecommendation> _recommendations = const <ExternalRecommendation>[];

  bool _deleteBusy = false;
  Object? _deleteError;

  MediaStatus _statusValue = MediaStatus.planned;
  bool _statusBusy = false;
  Object? _statusError;

  int? _scoreValue;
  bool _ratingBusy = false;
  // Svelte: ratingError пишется, но нигде не читается — 1-в-1 стейт.
  // ignore: unused_field
  Object? _ratingError;

  int _progressValue = 0;
  int _committedProgress = 0;
  int? _pendingSnapshot;
  Object? _progressError;
  String _episodeBusy = '';

  /// The job whose completion already triggered a refetch, so it only fires
  /// once per run.
  String? _settledJobId;

  bool _refreshInFlight = false;
  Object? _refreshError;
  bool _relinkOpen = false;
  bool _overwritePromptOpen = false;
  bool _fillMissingOpen = false;
  bool _fillMissingBusy = false;

  bool _isSynopsisTranslated = false;
  bool _translatingSynopsis = false;
  String? _translatedSynopsis;

  List<GameAchievementItem> _gameAchievements = const <GameAchievementItem>[];
  int _gameAchievementsTotal = 0;
  bool _gameAchievementsLoading = false;
  bool _achievementsBusy = false;

  String _watchedOnInput = '';
  bool _watchedOnDirty = false;

  /// In-memory caches to prevent progress spinner / jog wheel from
  /// re-fetching.
  final PrefetchCache<({List<GameAchievementItem> achievements, int total})>
      _achievementsCache = createPrefetchCache(5 * 60 * 1000);
  final Set<String> _enrichedMediaIds = <String>{};

  bool _seriesCommitBusy = false;
  int? _seriesPendingValue;
  int? _seriesBaseline;

  late final ProgressDebouncer _progressDebounce = createProgressDebounce(
    ProgressDebounceOptions(
      send: (id, value) =>
          ref.read(apiClientProvider).setProgress(id, value),
      buildRequest: (id, value) => ProgressRequest(
        url: '/api/media/\$id/progress',
        body: {'currentProgress': value},
      ),
      onCommitted: (value) {
        if (!mounted) return;
        setState(() {
          _committedProgress = value;
          _pendingSnapshot = null;
        });
        final id = _media?.id;
        if (id != null) {
          resolveOptimisticProgress(_container, id, value);
          writeCardProgress(_media!, value);
        }
        if (_progressValue == value) widget.onUpdate();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _progressValue = _pendingSnapshot ?? _committedProgress;
          _committedProgress = _progressValue;
          _pendingSnapshot = null;
          _progressError = error;
        });
        final id = _media?.id;
        if (id != null) clearOptimisticProgress(_container, id);
      },
    ),
  );

  final FocusNode _escapeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // $effect(refreshKey, mediaId): первый load — после монтирования
    // (эффекты Svelte выполняются post-mount; containerOf недоступен в
    // initState).
    _trackedMediaId = widget.mediaId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_load(widget.mediaId, ++_requestSequence, true));
      }
    });
    // $effect: sources для бейджей рейтингов.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref
          .read(apiClientProvider)
          .getSources()
          .then((res) {
            if (res.isNotEmpty && mounted) {
              setState(() => _availableSources = res);
            }
          })
          .catchError((Object _) {}));
    });
  }

  @override
  void didUpdateWidget(covariant MediaDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // $effect(refreshKey, mediaId).
    if (oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.mediaId != widget.mediaId) {
      final isNew = _trackedMediaId != widget.mediaId;
      _trackedMediaId = widget.mediaId;
      unawaited(_load(widget.mediaId, ++_requestSequence, isNew));
    }
  }

  @override
  void dispose() {
    // $effect cleanup: уход с незакоммиченным шагом → keepalive-PUT +
    // пометка для грид-родителя.
    if (_progressValue != _committedProgress) widget.onUpdate();
    unawaited(_progressDebounce.flush(keepalive: true));
    _ratingCloseTimer?.cancel();
    _escapeFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Rating popover: hover-open с отложенным закрытием 180ms.
  // ------------------------------------------------------------------

  void _openRatingPopover() {
    _ratingCloseTimer?.cancel();
    _ratingCloseTimer = null;
    if (!_userRatingPopoverOpen) {
      setState(() => _userRatingPopoverOpen = true);
    }
  }

  void _closeRatingPopover() {
    _ratingCloseTimer?.cancel();
    _ratingCloseTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _userRatingPopoverOpen = false);
    });
  }

  void _hideRatingPopover() {
    _ratingCloseTimer?.cancel();
    _ratingCloseTimer = null;
    if (_userRatingPopoverOpen) {
      setState(() => _userRatingPopoverOpen = false);
    }
  }

  // ------------------------------------------------------------------
  // Нагрузка карточки.
  // ------------------------------------------------------------------

  Future<void> _load(String id, int sequence, bool isNew,
      {bool forceRefresh = false}) async {
    if (isNew) {
      setState(() {
        _media = null;
        _isLoading = true;
        _loadError = null;
        _userRatingPopoverOpen = false;
        _synopsisExpanded = false;
        _isSynopsisTranslated = false;
        _translatedSynopsis = null;
        _translatingSynopsis = false;
        _activeSubTab = widget.initialSubTab;
        _related = const <RelatedEntry>[];
        _relatedError = null;
        _previewRelatedItem = null;
        _recommendations = const <ExternalRecommendation>[];
        _progressError = null;
        _statusError = null;
        _ratingError = null;
        _deleteError = null;
        _deleteBusy = false;
      });
    }

    try {
      // Префетч по наведению отдаёт готовый объект; после мутаций кэш протух —
      // берём сеть.
      final loaded = (isNew && !forceRefresh)
          ? await loadMediaDetailRef(_container, id)
          : await _refreshMediaDetail(_container, id);
      if (sequence != _requestSequence || !mounted) return;
      setState(() {
        _media = loaded;
        _syncFrom(loaded);
        // $effect: watchedOnInput следует за сервером, пока поле не тронуто.
        if (!(_watchedOnDirty && !isNew)) {
          _watchedOnInput = loaded.watchedOn ?? '';
        }
        if (isNew) {
          _watchedOnDirty = false;
          _watchedOnInput = loaded.watchedOn ?? '';
        }

        // Opening a card must not fetch anything, but the Related tab is the
        // one panel whose content lives outside the DB, so the copy stored on
        // the row is put back here.
        final storedRelated = _readStoredRelated(loaded, _t);
        if (storedRelated != null) {
          _related = storedRelated;
          _lastRelatedSource = loaded.relatedSource;
        } else {
          _related = const <RelatedEntry>[];
        }

        // Same for the game payloads.
        _readStoredGamePayloads(loaded);

        if (forceRefresh) {
          if (loaded.type == MediaType.game) {
            unawaited(_loadGameAchievements(loaded, force: true));
          }
          // Restore cached translation if available for current language.
          final targetLang = _isEnLocale ? 'en' : 'ru';
          if ((loaded.translatedSynopsis ?? '').isNotEmpty &&
              loaded.translationLanguage == targetLang) {
            _translatedSynopsis = loaded.translatedSynopsis;
            _isSynopsisTranslated = true;
          }
          unawaited(_loadRelated(loaded, null));
          unawaited(_triggerBackgroundEnrichment(loaded, sequence,
              forceRefresh: true));
        } else if (loaded.type == MediaType.game) {
          final cached = _achievementsCache.peek(loaded.id);
          if (cached != null) {
            _gameAchievements = cached.achievements;
            _gameAchievementsTotal = cached.total;
          }
        }
      });
    } catch (error) {
      if (sequence == _requestSequence && mounted) {
        setState(() {
          _loadError = error;
          if (isNew) _media = null;
        });
      }
    } finally {
      if (sequence == _requestSequence && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _readStoredGamePayloads(MediaDetail item) {
    if (item.achievementsJson != null && item.achievementsJson!.isNotEmpty) {
      try {
        final parsed = jsonDecode(item.achievementsJson!);
        if (parsed is Map<String, Object?>) {
          final items = parsed['items'];
          if (items is List && items.isNotEmpty) {
            _gameAchievements = items
                .whereType<Map<String, Object?>>()
                .map(GameAchievementItem.fromJson)
                .toList();
            _gameAchievementsTotal = (parsed['total'] is num)
                ? (parsed['total'] as num).toInt()
                : items.length;
          }
        }
      } catch (_) {
        // A corrupt blob is dropped rather than crashing the panel.
      }
    }

    // Recommendations come back with the detail payload, already parsed by the
    // server, so the tab is populated on F5 without the panel issuing a request
    // of its own.
    final recs = item.recommendations;
    if (recs != null && recs.isNotEmpty) {
      _recommendations = recs;
    }
  }

  void _syncFrom(MediaDetail item) {
    setState(() {
      _statusValue = item.status;
      _scoreValue = item.score;
      final info = readProgress(item, _t);
      // Anti-rollback: a card step whose debounce/PUT is still in flight must
      // not be overwritten by the (stale) freshly loaded server value.
      _progressValue = reconcileProgress(_container, item.id, info?.current ?? 0);
      _committedProgress = info?.current ?? 0;
      _pendingSnapshot = null;
    });
  }

  // ------------------------------------------------------------------
  // Game achievements.
  // ------------------------------------------------------------------

  Future<void> _loadGameAchievements(MediaItem item, {bool force = false}) async {
    if (item.type != MediaType.game) return;
    if (force) _achievementsCache.invalidate(item.id);
    final cached = _achievementsCache.peek(item.id);
    if (cached != null) {
      setState(() {
        _gameAchievements = cached.achievements;
        _gameAchievementsTotal = cached.total;
      });
      return;
    }
    setState(() => _gameAchievementsLoading = true);
    try {
      // load() отдаёт тот же промис, если запрос по этому id уже в полёте.
      final result = await _achievementsCache.load(item.id, () async {
        final res = await ref.read(apiClientProvider).getGameAchievements(
              steamAppId:
                  (item.externalSource?.toLowerCase() == 'steam') ? item.externalId : null,
              rawgId:
                  (item.externalSource?.toLowerCase() == 'rawg') ? item.externalId : null,
              title: item.title,
              externalSource: item.externalSource,
              externalId: item.externalId,
            );
        return (
          achievements: res.achievements,
          total: res.totalCount,
        );
      });
      if (!mounted) return;
      setState(() {
        _gameAchievements = result.achievements;
        _gameAchievementsTotal = result.total;
      });
      // First successful fetch: write it to the row so the next open (and F5)
      // is instant.
      final media = _media;
      if (media != null) {
        _persistGamePayloads(_container, media, result.achievements, result.total);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gameAchievements = const <GameAchievementItem>[];
        _gameAchievementsTotal = 0;
      });
    } finally {
      if (mounted) setState(() => _gameAchievementsLoading = false);
    }
  }

  // ------------------------------------------------------------------
  // Background enrichment.
  // ------------------------------------------------------------------

  Future<void> _triggerBackgroundEnrichment(
      MediaDetail current, int sequence,
      {bool forceRefresh = false}) async {
    if ((current.externalId == null || current.externalId!.isEmpty) &&
        current.title.isEmpty) {
      return;
    }

    if (!forceRefresh) {
      // Opening a card must not call any external API: enrichment is only an
      // explicit user action (the refresh button).
      return;
    }

    try {
      if (mounted) setState(() => _isEnriching = true);
      final enriched = await ref.read(apiClientProvider).enrichMedia(current.id);
      _enrichedMediaIds.add(current.id);
      if (sequence == _requestSequence && mounted) {
        setState(() {
          _media = enriched;
          _syncFrom(enriched);
        });
      }
    } catch (_) {
      _enrichedMediaIds.add(current.id);
    } finally {
      if (mounted) setState(() => _isEnriching = false);
    }
    
  }

  // ------------------------------------------------------------------
  // Related tab.
  // ------------------------------------------------------------------

  Future<void> _loadRelated(MediaItem item, String? source,
      {bool forceRefresh = false}) async {
    final sequence = ++_relatedSequence;
    if (mounted) setState(() => _relatedLoading = source != null);
    _relatedError = null;

    // A stored list is the previous successful load, so it is shown before
    // anything leaves the building.
    if (source == null && !forceRefresh && item is MediaDetail) {
      final stored = _readStoredRelated(item, _t);
      if (stored != null && mounted) {
        setState(() => _related = stored);
      }
    }

    try {
      List<MediaItem> all = const <MediaItem>[];
      try {
        all = await ref.read(apiClientProvider).getMedia();
      } catch (_) {
        // Library list is best-effort; external relations still load.
      }
      if (sequence != _relatedSequence || !mounted) return;

      final results = <RelatedEntry>[];

      // 1. Local siblings of the same franchise.
      if (item.franchiseId != null) {
        final localMatches = all
            .where((candidate) =>
                candidate.franchiseId == item.franchiseId &&
                candidate.id != item.id)
            .toList()
          ..sort((left, right) {
            final d = orderOf(left) - orderOf(right);
            return d != 0 ? d : left.title.compareTo(right.title);
          });

        for (final lm in localMatches) {
          results.add(RelatedEntry(
            id: lm.id,
            title: lm.title,
            coverUrl: lm.coverUrl,
            type: lm.type.wire,
            localItem: lm,
          ));
        }
      }

      // 2. Everything below leaves the building only after the user names a
      // source.
      if (source == null) {
        if (sequence == _relatedSequence && mounted) {
          final stored = item is MediaDetail ? _readStoredRelated(item, _t) : null;
          if (stored != null && stored.isNotEmpty) {
            final remappedStored = stored.map((entry) {
              MediaItem? local;
              try {
                local = findMatchingLocal(entry, all);
              } catch (_) {}
              return RelatedEntry(
                id: entry.id,
                title: entry.title,
                originalTitle: entry.originalTitle,
                romajiTitle: entry.romajiTitle,
                coverUrl: local?.coverUrl ?? entry.coverUrl,
                bannerUrl: entry.bannerUrl,
                type: entry.type,
                format: entry.format,
                year: entry.year,
                relationType: entry.relationType,
                rawRelationType: entry.rawRelationType,
                score: entry.score,
                ratings: entry.ratings,
                description: entry.description,
                trailerVideoId: entry.trailerVideoId,
                episodes: entry.episodes,
                chapters: entry.chapters,
                volumes: entry.volumes,
                studio: entry.studio,
                author: entry.author,
                duration: entry.duration,
                releaseDate: entry.releaseDate,
                endDate: entry.endDate,
                releaseStatus: entry.releaseStatus,
                externalSource: entry.externalSource,
                localItem: local ?? entry.localItem,
              );
            }).toList();
            final merged = [...results];
            for (final s in remappedStored) {
              final dup = merged.any((m) =>
                  m.id == s.id ||
                  (m.localItem != null &&
                      s.localItem != null &&
                      m.localItem!.id == s.localItem!.id));
              if (!dup) merged.add(s);
            }
            setState(() => _related = merged);
          } else {
            setState(() => _related = results);
          }
        }
        return;
      }

      if (source.toLowerCase().contains('rawg')) {
        try {
          final gameRelated = await ref.read(apiClientProvider).getGameRelated(
                rawgId: (item.externalSource?.toLowerCase() == 'rawg')
                    ? item.externalId
                    : null,
                title: item.title,
                externalSource: item.externalSource,
                externalId: item.externalId,
              );
          for (final gr in gameRelated) {
            if (gr.id == item.externalId ||
                gr.title.toLowerCase() == item.title.toLowerCase()) {
              continue;
            }
            final dup = results.any((r) =>
                r.id == gr.id || r.title.toLowerCase() == gr.title.toLowerCase());
            if (dup) continue;
            results.add(RelatedEntry(
              id: gr.id,
              title: gr.title,
              coverUrl: gr.coverUrl,
              type: 'game',
              score: gr.score?.toDouble(),
              releaseDate: gr.releaseDate,
              year: _yearOf(gr.releaseDate),
              ratings: (gr.score != null && gr.score != 0)
                  ? [RatingBadge(source: 'RAWG', score: gr.score!.toDouble())]
                  : null,
              relationType: _isRu ? 'Игра' : 'Game',
              rawRelationType: 'OTHER',
            ));
          }
        } catch (_) {}
      } else if (isAnime(item) || item.type == MediaType.manga) {
        final rows = await ref.read(apiClientProvider).getExternalRelations(
              type: isAnime(item) ? 'anime' : 'manga',
              externalId: item.externalId,
              title: readRomajiTitle(item) ?? item.title,
              source: source,
              kind: 'related',
            );

        for (final relation in rows) {
          final entry = _withRelationType(
              toRelatedEntry(relation), formatRelationType(relation.relationType, _t));
          if (entry.title.toLowerCase() == item.title.toLowerCase()) continue;

          MediaItem? matchedLocal;
          try {
            matchedLocal = findMatchingLocal(entry, all);
          } catch (_) {}

          final dup = results.any((r) =>
              r.id == entry.id ||
              r.title.toLowerCase() == entry.title.toLowerCase());
          if (!dup) {
            results.add(RelatedEntry(
              id: entry.id,
              title: entry.title,
              originalTitle: entry.originalTitle,
              romajiTitle: entry.romajiTitle,
              coverUrl: matchedLocal?.coverUrl ?? entry.coverUrl,
              bannerUrl: entry.bannerUrl,
              type: entry.type,
              format: entry.format,
              year: entry.year,
              relationType: entry.relationType,
              rawRelationType: entry.rawRelationType,
              score: entry.score,
              ratings: entry.ratings,
              description: entry.description,
              trailerVideoId: entry.trailerVideoId,
              episodes: entry.episodes,
              chapters: entry.chapters,
              volumes: entry.volumes,
              studio: entry.studio,
              author: entry.author,
              duration: entry.duration,
              releaseDate: entry.releaseDate,
              endDate: entry.endDate,
              releaseStatus: entry.releaseStatus,
              externalSource: entry.externalSource,
              localItem: matchedLocal,
            ));
          }
        }
      } else {
        // Films and series: TMDb's own recommendations + similar pool,
        // proxied by the server.
        final rows = await ref.read(apiClientProvider).getExternalRelations(
              type: item.type.wire,
              externalId: item.externalId,
              title: item.title,
              source: source,
              kind: 'related',
            );
        for (final relation in rows) {
          final entry = _withRelationType(
              toRelatedEntry(relation), formatRelationType(relation.relationType, _t));
          final dup = results.any((r) =>
              r.id == entry.id ||
              r.title.toLowerCase() == entry.title.toLowerCase());
          if (dup) continue;
          MediaItem? matchedLocal;
          try {
            matchedLocal = findMatchingLocal(entry, all);
          } catch (_) {}
          results.add(RelatedEntry(
            id: entry.id,
            title: entry.title,
            originalTitle: entry.originalTitle,
            romajiTitle: entry.romajiTitle,
            coverUrl: matchedLocal?.coverUrl ?? entry.coverUrl,
            bannerUrl: entry.bannerUrl,
            type: item.type.wire,
            format: entry.format,
            year: entry.year ?? _yearOf(entry.releaseDate),
            relationType: entry.relationType,
            rawRelationType: entry.rawRelationType,
            score: entry.score,
            ratings: entry.ratings,
            description: entry.description,
            trailerVideoId: entry.trailerVideoId,
            episodes: entry.episodes,
            chapters: entry.chapters,
            volumes: entry.volumes,
            studio: entry.studio,
            author: entry.author,
            duration: entry.duration,
            releaseDate: entry.releaseDate,
            endDate: entry.endDate,
            releaseStatus: entry.releaseStatus,
            externalSource: entry.externalSource,
            localItem: matchedLocal,
          ));
        }
      }

      if (sequence == _relatedSequence && mounted) {
        setState(() => _related = results);
        // Only the rows we actually fetched from a provider are worth keeping;
        // the local franchise siblings are already in the database.
        if (results.isNotEmpty && item is MediaDetail) {
          final external = results
              .where((entry) =>
                  entry.localItem?.id != entry.id)
              .toList();
          if (external.isNotEmpty) {
            _persistRelated(_container, item, external, source);
            setState(() {
              _media = _media!.copyWithFields(
                relatedMediaJson: jsonEncode(external.map(_relatedEntryToJson).toList()),
                relatedSource: source,
              );
            });
          }
        }
      }
    } catch (error) {
      if (sequence == _relatedSequence && mounted) {
        // The stored copy is left alone: a provider being down is not a reason
        // to throw away what a previous successful load put there.
        setState(() => _relatedError = error);
      }
    } finally {
      if (sequence == _relatedSequence && mounted) {
        setState(() => _relatedLoading = false);
      }
      // $effect auto-load: после завершения (пустой результат) эффект в
      // Svelte переоценивается; здесь — явный вызов.
      if (sequence == _relatedSequence) {
        unawaited(_maybeAutoLoadRelated());
      }
    }
  }

  Future<void> _handleRelatedClick(RelatedEntry rel) async {
    if (rel.localItem != null) {
      widget.onOpenRelated(rel.localItem!);
      return;
    }

    setState(() {
      _previewRelatedItem = rel;
      _previewStatus = MediaStatus.planned;
      _previewRelatedLoading = true;
    });

    try {
      final details = await ref.read(apiClientProvider).getExternalDetails(
            rel.type,
            rel.id,
            rel.title,
            source: rel.externalSource ?? 'AniList',
          );
      if (details != null && mounted && _previewRelatedItem?.id == rel.id) {
        setState(() {
          _previewRelatedItem = RelatedEntry(
            id: _previewRelatedItem!.id,
            title: _previewRelatedItem!.title,
            originalTitle:
                details.originalTitle ?? _previewRelatedItem!.originalTitle,
            romajiTitle: details.romajiTitle ??
                details.originalTitle ??
                _previewRelatedItem!.romajiTitle,
            coverUrl: details.coverUrl ?? _previewRelatedItem!.coverUrl,
            bannerUrl: _previewRelatedItem!.bannerUrl,
            type: _previewRelatedItem!.type,
            format: _previewRelatedItem!.format,
            year: details.releaseYear ?? _previewRelatedItem!.year,
            relationType: _previewRelatedItem!.relationType,
            rawRelationType: _previewRelatedItem!.rawRelationType,
            score: details.rating ?? _previewRelatedItem!.score,
            ratings: details.ratings != null
                ? details.ratings!
                    .map((r) => RatingBadge(
                          source: r.source,
                          score: r.rating,
                          queried: true,
                        ))
                    .toList()
                : _previewRelatedItem!.ratings,
            description:
                details.description ?? _previewRelatedItem!.description,
            trailerVideoId: _previewRelatedItem!.trailerVideoId,
            episodes: details.totalCount ?? _previewRelatedItem!.episodes,
            chapters: _previewRelatedItem!.chapters,
            volumes: _previewRelatedItem!.volumes,
            studio: details.studio ?? _previewRelatedItem!.studio,
            author: details.author ?? _previewRelatedItem!.author,
            duration: details.runtimeMinutes ?? _previewRelatedItem!.duration,
            releaseDate: details.releaseDate ?? _previewRelatedItem!.releaseDate,
            endDate: details.endDate ?? _previewRelatedItem!.endDate,
            releaseStatus:
                details.releaseStatus ?? _previewRelatedItem!.releaseStatus,
            externalSource: _previewRelatedItem!.externalSource,
            localItem: _previewRelatedItem!.localItem,
          );
        });
      }
    } catch (_) {
      // Preview stays as-is; the modal shows the raw card.
    } finally {
      if (mounted) setState(() => _previewRelatedLoading = false);
    }
  }

  Future<void> _addRelatedToLibrary(RelatedEntry rel, MediaStatus status) async {
    if (mounted) setState(() => _previewAddingBusy = true);
    try {
      // Ensure we have full details (including Kitsu ratings and exact release
      // date).
      RelatedEntry itemDetails = rel;
      List<ExternalEpisode>? fetchedEpisodes;
      try {
        final fetched = await ref.read(apiClientProvider).getExternalDetails(
              rel.type,
              rel.id,
              rel.title,
              source: rel.externalSource ?? 'AniList',
            );
        if (fetched != null) {
          fetchedEpisodes = fetched.episodes;
          itemDetails = RelatedEntry(
            id: rel.id,
            title: rel.title,
            originalTitle: fetched.originalTitle ?? rel.originalTitle,
            romajiTitle:
                fetched.romajiTitle ?? fetched.originalTitle ?? rel.romajiTitle,
            coverUrl: fetched.coverUrl ?? rel.coverUrl,
            bannerUrl: rel.bannerUrl,
            type: rel.type,
            format: fetched.format ?? rel.format,
            year: fetched.releaseYear ?? rel.year,
            relationType: rel.relationType,
            rawRelationType: rel.rawRelationType,
            score: fetched.rating ?? rel.score,
            ratings: fetched.ratings != null
                ? fetched.ratings!
                    .map((r) => RatingBadge(
                          source: r.source,
                          score: r.rating,
                          queried: true,
                        ))
                    .toList()
                : rel.ratings,
            description: fetched.description ?? rel.description,
            trailerVideoId: rel.trailerVideoId,
            episodes: fetched.totalCount ?? rel.episodes,
            chapters: fetched.chapters ?? rel.chapters,
            volumes: fetched.volumes ?? rel.volumes,
            studio: fetched.studio ?? rel.studio,
            author: fetched.author ?? rel.author,
            duration: fetched.runtimeMinutes ?? rel.duration,
            releaseDate: fetched.releaseDate ?? rel.releaseDate,
            endDate: fetched.endDate ?? rel.endDate,
            releaseStatus: fetched.releaseStatus ?? rel.releaseStatus,
            externalSource: rel.externalSource,
            localItem: rel.localItem,
          );
        }
      } catch (_) {}

      // Ensure current media has franchiseName or franchiseId so they are
      // grouped together.
      final media = _media;
      String? franchiseName = media?.franchiseName;
      String? franchiseId = media?.franchiseId;
      MediaDetail? updatedMedia;
      if (media != null && franchiseId == null && (franchiseName == null || franchiseName.isEmpty)) {
        franchiseName = media.title;
        try {
          final patched = await ref
              .read(apiClientProvider)
              .updateMedia(media.id, UpdateMediaPayload(franchiseName: media.title));
          updatedMedia = patched;
        } catch (_) {}
      }

      final format = (itemDetails.format ?? '').toUpperCase();
      final isMovie = format == 'MOVIE';
      final isManga =
          itemDetails.type == 'manga' ||
              format == 'MANGA' ||
              format == 'NOVEL' ||
              format == 'ONE_SHOT';

      final ratingsJson = (itemDetails.ratings != null &&
              itemDetails.ratings!.isNotEmpty)
          ? jsonEncode(itemDetails.ratings!
              .map((r) => {'source': r.source, 'rating': r.score})
              .toList())
          : null;
      final releaseDate = itemDetails.releaseDate ??
          (itemDetails.year != null ? '${itemDetails.year}-01-01' : null);
      final endDate = itemDetails.endDate;

      final base = CreateMediaBase(
        type: '',
        title: itemDetails.title,
        status: status,
        altTitles: null,
        score: null,
        coverUrl: itemDetails.coverUrl,
        notes: null,
        description: itemDetails.description,
        trailerVideoId: itemDetails.trailerVideoId,
        franchiseId: franchiseId,
        franchiseName: franchiseName,
        franchiseOrder: null,
        externalId: itemDetails.id,
        externalSource: itemDetails.externalSource ?? 'AniList',
        importSource: null,
        externalRating: itemDetails.score,
        externalRatingVotes: null,
        externalRatingsJson: ratingsJson,
        releaseDate: releaseDate,
        endDate: endDate,
        releaseStatus: itemDetails.releaseStatus,
        genres: null,
        tags: null,
        unlockedAchievements: null,
        userPlatform: null,
      );

      final MediaDetail created;
      if (isMovie) {
        created = await ref.read(apiClientProvider).createMedia(
              CreateMoviePayload(
                durationMinutes: itemDetails.duration,
                director: null,
                isAnime: true,
                studio: itemDetails.studio,
                romajiTitle: itemDetails.romajiTitle ?? itemDetails.originalTitle,
                title: base.title,
                status: base.status,
                altTitles: base.altTitles,
                score: base.score,
                coverUrl: base.coverUrl,
                notes: base.notes,
                description: base.description,
                trailerVideoId: base.trailerVideoId,
                franchiseId: base.franchiseId,
                franchiseName: base.franchiseName,
                franchiseOrder: base.franchiseOrder,
                externalId: base.externalId,
                externalSource: base.externalSource,
                importSource: base.importSource,
                externalRating: base.externalRating,
                externalRatingVotes: base.externalRatingVotes,
                externalRatingsJson: base.externalRatingsJson,
                releaseDate: base.releaseDate,
                endDate: base.endDate,
                releaseStatus: base.releaseStatus,
                genres: base.genres,
                tags: base.tags,
                unlockedAchievements: base.unlockedAchievements,
                userPlatform: base.userPlatform,
              ),
            );
      } else if (isManga) {
        created = await ref.read(apiClientProvider).createMedia(
              CreateMangaPayload(
                author: itemDetails.author,
                romajiTitle: itemDetails.romajiTitle ?? itemDetails.originalTitle,
                totalVolumes: itemDetails.volumes,
                totalChapters: itemDetails.chapters,
                currentVolume: null,
                volumes: null,
                title: base.title,
                status: base.status,
                altTitles: base.altTitles,
                score: base.score,
                coverUrl: base.coverUrl,
                notes: base.notes,
                description: base.description,
                trailerVideoId: base.trailerVideoId,
                franchiseId: base.franchiseId,
                franchiseName: base.franchiseName,
                franchiseOrder: base.franchiseOrder,
                externalId: base.externalId,
                externalSource: base.externalSource,
                importSource: base.importSource,
                externalRating: base.externalRating,
                externalRatingVotes: base.externalRatingVotes,
                externalRatingsJson: base.externalRatingsJson,
                releaseDate: base.releaseDate,
                endDate: base.endDate,
                releaseStatus: base.releaseStatus,
                genres: base.genres,
                tags: base.tags,
                unlockedAchievements: base.unlockedAchievements,
                userPlatform: base.userPlatform,
              ),
            );
      } else {
        created = await ref.read(apiClientProvider).createMedia(
              CreateTvShowPayload(
                isAnime: true,
                studio: itemDetails.studio,
                romajiTitle: itemDetails.romajiTitle ?? itemDetails.originalTitle,
                network: null,
                durationMinutes: itemDetails.duration,
                episodeDurationMinutes: itemDetails.duration,
                seasons: [
                  CreateSeasonPayload(
                    seasonNumber: 1,
                    title: 'Season 1',
                    coverUrl: null,
                    totalEpisodes: itemDetails.episodes ??
                        (fetchedEpisodes?.isNotEmpty == true
                            ? fetchedEpisodes!.length
                            : 12),
                    status: status,
                    score: null,
                    notes: null,
                    airDate: releaseDate,
                    episodesData: (fetchedEpisodes != null &&
                            fetchedEpisodes.isNotEmpty)
                        ? jsonEncode([
                            for (final e in fetchedEpisodes)
                              {'number': e.number, 'title': e.title, 'airDate': e.airDate},
                          ])
                        : null,
                  ),
                ],
                title: base.title,
                status: base.status,
                altTitles: base.altTitles,
                score: base.score,
                coverUrl: base.coverUrl,
                notes: base.notes,
                description: base.description,
                trailerVideoId: base.trailerVideoId,
                franchiseId: base.franchiseId,
                franchiseName: base.franchiseName,
                franchiseOrder: base.franchiseOrder,
                externalId: base.externalId,
                externalSource: base.externalSource,
                importSource: base.importSource,
                externalRating: base.externalRating,
                externalRatingVotes: base.externalRatingVotes,
                externalRatingsJson: base.externalRatingsJson,
                releaseDate: base.releaseDate,
                endDate: base.endDate,
                releaseStatus: base.releaseStatus,
                genres: base.genres,
                tags: base.tags,
                unlockedAchievements: base.unlockedAchievements,
                userPlatform: base.userPlatform,
              ),
            );
      }

      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: _t.tr('searchModal.inLibrary'),
            description: _t.tr('toast.descCreated'),
          ),
        );
      }
      // Update the related grid immediately to show the "added" badge.
      setState(() {
        _related = [
          for (final r in _related)
            if (r.id == rel.id) ...[
              RelatedEntry(
                id: r.id,
                title: r.title,
                originalTitle: r.originalTitle,
                romajiTitle: r.romajiTitle,
                coverUrl: created.coverUrl ?? r.coverUrl,
                bannerUrl: r.bannerUrl,
                type: r.type,
                format: r.format,
                year: r.year,
                relationType: r.relationType,
                rawRelationType: r.rawRelationType,
                score: r.score,
                ratings: r.ratings,
                description: r.description,
                trailerVideoId: r.trailerVideoId,
                episodes: r.episodes,
                chapters: r.chapters,
                volumes: r.volumes,
                studio: r.studio,
                author: r.author,
                duration: r.duration,
                releaseDate: r.releaseDate,
                endDate: r.endDate,
                releaseStatus: r.releaseStatus,
                externalSource: r.externalSource,
                localItem: created,
              ),
            ] else
              r,
        ];
        if (updatedMedia != null) {
          _media = updatedMedia;
          _syncFrom(updatedMedia);
        }
        _previewRelatedItem = null;
      });
      widget.onUpdate();
      widget.onOpenRelated(created);
    } catch (e) {
      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: _t.tr('toast.actionFailed'),
            description: errorMessage(e, _t.locale),
            type: ToastType.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _previewAddingBusy = false);
    }
  }

  // ------------------------------------------------------------------
  // Прогресс: степ, серии, счётчик.
  // ------------------------------------------------------------------

  void _stepProgress(int delta) {
    final info = _progressInfo;
    final target = _media;
    if (info == null || !info.editable || target == null) return;

    final next = clampProgress(_progressValue + delta, info.total);
    if (next == _progressValue) return;

    // Rule 1: only the exact 0 → 1 step implies the title started.
    if (shouldPromoteToInProgress(_progressValue, next) &&
        target.status != MediaStatus.inProgress) {
      final previousStatus = target.status;
      final flipped = target.copyWithFields(status: MediaStatus.inProgress);
      setState(() {
        _media = flipped;
        _statusValue = MediaStatus.inProgress;
      });
      notifyAutoInProgress(
        flipped,
        previousStatus,
        show: (spec) => showStatusPromotionToast(ref, spec),
        t: _t,
        handlers: StatusPromotionHandlers(
          undo: () => _revertPromotion(flipped, previousStatus),
          keepStatus: () => _keepProgressOnly(flipped, previousStatus, next),
        ),
      );
    }

    setState(() {
      _pendingSnapshot ??= _committedProgress;
      _progressValue = next;
      _progressError = null;
    });
    // Publish the optimistic value so cards showing this title (and the
    // prefetch cache) pick it up before the debounced PUT confirms.
    applyOptimisticProgress(_container, target.id, next);
    writeCardProgress(target, next);
    updateCachedDetailProgressRef(_container, target.id, next);
    _progressDebounce.schedule(target.id, next);
  }

  /// Undo on the detail banner: cancel the pending progress write, then
  /// persist progress 0 and the previous status.
  void _revertPromotion(MediaDetail target, MediaStatus previousStatus) {
    _progressDebounce.cancel();
    clearOptimisticProgress(_container, target.id);
    if (mounted) {
      setState(() {
        _pendingSnapshot = null;
        _progressValue = 0;
        _committedProgress = 0;
        _statusValue = previousStatus;
        _media = target.copyWithFields(status: previousStatus);
      });
    }
    writeCardProgress(target, 0);
    updateCachedDetailProgressRef(_container, target.id, 0);
    unawaited(ref
        .read(apiClientProvider)
        .setProgress(target.id, 0)
        .then((_) => ref.read(apiClientProvider).updateStatus(
            target.id, previousStatus))
        .catchError((Object _) {}));
  }

  /// Keep-status on the detail banner: progress stays (persisted explicitly,
  /// since the debounced write is cancelled) and the previous status is
  /// restored.
  void _keepProgressOnly(
      MediaDetail target, MediaStatus previousStatus, int value) {
    _progressDebounce.cancel();
    if (mounted) {
      setState(() {
        _pendingSnapshot = null;
        _committedProgress = value;
        _statusValue = previousStatus;
        _media = target.copyWithFields(status: previousStatus);
      });
    }
    unawaited(ref
        .read(apiClientProvider)
        .setProgress(target.id, value)
        .then((_) => resolveOptimisticProgress(_container, target.id, value))
        .catchError((Object _) {}));
    unawaited(ref
        .read(apiClientProvider)
        .updateStatus(target.id, previousStatus)
        .catchError((Object _) {}));
  }

  Future<void> _stepEpisodeProgress(int delta) async {
    final step = nextSeriesEpisodeStep(_seasons, delta);
    if (step == null) return;
    final target = _media;
    if (target == null) return;

    // Optimistic: bump the season row locally so the banner moves at once.
    TvSeason? season;
    int previousEpisode = 0;
    final updatedSeasons = <TvSeason>[];
    for (final s in _seasons) {
      if (s.id == step.seasonId) {
        season = s;
        previousEpisode = s.currentEpisode;
        updatedSeasons.add(TvSeason(
          id: s.id,
          seasonNumber: s.seasonNumber,
          title: s.title,
          coverUrl: s.coverUrl,
          currentEpisode: step.currentEpisode,
          totalEpisodes: s.totalEpisodes,
          status: s.status,
          score: s.score,
          notes: s.notes,
          airDate: s.airDate,
          episodesData: s.episodesData,
          tvShowId: s.tvShowId,
        ));
      } else {
        updatedSeasons.add(s);
      }
    }
    final previousTotal = _seriesEpisodes.current;
    if (mounted) {
      setState(() {
        _media = target.copyWithFields(seasons: updatedSeasons);
      });
    }

    // Rule 1 for the series total.
    if (shouldPromoteToInProgress(previousTotal, previousTotal + delta) &&
        target.status != MediaStatus.inProgress) {
      final previousStatus = target.status;
      final flipped = target.copyWithFields(
          status: MediaStatus.inProgress, seasons: updatedSeasons);
      setState(() => _statusValue = MediaStatus.inProgress);
      notifyAutoInProgress(
        flipped,
        previousStatus,
        show: (spec) => showStatusPromotionToast(ref, spec),
        t: _t,
        handlers: StatusPromotionHandlers(
          undo: () => _revertSeriesPromotion(
              flipped, previousStatus, season, previousEpisode),
          keepStatus: () {
            if (mounted) {
              setState(() {
                _statusValue = previousStatus;
                _media = flipped.copyWithFields(status: previousStatus);
              });
            }
          },
        ),
      );
    }
    applyOptimisticProgress(_container, target.id, previousTotal + delta);

    try {
      await ref
          .read(apiClientProvider)
          .setSeasonProgress(step.seasonId, step.currentEpisode);
      if (mounted) widget.onUpdate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _media = target.copyWithFields(
            status: _statusValue,
            seasons: [
              for (final s in updatedSeasons)
                if (s.id == step.seasonId && season != null)
                  TvSeason(
                    id: s.id,
                    seasonNumber: s.seasonNumber,
                    title: s.title,
                    coverUrl: s.coverUrl,
                    currentEpisode: previousEpisode,
                    totalEpisodes: s.totalEpisodes,
                    status: s.status,
                    score: s.score,
                    notes: s.notes,
                    airDate: s.airDate,
                    episodesData: s.episodesData,
                    tvShowId: s.tvShowId,
                  )
                else
                  s,
            ]);
      });
      writeCardProgress(target, previousTotal);
      clearOptimisticProgress(_container, target.id);
      setState(() => _progressError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    }
  }

  /// Undo for a series step: after the in-flight season write settles, the
  /// first season is zeroed and the previous status restored.
  void _revertSeriesPromotion(
    MediaDetail target,
    MediaStatus previousStatus,
    TvSeason? season,
    int previousEpisode,
  ) {
    setState(() {
      _statusValue = previousStatus;
      _media = target.copyWithFields(
        status: previousStatus,
        seasons: [
          for (final s in target.seasons ?? const <TvSeason>[])
            if (season != null && s.id == season.id)
              _seasonWithEpisode(s, previousEpisode)
            else
              s,
        ],
      );
    });
    writeCardProgress(target, 0);
    clearOptimisticProgress(_container, target.id);
    unawaited(() async {
      try {
        final zero = _absoluteSeasonTarget(target.seasons ?? const <TvSeason>[], 0);
        if (zero != null) {
          await ref
              .read(apiClientProvider)
              .setSeasonProgress(zero.seasonId, zero.currentEpisode);
        }
        if (mounted) widget.onUpdate();
      } catch (_) {}
    }());
    unawaited(ref
        .read(apiClientProvider)
        .updateStatus(target.id, previousStatus)
        .catchError((Object _) {}));
  }

  void _stepOverview(int delta) {
    if (_isSeriesOverview) {
      unawaited(_stepEpisodeProgress(delta));
      return;
    }
    _stepProgress(delta);
  }

  /// Absolute per-season write used by the episodes tab.
  Future<void> _setSeasonProgressOf(String seasonId, int number) async {
    final target =
        _seasonViews.where((view) => view.season.id == seasonId).toList();
    if (target.isEmpty) return;
    await _setEpisodeProgress(target.first.season, number);
  }

  /// Marks every season of the series fully watched in one optimistic sweep.
  Future<void> _markAllSeries() async {
    final target = _media;
    if (target == null) return;
    final pending = <({TvSeason season, int previous})>[];
    for (final season in _seasons) {
      if (season.totalEpisodes > 0 && season.currentEpisode < season.totalEpisodes) {
        pending.add((season: season, previous: season.currentEpisode));
      }
    }
    if (pending.isEmpty) return;

    final optimisticSeasons = [
      for (final s in _seasons)
        if (pending.any((p) => p.season.id == s.id))
          _seasonWithEpisode(s, s.totalEpisodes)
        else
          s,
    ];
    if (mounted) {
      setState(() {
        _episodeBusy = 'mark-all';
        _media = target.copyWithFields(seasons: optimisticSeasons);
        _progressError = null;
      });
    }
    applyOptimisticProgress(_container, target.id, _seriesEpisodesOf(optimisticSeasons).total);
    try {
      for (final p in pending) {
        await ref
            .read(apiClientProvider)
            .setSeasonProgress(p.season.id, p.season.totalEpisodes);
      }
      if (mounted) widget.onUpdate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _media = target.copyWithFields(seasons: [
          for (final s in optimisticSeasons)
            if (pending.any((p) => p.season.id == s.id))
              _seasonWithEpisode(s, pending.firstWhere((p) => p.season.id == s.id).previous)
            else
              s,
        ]);
      });
      clearOptimisticProgress(_container, target.id);
      setState(() => _progressError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _episodeBusy = '');
    }
  }

  /// Rolls every started season of the series back to zero.
  Future<void> _resetSeries() async {
    final target = _media;
    if (target == null) return;
    final pending = <({TvSeason season, int previous})>[];
    for (final season in _seasons) {
      if (season.currentEpisode > 0) {
        pending.add((season: season, previous: season.currentEpisode));
      }
    }
    if (pending.isEmpty) return;

    final optimisticSeasons = [
      for (final s in _seasons)
        if (pending.any((p) => p.season.id == s.id))
          _seasonWithEpisode(s, 0)
        else
          s,
    ];
    if (mounted) {
      setState(() {
        _episodeBusy = 'reset-all';
        _media = target.copyWithFields(seasons: optimisticSeasons);
        _progressError = null;
      });
    }
    applyOptimisticProgress(_container, target.id, 0);
    try {
      for (final p in pending) {
        await ref.read(apiClientProvider).setSeasonProgress(p.season.id, 0);
      }
      if (mounted) widget.onUpdate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _media = target.copyWithFields(seasons: [
          for (final s in optimisticSeasons)
            if (pending.any((p) => p.season.id == s.id))
              _seasonWithEpisode(
                  s, pending.firstWhere((p) => p.season.id == s.id).previous)
            else
              s,
        ]);
      });
      clearOptimisticProgress(_container, target.id);
      setState(() => _progressError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _episodeBusy = '');
    }
  }

  /// Absolute series-wide counter. The generic PUT /progress endpoint rejects
  /// shows, so the desired total is distributed across the seasons in order.
  Future<void> _commitSeriesCounter(int val) async {
    final target = _media;
    if (target == null || !_isSeriesOverview) return;
    final max = _seriesEpisodes.total;
    final desired =
        max > 0 ? val.clamp(0, max) : (val < 0 ? 0 : val);
    if (_seriesBaseline == null) {
      if (desired == _seriesEpisodes.current) return;
      _seriesBaseline = _seriesEpisodes.current;
    }

    // Optimistic: fill the live seasons in order, so the counter moves at once.
    var remaining = desired;
    final optimisticSeasons = <TvSeason>[];
    for (final season in _seasons) {
      final total = season.totalEpisodes;
      if (total <= 0) {
        optimisticSeasons.add(season);
        continue;
      }
      final fill = remaining < total ? remaining : total;
      remaining -= fill;
      optimisticSeasons.add(fill != season.currentEpisode
          ? _seasonWithEpisode(season, fill)
          : season);
    }
    if (mounted) {
      setState(() => _media = target.copyWithFields(seasons: optimisticSeasons));
    }
    applyOptimisticProgress(
        _container, target.id, desired - (remaining > 0 ? remaining : 0));

    _seriesPendingValue = desired;
    if (_seriesCommitBusy) return;
    _seriesCommitBusy = true;
    setState(() => _progressError = null);
    try {
      while (_seriesPendingValue != null) {
        final value = _seriesPendingValue!;
        _seriesPendingValue = null;
        final step = _absoluteSeasonTarget(optimisticSeasons, value);
        if (step == null) continue;
        await ref
            .read(apiClientProvider)
            .setSeasonProgress(step.seasonId, step.currentEpisode);
        if (mounted) widget.onUpdate();
      }
    } catch (error) {
      // Roll the whole burst back to where the pointer interaction started.
      if (_seriesBaseline != null) {
        var rest = _seriesBaseline!;
        final rolled = <TvSeason>[];
        for (final season in optimisticSeasons) {
          final total = season.totalEpisodes;
          if (total <= 0) {
            rolled.add(season);
            continue;
          }
          final fill = rest < total ? rest : total;
          rest -= fill;
          rolled.add(_seasonWithEpisode(season, fill));
        }
        setState(() => _media = target.copyWithFields(seasons: rolled));
      }
      clearOptimisticProgress(_container, target.id);
      setState(() => _progressError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      _seriesCommitBusy = false;
      _seriesPendingValue = null;
      _seriesBaseline = null;
    }
  }

  /// Season write that puts the series at exactly `value` watched episodes.
  ({String seasonId, int currentEpisode})? _absoluteSeasonTarget(
      List<TvSeason> list, int value) {
    if (list.isEmpty) return null;
    var cumulative = 0;
    for (final season in list) {
      final total = season.totalEpisodes;
      if (total <= 0 || value <= cumulative + total) {
        final ep = value - cumulative;
        return (
          seasonId: season.id,
          currentEpisode: ep > 0 ? ep : 0,
        );
      }
      cumulative += total;
    }
    final last = list.last;
    return (seasonId: last.id, currentEpisode: last.totalEpisodes);
  }

  /// RelatedEntry иммутабелен (detail_types) — copyWith-хелпер.
  RelatedEntry _withRelationType(RelatedEntry e, String? relationType) =>
      RelatedEntry(
        id: e.id,
        title: e.title,
        originalTitle: e.originalTitle,
        romajiTitle: e.romajiTitle,
        coverUrl: e.coverUrl,
        bannerUrl: e.bannerUrl,
        type: e.type,
        format: e.format,
        year: e.year,
        relationType: relationType ?? e.relationType,
        rawRelationType: e.rawRelationType,
        score: e.score,
        ratings: e.ratings,
        description: e.description,
        trailerVideoId: e.trailerVideoId,
        episodes: e.episodes,
        chapters: e.chapters,
        volumes: e.volumes,
        studio: e.studio,
        author: e.author,
        duration: e.duration,
        releaseDate: e.releaseDate,
        endDate: e.endDate,
        releaseStatus: e.releaseStatus,
        externalSource: e.externalSource,
        localItem: e.localItem,
      );

  /// $effect auto-load Related: пустой таб + не-загрузка + нет ошибки →
  /// дефолтный источник (relatedSource → externalSource → первый → по типу).
  Future<void> _maybeAutoLoadRelated() async {
    if (_activeSubTab != SubTab.related) return;
    final media = _media;
    if (media == null) return;
    if (_related.isNotEmpty || _relatedLoading || _relatedError != null) return;
    final currentMedia = media;
    final list =
        await availableRelationSources(ref.read(apiClientProvider), currentMedia);
    if (!mounted) return;
    if (_activeSubTab != SubTab.related ||
        _media == null ||
        _media!.id != currentMedia.id ||
        _related.isNotEmpty ||
        _relatedLoading ||
        _relatedError != null ||
        _autoRelatedAttemptedId == currentMedia.id) {
      return;
    }
    _autoRelatedAttemptedId = currentMedia.id;

    String defaultSource = '';
    for (final s in list) {
      final rs = currentMedia.relatedSource?.toLowerCase();
      if (rs != null &&
          rs.isNotEmpty &&
          (s.id.toLowerCase() == rs || s.label.toLowerCase() == rs)) {
        defaultSource = s.id;
        break;
      }
    }
    if (defaultSource.isEmpty) {
      for (final s in list) {
        final es = currentMedia.externalSource?.toLowerCase();
        if (es != null &&
            es.isNotEmpty &&
            (s.id.toLowerCase() == es || s.label.toLowerCase() == es)) {
          defaultSource = s.id;
          break;
        }
      }
    }
    if (defaultSource.isEmpty && list.isNotEmpty) {
      defaultSource = list.first.id;
    }
    if (defaultSource.isEmpty) {
      defaultSource = (isAnime(currentMedia) || currentMedia.type == MediaType.manga)
          ? 'anilist'
          : currentMedia.type == MediaType.game
              ? 'rawg'
              : 'tmdb';
    }
    if (defaultSource.isNotEmpty) {
      if (mounted) {
        setState(() => _lastRelatedSource = defaultSource);
      }
      await _loadRelated(currentMedia, defaultSource);
    }
  }

  TvSeason _seasonWithEpisode(TvSeason s, int episode) => TvSeason(
        id: s.id,
        seasonNumber: s.seasonNumber,
        title: s.title,
        coverUrl: s.coverUrl,
        currentEpisode: episode,
        totalEpisodes: s.totalEpisodes,
        status: s.status,
        score: s.score,
        notes: s.notes,
        airDate: s.airDate,
        episodesData: s.episodesData,
        tvShowId: s.tvShowId,
      );

  // ------------------------------------------------------------------
  // Статусы, оценки, просмотрено, платформа.
  // ------------------------------------------------------------------

  Future<void> _changeStatus(MediaStatus value) async {
    final target = _media;
    if (target == null || _statusBusy) return;
    if (value == _statusValue) return;

    final previous = _statusValue;
    final leavesCompleted =
        previous == MediaStatus.completed && value != MediaStatus.completed;
    final progressBeforeReset = leavesCompleted ? readCardProgress(target) : null;
    setState(() {
      _statusValue = value;
      _statusBusy = true;
      _statusError = null;
    });

    try {
      await ref.read(apiClientProvider).updateStatus(target.id, value);
      var nextMedia = target.copyWithFields(status: value);
      if (leavesCompleted) {
        // Rule 2: leaving Completed is the only status change that resets
        // progress — mirror the server's reset on the raw item, the banner and
        // the season rows.
        nextMedia = writeCardProgress(nextMedia, 0) as MediaDetail;
        updateCachedDetailProgressRef(_container, target.id, 0);
        setState(() {
          _progressValue = 0;
          _committedProgress = 0;
          _pendingSnapshot = null;
        });
      }
      showToast(
        ref,
        ToastOptions(
          title: '${_t.tr('status.label')}: ${statusLabel(value, _t)}',
          description: _t.tr('toast.descUpdated'),
        ),
      );
      if (value == MediaStatus.dropped) {
        ref.read(dropPromptStateProvider.notifier).open(DropPromptTarget(
              id: nextMedia.id,
              title: nextMedia.title,
              type: nextMedia.type.wire,
              isAnime: nextMedia.isAnime,
              dropReason: nextMedia.dropReason,
              dropNotes: nextMedia.dropNotes,
              onSaved: (reason, notes) {
                setState(() {
                  _media = _media!.copyWithFields(
                      dropReason: reason, dropNotes: notes);
                });
                widget.onUpdate();
              },
            ));
      } else {
        // Очистка nullable drop-полей — через json-пере-парс (решение #14).
        final json = nextMedia.toJson();
        json['dropReason'] = null;
        json['dropNotes'] = null;
        nextMedia = MediaDetail.fromJson(json);
      }
      setState(() {
        _media = nextMedia;
        if (leavesCompleted) {
          _media = nextMedia.copyWithFields(
              seasons: [
            for (final s in (nextMedia.seasons ?? const <TvSeason>[]))
              _seasonWithEpisode(s, 0),
          ]);
        }
      });
      widget.onUpdate();
    } catch (error) {
      setState(() => _statusValue = previous);
      if (progressBeforeReset != null) {
        // The reset never happened server-side: restore the old progress.
        writeCardProgress(target, progressBeforeReset);
        updateCachedDetailProgressRef(_container, target.id, progressBeforeReset);
      }
      setState(() => _statusError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _setScore(int score) async {
    final target = _media;
    if (target == null || _ratingBusy) return;

    final next = _scoreValue == score ? null : score;
    final previous = _scoreValue;
    setState(() {
      _scoreValue = next;
      _ratingBusy = true;
      _ratingError = null;
    });

    try {
      await ref.read(apiClientProvider).updateMedia(
            target.id,
            UpdateMediaPayload(score: next, clearScore: next == null),
          );
      showToast(
        ref,
        ToastOptions(
          title: next != null ? '\$next ★' : _t.tr('detail.clearRating'),
          description: _t.tr('toast.descUpdated'),
        ),
      );
      widget.onUpdate();
    } catch (error) {
      setState(() {
        _scoreValue = previous;
        _ratingError = error;
      });
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  /// Очистка nullable-полей одним json-пере-парсом (решение #14).
  MediaDetail _clearFields(MediaDetail m, List<String> keys, Map<String, Object?> set) {
    final json = m.toJson();
    for (final k in keys) {
      json[k] = null;
    }
    set.forEach((k, v) => json[k] = v);
    return MediaDetail.fromJson(json);
  }

  Future<void> _clearScore() async {
    final target = _media;
    if (target == null || _ratingBusy) return;

    final previousScore = _scoreValue;
    final previousDetailed = target.detailedScoreJson;

    setState(() {
      _scoreValue = null;
      _media = _clearFields(target, ['detailedScoreJson'], const {});
      _ratingBusy = true;
      _ratingError = null;
    });

    try {
      await ref.read(apiClientProvider).updateMedia(
            target.id,
            UpdateMediaPayload(
              score: null,
              clearScore: true,
              clearDetailedScore: true,
            ),
          );
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('detail.clearRating'),
          description: _t.tr('toast.descUpdated'),
        ),
      );
      widget.onUpdate();
    } catch (error) {
      setState(() {
        _scoreValue = previousScore;
        _media = target.copyWithFields(detailedScoreJson: previousDetailed);
        _ratingError = error;
      });
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  Future<void> _saveDetailedScore(String? detailedJson, [int? newScore]) async {
    final target = _media;
    if (target == null || _ratingBusy) return;

    final previousScore = _scoreValue;
    final previousDetailed = target.detailedScoreJson;

    setState(() {
      if (newScore != null) _scoreValue = newScore;
      _media = target.copyWithFields(detailedScoreJson: detailedJson);
      _ratingBusy = true;
      _ratingError = null;
    });

    try {
      final payload = UpdateMediaPayload(
        detailedScoreJson: detailedJson,
        clearDetailedScore: detailedJson == null,
        score: newScore,
      );
      await ref.read(apiClientProvider).updateMedia(target.id, payload);
      showToast(
        ref,
        ToastOptions(
          title: (newScore != null && newScore != 0)
              ? '\$newScore ★'
              : _t.tr('detail.notesSaved'),
          description:
              (newScore != null && newScore != 0) ? _t.tr('toast.descUpdated') : _t.tr('toast.descSaved'),
        ),
      );
      widget.onUpdate();
    } catch (error) {
      setState(() {
        _scoreValue = previousScore;
        _media = target.copyWithFields(detailedScoreJson: previousDetailed);
        _ratingError = error;
      });
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  void _retry() {
    // Повтор после ошибки = пользователь просит свежие данные, а не запись из
    // кэша.
    unawaited(_load(widget.mediaId, ++_requestSequence, true, forceRefresh: true));
  }

  void _startEdit() {
    final target = _media;
    if (target != null) widget.onEdit(target);
  }

  Future<void> _removeMedia() async {
    final target = _media;
    if (target == null || _deleteBusy) return;
    // The 1-second hold in the sidebar is the confirmation; no modal here.
    setState(() {
      _deleteBusy = true;
      _deleteError = null;
    });

    try {
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('detailModal.delete'),
          description: _t.tr('toast.descDeleted'),
          type: ToastType.warning,
        ),
      );
      await widget.onDelete(target.id);
      widget.onBack();
    } catch (error) {
      setState(() => _deleteError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
  }

  /// One write path for every episode toggle.
  Future<void> _setEpisodeProgress(TvSeason target, int number) async {
    if (_episodeBusy.isNotEmpty) return;

    final current = target.currentEpisode;
    // Clicking a watched episode unwatches back to the one before it; clicking
    // an unwatched one marks everything up to and including it.
    final nextVal = number <= current ? number - 1 : number;
    final owner = _media;
    final seriesTotalBefore = _seriesEpisodes.current;

    final updatedSeasons = [
      for (final s in _seasons)
        if (s.id == target.id) _seasonWithEpisode(s, nextVal) else s,
    ];
    setState(() {
      _episodeBusy = target.id;
      _progressError = null;
      _media = owner?.copyWithFields(seasons: updatedSeasons);
    });

    if (owner != null) {
      // Rule 1: the exact 0 → 1 step of the series total flips the badge.
      final seriesTotalAfter = seriesTotalBefore + (nextVal - current);
      if (shouldPromoteToInProgress(seriesTotalBefore, seriesTotalAfter) &&
          owner.status != MediaStatus.inProgress) {
        setState(() {
          _statusValue = MediaStatus.inProgress;
          _media = owner.copyWithFields(
              status: MediaStatus.inProgress, seasons: updatedSeasons);
        });
      }
      applyOptimisticProgress(_container, owner.id, seriesTotalAfter);
    }

    try {
      await ref.read(apiClientProvider).setSeasonProgress(target.id, nextVal);
      // Refresh only after the write landed.
      if (mounted) widget.onUpdate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _episodeBusy = '';
        _media = owner?.copyWithFields(seasons: [
          for (final s in updatedSeasons)
            if (s.id == target.id) _seasonWithEpisode(s, current) else s,
        ]);
      });
      if (owner != null) clearOptimisticProgress(_container, owner.id);
      widget.onUpdate();
      setState(() => _progressError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _episodeBusy = '');
    }
  }

  Future<void> _toggleEpisodeOf(String seasonId, int number) async {
    final views = _seasonViews.where((view) => view.season.id == seasonId).toList();
    if (views.isEmpty) return;
    await _setEpisodeProgress(views.first.season, number);
  }

  /// The banner's main action: marks the series-wide next episode as watched.
  Future<void> _watchNextUp(NextUp target) async {
    final views =
        _seasonViews.where((view) => view.season.id == target.seasonId).toList();
    if (views.isEmpty) return;
    await _setEpisodeProgress(views.first.season, target.episodeNumber);
  }

  /// The season-header toggle is two-way: an unfinished season jumps to 100%
  /// (status Completed), a finished one rolls back to 0.
  Future<void> _toggleSeasonCompleteOf(String seasonId) async {
    final views =
        _seasonViews.where((view) => view.season.id == seasonId).toList();
    if (views.isEmpty) return;
    final target = views.first.season;
    final total = target.totalEpisodes;
    if (total <= 0 || _episodeBusy.isNotEmpty) return;

    final previous = target.currentEpisode;
    final completing = previous < total;
    final nextVal = completing ? total : 0;
    final owner = _media;
    final seriesTotalBefore = _seriesEpisodes.current;

    final updatedSeasons = [
      for (final s in _seasons)
        if (s.id == target.id) _seasonWithEpisode(s, nextVal) else s,
    ];
    if (mounted) {
      setState(() {
        _episodeBusy = target.id;
        _progressError = null;
        _media = owner?.copyWithFields(seasons: updatedSeasons);
      });
    }
    if (owner != null) {
      applyOptimisticProgress(
          _container, owner.id, seriesTotalBefore + (nextVal - previous));
    }

    try {
      await ref.read(apiClientProvider).setSeasonProgress(target.id, nextVal);
      if (mounted) {
        widget.onUpdate();
        showToast(
          ref,
          ToastOptions(
            title: completing
                ? _t.tr('detail.markSeasonWatched')
                : _t.tr('detail.resetSeason'),
            description: _t.tr('toast.descUpdated'),
            type: completing ? ToastType.success : ToastType.warning,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _episodeBusy = '';
        _media = owner?.copyWithFields(seasons: [
          for (final s in updatedSeasons)
            if (s.id == target.id) _seasonWithEpisode(s, previous) else s,
        ]);
      });
      if (owner != null) clearOptimisticProgress(_container, owner.id);
      widget.onUpdate();
      setState(() => _progressError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _episodeBusy = '');
    }
  }

  // ------------------------------------------------------------------
  // Refresh / relink / fill-missing / watched-on / platform / translate /
  // achievements.
  // ------------------------------------------------------------------

  Future<void> _handleRefreshMetadata([bool fillMissing = false]) async {
    final target = _media;
    if (target == null || _refreshBusy) return;
    setState(() {
      _refreshInFlight = true;
      _refreshError = null;
    });
    try {
      final updated =
          await ref.read(apiClientProvider).refreshMetadata(target.id, fillMissing: fillMissing);
      setState(() {
        _media = updated;
        _syncFrom(updated);
      });
      showToast(
        ref,
        ToastOptions(
          title: fillMissing
              ? _t.tr('detail.metadataMergeKept')
              : _t.tr('detail.metadataUpdated'),
          description: _t.tr('toast.descUpdated'),
        ),
      );
    } catch (error) {
      setState(() => _refreshError = error);
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshInFlight = false);
    }
  }

  /// A row the user hand-edited cannot be overwritten behind their back, so
  /// refresh asks first.
  Future<void> _requestRefresh() async {
    if (_media?.isCustomEdited == true) {
      setState(() => _overwritePromptOpen = true);
      return;
    }
    await _handleRefreshMetadata(false);
  }

  void _resolveOverwrite(bool fillMissing) {
    setState(() => _overwritePromptOpen = false);
    unawaited(_handleRefreshMetadata(fillMissing));
  }

  Future<void> _handleFillMissing(String source) async {
    final target = _media;
    if (target == null || _fillMissingBusy) return;
    setState(() => _fillMissingBusy = true);
    try {
      final updated = await ref
          .read(apiClientProvider)
          .enrichMedia(target.id, source: source.isEmpty ? null : source);
      setState(() {
        _media = updated;
        _syncFrom(updated);
        _fillMissingOpen = false;
      });
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('detail.fillMissingDone'),
          description: _t.tr('toast.descUpdated'),
        ),
      );
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(error, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _fillMissingBusy = false);
    }
  }

  /// Drops the freshly re-pointed payload in place: the season list and the
  /// spec sheet move with it.
  void _applyRelinked(MediaDetail payload) {
    setState(() {
      _media = payload;
      _syncFrom(payload);
      _related = const <RelatedEntry>[];
      _relatedError = null;
      _lastRelatedSource = null;
      _relinkOpen = false;
    });
    widget.onUpdate();
    unawaited(_loadRelated(payload, null));
    showToast(
      ref,
      ToastOptions(
        title: _isRu ? 'Источник изменён.' : 'Source changed.',
        description: _t.tr('toast.descUpdated'),
      ),
    );
  }

  Future<void> _saveWatchedOn() async {
    final target = _media;
    if (target == null) return;
    final value = _watchedOnInput.trim();
    setState(() {
      _media = _clearFields(
          target, ['watchedOn'], {'watchedOn': value.isEmpty ? null : value});
      _watchedOnDirty = false;
    });
    try {
      await ref.read(apiClientProvider).updateMedia(
            target.id,
            UpdateMediaPayload(
              watchedOn: value.isEmpty ? null : value,
              clearWatchedOn: value.isEmpty,
            ),
          );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _media = _clearFields(target, ['watchedOn'], {});
        _watchedOnDirty = false;
      });
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(err, _t.locale),
          type: ToastType.error,
        ),
      );
    }
  }

  Future<void> _updateUserPlatform(String val) async {
    final target = _media;
    if (target == null) return;
    setState(() {
      _media = _clearFields(target, ['userPlatform'],
          {'userPlatform': val.isEmpty ? null : val});
    });
    try {
      // A null UserPlatform means "not supplied" to the server, so clearing
      // needs the explicit flag.
      await ref.read(apiClientProvider).updateMedia(
            target.id,
            UpdateMediaPayload(
              userPlatform: val.isEmpty ? null : val,
              clearUserPlatform: val.isEmpty,
            ),
          );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _media = _clearFields(target, ['userPlatform'], {});
      });
    }
  }

  Future<void> _toggleTranslateSynopsis() async {
    final media = _media;
    if (media == null || _synopsisText.isEmpty || _translatingSynopsis) return;

    if (_isSynopsisTranslated) {
      setState(() => _isSynopsisTranslated = false);
      return;
    }

    // Check if we already have a cached translation in DB matching current
    // language.
    final targetLang = _isEnLocale ? 'en' : 'ru';
    if (media.translatedSynopsis != null &&
        media.translationLanguage == targetLang) {
      setState(() {
        _translatedSynopsis = media.translatedSynopsis;
        _isSynopsisTranslated = true;
      });
      return;
    }

    if (_translatedSynopsis != null) {
      setState(() => _isSynopsisTranslated = true);
      return;
    }

    setState(() => _translatingSynopsis = true);
    try {
      final translated =
          await ref.read(apiClientProvider).translateText(_synopsisText, targetLanguage: targetLang);
      if (mounted) {
        setState(() {
          _translatedSynopsis = translated;
          _isSynopsisTranslated = true;
        });
      }
      // Persist to DB (fire-and-forget, don't block UI).
      unawaited(ref
          .read(apiClientProvider)
          .updateMedia(
              media.id,
              UpdateMediaPayload(
                translatedSynopsis: translated,
                translationLanguage: targetLang,
              ))
          .then((_) {}, onError: (Object _) {}));
    } catch (err) {
      if (mounted) {
        showToast(
          ref,
          ToastOptions(
            title: _t.tr('toast.actionFailed'),
            description: errorMessage(err, _t.locale),
            type: ToastType.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _translatingSynopsis = false);
    }
  }

  Future<void> _toggleAchievement(String name) async {
    final media = _media;
    if (media == null) return;
    // Match case-insensitively but persist the source spelling.
    final key = name.toLowerCase().trim();
    final nextMap = Map<String, String>.from(_unlockedAchievementNames);
    final previousJson = media.unlockedAchievements;

    if (nextMap.containsKey(key)) {
      nextMap.remove(key);
    } else {
      nextMap[key] = name.trim();
    }

    final jsonStr = jsonEncode(nextMap.values.toList());
    setState(() => _media = media.copyWithFields(unlockedAchievements: jsonStr));
    try {
      await ref
          .read(apiClientProvider)
          .updateMedia(media.id, UpdateMediaPayload(unlockedAchievements: jsonStr));
    } catch (err) {
      if (!mounted) return;
      setState(() =>
          _media = media.copyWithFields(unlockedAchievements: previousJson));
    }
  }

  Future<void> _toggleAllAchievements() async {
    final media = _media;
    if (media == null || _gameAchievements.isEmpty) return;

    final nextMap = Map<String, String>.from(_unlockedAchievementNames);
    final previousJson = media.unlockedAchievements;

    if (_allAchievementsUnlocked) {
      for (final ach in _gameAchievements) {
        nextMap.remove(ach.name.toLowerCase().trim());
      }
    } else {
      for (final ach in _gameAchievements) {
        nextMap[ach.name.toLowerCase().trim()] = ach.name.trim();
      }
    }

    final jsonStr = jsonEncode(nextMap.values.toList());
    setState(() {
      _achievementsBusy = true;
      _media = media.copyWithFields(unlockedAchievements: jsonStr);
    });
    try {
      await ref
          .read(apiClientProvider)
          .updateMedia(media.id, UpdateMediaPayload(unlockedAchievements: jsonStr));
    } catch (err) {
      if (!mounted) return;
      setState(() =>
          _media = media.copyWithFields(unlockedAchievements: previousJson));
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('toast.actionFailed'),
          description: errorMessage(err, _t.locale),
          type: ToastType.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _achievementsBusy = false);
    }
  }

  /// После мутации linked-sources — родитель перечитывает карточку.
  Future<void> _refreshAfterSourceChange() async {
    if (_media == null) return;
    try {
      final loaded = await _refreshMediaDetail(_container, widget.mediaId);
      if (loaded.id != widget.mediaId || !mounted) return;
      setState(() {
        _media = loaded;
        _syncFrom(loaded);
      });
      ref.read(mediaDetailCacheProvider).invalidate(loaded.id);
      widget.onUpdate();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Derived ($derived-аналоги — геттеры по текущему состоянию).
  // ------------------------------------------------------------------

  ProviderContainer get _container => ProviderScope.containerOf(context);

  I18nDictionary get _t => ref.read(tProvider);
  bool get _isRu => ref.read(i18nProvider).wire == 'ru';
  bool get _isEnLocale => ref.read(i18nProvider).wire == 'en';

  /// The live feed wins over the stored flag.
  bool get _isSyncing {
    final media = _media;
    if (media == null) return false;
    final job = ref.read(jobsClientProvider.notifier).jobFor(media.id);
    if (job != null) {
      return job.status == JobStatus.running || job.status == JobStatus.queued;
    }
    return media.syncStatus == SyncStatus.syncing;
  }

  /// The POST only enqueues the job, so the button must stay blocked until the
  /// live job settles.
  bool get _refreshBusy => _refreshInFlight || _isSyncing;

  String? get _syncStep {
    final media = _media;
    if (media == null) return null;
    return ref.read(jobsClientProvider.notifier).jobFor(media.id)?.currentStep;
  }

  ProgressInfo? get _progressInfo =>
      _media != null ? readProgress(_media!, _t) : null;

  List<TvSeason> get _seasons =>
      (_media != null && isTvShowDetail(_media!) ? _media!.seasons : null) ??
      const <TvSeason>[];

  List<({TvSeason season, List<EpisodeRow> episodes})> get _seasonViews => [
        for (final season in _seasons)
          (season: season, episodes: buildEpisodes(season, _t)),
      ];

  String? get _originalTitle =>
      _media != null ? readOriginalTitle(_media!) : null;

  String get _synopsisText => _media?.description?.trim() ?? '';
  bool get _synopsisExpandable => _synopsisText.length > 280;

  /// The first unwatched episode of the series, not of any one season.
  NextUp? get _nextUp {
    for (final view in _seasonViews) {
      final watched = view.season.currentEpisode;
      final total = view.season.totalEpisodes;
      if (total <= 0 || watched >= total) continue;
      return NextUp(
        seasonId: view.season.id,
        seasonNumber: view.season.seasonNumber,
        episodeNumber: watched + 1,
      );
    }
    return null;
  }

  double get _progressPercent {
    final info = _progressInfo;
    final total = info?.total ?? 0;
    if (total <= 0) return 0;
    return (_progressValue / total).clamp(0, 1) * 100;
  }

  /// Series-wide counters.
  ({int current, int total}) get _seriesEpisodes =>
      _seriesEpisodesOf(_seasons);

  ({int current, int total}) _seriesEpisodesOf(List<TvSeason> seasons) {
    var current = 0;
    var total = 0;
    for (final season in seasons) {
      current += season.currentEpisode;
      total += season.totalEpisodes;
    }
    return (current: current, total: total);
  }

  double get _seriesProgressPercent {
    final eps = _seriesEpisodes;
    return eps.total > 0
        ? (eps.current / eps.total).clamp(0, 1) * 100
        : 0.0;
  }

  /// A show's overview card uses the season totals already on screen.
  ProgressInfo? get _episodeProgress {
    final eps = _seriesEpisodes;
    return eps.total > 0
        ? ProgressInfo(
            current: eps.current,
            total: eps.total,
            editable: true,
            label: _t.tr('detail.episodesLabel'),
          )
        : null;
  }

  bool get _isSeriesOverview => _media?.type == MediaType.tvshow;

  ProgressInfo? get _overviewSupport =>
      _isSeriesOverview ? _episodeProgress : _progressInfo;

  int get _overviewValue =>
      _isSeriesOverview ? _seriesEpisodes.current : _progressValue;

  double get _overviewPercent =>
      _isSeriesOverview ? _seriesProgressPercent : _progressPercent;

  /// lowercase key -> the name as the source spelled it.
  Map<String, String> get _unlockedAchievementNames {
    final media = _media;
    if (media == null || media.unlockedAchievements == null) {
      return const <String, String>{};
    }
    try {
      final parsed = jsonDecode(media.unlockedAchievements!);
      if (parsed is List) {
        final map = <String, String>{};
        for (final entry in parsed) {
          final original = entry.toString();
          map[original.toLowerCase().trim()] = original;
        }
        return map;
      }
    } catch (_) {}
    return const <String, String>{};
  }

  bool get _allAchievementsUnlocked {
    if (_gameAchievements.isEmpty) return false;
    final names = _unlockedAchievementNames;
    return _gameAchievements
        .every((ach) => names.containsKey(ach.name.toLowerCase().trim()));
  }

  /// The source reported more achievements than we received (page cap).
  bool get _achievementsTruncated =>
      _gameAchievementsTotal > _gameAchievements.length;

  List<String> get _gamePlatformOptions {
    final media = _media;
    if (media == null || media.type != MediaType.game) {
      return const <String>[];
    }
    final opts = <String>{};
    for (final p in (media.platform ?? '').split(',')) {
      final trimmed = p.trim();
      if (trimmed.isNotEmpty) opts.add(trimmed);
    }
    if (media.userPlatform != null && !opts.contains(media.userPlatform)) {
      opts.add(media.userPlatform!);
    }
    return opts.toList();
  }

  List<RatingBadge> get _externalRatings {
    final media = _media;
    if (media == null) return const <RatingBadge>[];

    // The stored JSON is PascalCase from some providers and camelCase from
    // others.
    List<RawRating> ratings = <RawRating>[];
    if (media.externalRatingsJson != null) {
      try {
        final parsed = jsonDecode(media.externalRatingsJson!);
        if (parsed is List) {
          for (final r in parsed) {
            if (r is! Map<String, Object?>) continue;
            final score = r['score'] is num
                ? (r['score'] as num).toDouble()
                : r['Score'] is num
                    ? (r['Score'] as num).toDouble()
                    : r['rating'] is num
                        ? (r['rating'] as num).toDouble()
                        : r['Rating'] is num
                            ? (r['Rating'] as num).toDouble()
                            : null;
            ratings.add(RawRating(
              source: ((r['source'] ?? r['Source']) as String? ?? '').trim(),
              rating: score,
              votes: r['votes'] is num
                  ? (r['votes'] as num).toInt()
                  : r['Votes'] is num
                      ? (r['Votes'] as num).toInt()
                      : null,
              // Present in the stored JSON means the source answered.
              queried: true,
            ));
          }
        }
      } catch (_) {}
    }

    // Offline databases feed metadata, not scores.
    ratings = ratings
        .where((r) => !_offlineSourceRe.hasMatch(r.source))
        .toList();

    // The LibSocial ecosystem answers under several aliases: collapse them
    // into one row per site, preferring the exact site name over the umbrella.
    final byFamily = <String, RawRating>{};
    for (final r in ratings) {
      final key = r.source.toLowerCase();
      final family = _libFamilyRe.hasMatch(key) ? 'lib' : key;
      final existing = byFamily[family];
      if (existing == null) {
        byFamily[family] = r;
        continue;
      }
      final existingIsUmbrella = existing.source.toLowerCase() == 'sociallib';
      final candidateIsUmbrella = key == 'sociallib';
      final better =
          (existingIsUmbrella && !candidateIsUmbrella) ||
                  ((existing.rating == null || existing.rating == 0) &&
                      r.rating != null && r.rating != 0)
              ? r
              : existing;
      byFamily[family] = better;
    }
    ratings = byFamily.values.toList();

    final cat = (media.isAnime ?? false) ? 'anime' : media.type.wire;

    final linkedSourceNames = <String>[];
    if (media.externalSource != null) {
      linkedSourceNames.add(media.externalSource!);
    }
    if (media.linkedSources != null) {
      for (final s in media.linkedSources!) {
        if (s.source.isNotEmpty) linkedSourceNames.add(s.source);
      }
    } else if ((media.linkedSourcesJson ?? '').trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(media.linkedSourcesJson!);
        if (parsed is List) {
          for (final s in parsed) {
            if (s is Map<String, Object?>) {
              final name =
                  (s['source'] ?? s['Source'])?.toString();
              if (name != null && name.isNotEmpty) linkedSourceNames.add(name);
            }
          }
        }
      } catch (_) {}
    }

    return buildRatingBadges(RatingBadgeInput(
      ratings: ratings,
      fallback: (media.externalRating ?? 0) > 0
          ? FallbackRating(
              source: dataSource(media),
              score: media.externalRating!,
              votes: media.externalRatingVotes,
            )
          : null,
      category: cat,
      availableSources: _availableSources,
      fallbackSources: kCategoryExpectedSources[cat] ?? const <String>[],
      linkedSources: linkedSourceNames,
    ));
  }

  List<RatingBadge> get _previewRelatedBadges {
    final item = _previewRelatedItem;
    if (item == null) return const <RatingBadge>[];

    final ratings = (item.ratings ?? const <RatingBadge>[])
        .map((r) => RawRating(
              source: r.source,
              rating: r.score,
              queried: r.queried,
            ))
        .toList();

    // A single top-level score still deserves a badge when the source reported
    // no list.
    final fallback = (item.score ?? 0) != 0 && item.score != null
        ? FallbackRating(
            source: item.externalSource ??
                (item.type == 'manga' || item.type == 'anime'
                    ? 'AniList'
                    : 'TMDB'),
            score: item.score!,
          )
        : null;

    return buildRatingBadges(RatingBadgeInput(
      ratings: ratings,
      fallback: fallback,
      category: item.type,
      availableSources: _availableSources,
      fallbackSources:
          kCategoryExpectedSources[item.type] ?? const ['AniList'],
    ));
  }

  List<RelationGroup> get _relatedGroups {
    if (_related.isEmpty) return const <RelationGroup>[];

    final main = <RelatedEntry>[];
    final spinoffs = <RelatedEntry>[];
    final adaptations = <RelatedEntry>[];
    final others = <RelatedEntry>[];

    for (final item in _related) {
      final raw = (item.rawRelationType ?? '').toUpperCase();
      if (raw == 'SEQUEL' || raw == 'PREQUEL') {
        main.add(item);
      } else if (raw == 'SIDE_STORY' ||
          raw == 'SPIN_OFF' ||
          raw == 'CHARACTER') {
        spinoffs.add(item);
      } else if (raw == 'ADAPTATION' ||
          item.type == 'manga' ||
          ['MANGA', 'NOVEL', 'ONE_SHOT']
              .contains((item.format ?? '').toUpperCase())) {
        adaptations.add(item);
      } else {
        others.add(item);
      }
    }

    final groups = <RelationGroup>[];
    if (main.isNotEmpty) {
      groups.add(RelationGroup(
          id: 'main', title: _t.tr('detail.groupMain'), items: main));
    }
    if (spinoffs.isNotEmpty) {
      groups.add(RelationGroup(
          id: 'spinoffs', title: _t.tr('detail.groupSpinoffs'), items: spinoffs));
    }
    if (adaptations.isNotEmpty) {
      groups.add(RelationGroup(
          id: 'adaptations',
          title: _t.tr('detail.groupAdaptations'),
          items: adaptations));
    }
    if (others.isNotEmpty) {
      groups.add(RelationGroup(
          id: 'others', title: _t.tr('detail.groupOthers'), items: others));
    }

    return groups;
  }

  List<TimelineEntry> get _timelineEntries {
    final media = _media;
    if (media == null) return const <TimelineEntry>[];

    final current = TimelineEntry(
      id: media.id,
      title: media.title,
      coverUrl: media.coverUrl,
      year: _yearOf(media.releaseDate),
      formatDisplay: currentFormatLabel(media, _t),
      relationType: _t.tr('detail.currentTitleBadge'),
      isCurrent: true,
      localItem: media,
    );

    final items = <TimelineEntry>[
      current,
      ..._related.map((r) => TimelineEntry(
            id: r.id,
            title: r.title,
            coverUrl: r.coverUrl,
            year: r.year,
            formatDisplay: formatMediaDisplayType(r.type, r.format, _t),
            relationType: r.relationType ?? _t.tr('detail.relations.other'),
            isCurrent: false,
            localItem: r.localItem,
            rawItem: r,
          )),
    ];

    // Entries with a known year sort by it; the rest keep their order at the
    // end.
    items.sort((a, b) {
      if (a.year != null && b.year != null) return a.year! - b.year!;
      if (a.year != null) return -1;
      if (b.year != null) return 1;
      return 0;
    });
    return items;
  }

  void _selectSubTab(SubTab tab) {
    final from = _tabOrder.indexOf(_activeSubTab);
    final to = _tabOrder.indexOf(tab);
    setState(() {
      _tabDirection = to >= from ? 1 : -1;
      _activeSubTab = tab;
    });
    if (tab == SubTab.related) {
      unawaited(_maybeAutoLoadRelated());
    }
  }

  // ------------------------------------------------------------------
  // Build.
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final media = _media;
    final isLoading = _isLoading;

    // $effect: job completed/failed → refetch (ref.listen — один раз за прогон
    // через settledJobId).
    ref.listen<JobsState>(jobsClientProvider, (previous, next) {
      final mediaId = widget.mediaId;
      final job = ref.read(jobsClientProvider.notifier).jobFor(mediaId);
      if (job == null) return;
      if (job.status == JobStatus.failed) {
        if (job.jobId == _settledJobId) return;
        _settledJobId = job.jobId;
        setState(() {
          _refreshError = job.errorMessage ?? 'Metadata refresh failed';
        });
        showToast(
          ref,
          ToastOptions(
            title: t.tr('toast.actionFailed'),
            description: errorMessage(_refreshError!, t.locale),
            type: ToastType.error,
          ),
        );
        unawaited(_refreshMediaDetail(_container, mediaId).then((loaded) {
          if (loaded.id != mediaId || !mounted) return;
          setState(() {
            _media = loaded;
            _syncFrom(loaded);
          });
        }));
        return;
      }
      if (job.status != JobStatus.completed) return;
      if (job.jobId == _settledJobId) return;

      _settledJobId = job.jobId;
      unawaited(_refreshMediaDetail(_container, mediaId).then((loaded) async {
        if (loaded.id != mediaId || !mounted) return;
        setState(() {
          _media = loaded;
          _syncFrom(loaded);
        });
        ref.read(mediaDetailCacheProvider).invalidate(loaded.id);
        _achievementsCache.invalidate(loaded.id);
        _enrichedMediaIds.remove(loaded.id);
        if (loaded.type == MediaType.game) {
          unawaited(_loadGameAchievements(loaded, force: true));
        }
        unawaited(_loadRelated(loaded, null));
        widget.onUpdate();
      }).catchError((Object _) {}));
    });

    return KeyboardListener(
      focusNode: _escapeFocus,
      onKeyEvent: (event) {
        // svelte:window: Escape → закрыть превью внешнего тайтла.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _previewRelatedItem != null) {
          setState(() => _previewRelatedItem = null);
        }
      },
      child: Stack(
        children: [
          Padding(
        padding: const EdgeInsets.only(bottom: 20), // space-y-5 хвост
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BackRow(t: t, th: th, onBack: widget.onBack),
            const SizedBox(height: 20), // space-y-5
            if (media == null && isLoading)
              _DetailSkeleton(th: th)
            else if (media == null)
              _ErrorBoxView(
                t: t,
                th: th,
                message: _loadError != null
                    ? errorMessage(_loadError!, t.locale)
                    : t.tr('detail.notFound'),
                canRetry: _loadError != null,
                onRetry: _retry,
              )
            else ...[
              Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Poster, Status + Rating, History, Actions.
                    DetailSidebar(
                      media: media,
                      statusOptions: const [
                        MediaStatus.planned,
                        MediaStatus.inProgress,
                        MediaStatus.completed,
                        MediaStatus.onHold,
                        MediaStatus.dropped,
                      ],
                      statusBusy: _statusBusy,
                      onChangeStatus: _changeStatus,
                      statusError: _statusError,
                      scoreValue: _scoreValue,
                      ratingOpen: _userRatingPopoverOpen,
                      onRatingOpen: _openRatingPopover,
                      onRatingClose: _closeRatingPopover,
                      onRatingHide: _hideRatingPopover,
                      onSetScore: _setScore,
                      onClearScore: _clearScore,
                      onSaveDetailedScore: _saveDetailedScore,
                      formatDate: (value) => formatDate(value, t),
                      watchedOnInput: _watchedOnInput,
                      onWatchedOnInput: (value) {
                        setState(() {
                          _watchedOnInput = value;
                          _watchedOnDirty = true;
                        });
                      },
                      onWatchedOnDirty: () => _watchedOnDirty = true,
                      onSaveWatchedOn: _saveWatchedOn,
                      platformOptions: _gamePlatformOptions,
                      onSelectPlatform: _updateUserPlatform,
                      refreshBusy: _refreshBusy,
                      syncStep: _syncStep,
                      refreshError: _refreshError,
                      onRefreshMetadata: _requestRefresh,
                      fillMissingBusy: _fillMissingBusy,
                      onFillMissing: () =>
                          setState(() => _fillMissingOpen = true),
                      onRelink: () => setState(() => _relinkOpen = true),
                      onStartEdit: _startEdit,
                      deleteBusy: _deleteBusy,
                      deleteError: _deleteError,
                      onDelete: _removeMedia,
                      onAutoRefreshed: (updated) {
                        setState(() {
                          _media = updated;
                          _syncFrom(updated);
                        });
                        widget.onUpdate();
                      },
                      onMediaUpdated: (updated) {
                        setState(() {
                          _media = updated;
                          _syncFrom(updated);
                        });
                        widget.onUpdate();
                      },
                      specRows: specRows(media, t),
                      syncing: _isSyncing,
                    ),
                    const SizedBox(width: 24), // gap-6
                    // Right Column: Header, Badges, Tabs, Tab Content.
                    Expanded(
                      child: _RightColumn(
                        state: this,
                        t: t,
                        th: th,
                        media: media,
                      ),
                    ),
                  ],
                ),
            ],
            // Модалки: нативный popover — top-layer браузера; Flutter-аналог
            // OverlayPortal (Stack-модалка внутри скролл-контейнера получает
            // бесконечную высоту).
            _OverlayModal(
              isOpen: _relinkOpen,
              modal: RelinkSourceModal(
              isOpen: _relinkOpen,
              mediaId: widget.mediaId,
              title: _media?.title ?? '',
              originalTitle: _originalTitle,
              type: _relinkType,
              currentSource: _media?.externalSource,
              onClose: () => setState(() => _relinkOpen = false),
              onRelinked: _applyRelinked,
              ),
            ),
            _OverlayModal(
              isOpen: _overwritePromptOpen,
              modal: OverwriteConfirmModal(
              isOpen: _overwritePromptOpen,
              busy: _refreshBusy,
              onFillMissing: () => _resolveOverwrite(true),
              onOverwrite: () => _resolveOverwrite(false),
              onClose: () => setState(() => _overwritePromptOpen = false),
              ),
            ),
            _OverlayModal(
              isOpen: _fillMissingOpen,
              modal: FillMissingModal(
              isOpen: _fillMissingOpen,
              busy: _fillMissingBusy,
              media: _media,
              mediaType: _media?.type.wire ?? 'movie',
              currentSource: _media?.externalSource,
              onFill: (source) => unawaited(_handleFillMissing(source)),
              onClose: () => setState(() => _fillMissingOpen = false),
              ),
            ),
          ],
        ),
          ),
          // PREVIEW MODAL FOR UNADDED RELATED ITEMS.
          _OverlayModal(
            isOpen: _previewRelatedItem != null,
            modal: RelatedPreviewModal(
              item: _previewRelatedItem,
              badges: _previewRelatedBadges,
              loading: _previewRelatedLoading,
              adding: _previewAddingBusy,
              status: _previewStatus,
              onStatusChange: (v) => setState(() => _previewStatus = v),
              onAdd: (status) {
                final rel = _previewRelatedItem;
                if (rel != null) {
                  unawaited(_addRelatedToLibrary(rel, status));
                }
              },
              onClose: () => setState(() => _previewRelatedItem = null),
              ),
            ),
        ],
      ),
    );
  }

  /// (media?.type === 'tvshow' || 'movie') && isAnime → 'anime'.
  String get _relinkType {
    final media = _media;
    final type = media?.type ?? MediaType.movie;
    if ((type == MediaType.tvshow || type == MediaType.movie) &&
        (media?.isAnime ?? false)) {
      return 'anime';
    }
    return type.wire;
  }
}

/// Top-layer mounting для модалок (аналог native popover top-layer).
class _OverlayModal extends ConsumerStatefulWidget {
  final bool isOpen;
  final Widget modal;

  const _OverlayModal({required this.isOpen, required this.modal});

  @override
  ConsumerState<_OverlayModal> createState() => _OverlayModalState();
}

class _OverlayModalState extends ConsumerState<_OverlayModal> {
  final OverlayPortalController _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isOpen) _portal.show();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _OverlayModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.isOpen && !_portal.isShowing) {
          _portal.show();
        } else if (!widget.isOpen && _portal.isShowing) {
          _portal.hide();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => widget.modal,
      child: const SizedBox.shrink(),
    );
  }
}

/// Back-кнопка (uppercase tracking-wider).
class _BackRow extends ConsumerStatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final VoidCallback onBack;

  const _BackRow({required this.t, required this.th, required this.onBack});

  @override
  ConsumerState<_BackRow> createState() => _BackRowState();
}

class _BackRowState extends ConsumerState<_BackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onBack,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrowLeft,
                size: 16,
                color: _hovered ? Colors.white : widget.th.textSecondary),
            const SizedBox(width: 6), // gap-1.5
            Text(
              widget.t.tr('common.back').toUpperCase(),
              style: TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w600, // font-semibold
                letterSpacing: 0.06 * 12, // tracking-wider
                color: _hovered ? Colors.white : widget.th.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Скелетон загрузки (grid 20rem + 1fr).
class _DetailSkeleton extends StatelessWidget {
  final TsundokuTheme th;

  const _DetailSkeleton({required this.th});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320, // lg:grid-cols-[20rem_...]
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
                color: th.bgCard, // bg-card
              ),
            ),
          ),
        ),
        const SizedBox(width: 24), // gap-6
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 36, // h-9
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: th.bgCard,
                ),
              ),
              const SizedBox(height: 16), // space-y-4
              Container(
                height: 16, // h-4
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: th.bgCard,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 160, // h-40
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(TsundokuPalette.radiusBox),
                  color: th.bgCard,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Error-box (min-h-72 rose).
class _ErrorBoxView extends ConsumerStatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  const _ErrorBoxView({
    required this.t,
    required this.th,
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  @override
  ConsumerState<_ErrorBoxView> createState() => _ErrorBoxViewState();
}

class _ErrorBoxViewState extends ConsumerState<_ErrorBoxView> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 288), // min-h-72
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(TsundokuPalette.radiusBox), // rounded-xl
        color: Colors.white.withAlpha(13), // bg-rose-400/5 близко
      ),
      padding: const EdgeInsets.all(24), // p-6
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: const Color(0xFFFECDD3)), // rose-200
          ),
          if (widget.canRetry) ...[
            const SizedBox(height: 12), // gap-3
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: widget.onRetry,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8), // px-4 py-2
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6), // rounded-md
                    color: _hovered ? widget.th.accentHover : widget.th.accent,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.refreshCw,
                          size: 15, color: Colors.white),
                      const SizedBox(width: 8), // gap-2
                      Text(
                        widget.t.tr('common.retry'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Правая колонка: DetailHeader + DetailTabs + панель табов + превью-модал.
class _RightColumn extends ConsumerStatefulWidget {
  final _MediaDetailViewState state;
  final I18nDictionary t;
  final TsundokuTheme th;
  final MediaDetail media;

  const _RightColumn({
    required this.state,
    required this.t,
    required this.th,
    required this.media,
  });

  @override
  ConsumerState<_RightColumn> createState() => _RightColumnState();
}

class _RightColumnState extends ConsumerState<_RightColumn> {
  ProviderContainer get _container => ProviderScope.containerOf(context);

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final t = widget.t;
    final media = widget.media;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        detail_header.DetailHeader(
          title: media.title,
          originalTitle: st._originalTitle,
          tags: tags(media, t),
          ratings: [
            for (final r in st._externalRatings)
              detail_header.RatingBadge(
                  source: r.source, score: r.score, votes: r.votes),
          ],
          synopsisText: st._synopsisText,
          synopsisExpanded: st._synopsisExpanded,
          synopsisExpandable: st._synopsisExpandable,
          synopsisTranslated: st._isSynopsisTranslated,
          translatedSynopsis: st._translatedSynopsis,
          translatingSynopsis: st._translatingSynopsis,
          onToggleTranslate: () => unawaited(st._toggleTranslateSynopsis()),
          onToggleExpand: () =>
              setState(() => st._synopsisExpanded = !st._synopsisExpanded),
        ),
        const SizedBox(height: 24), // space-y-6
        DetailTabs(
          active: st._activeSubTab,
          mediaType: media.type.wire,
          seasonProgress:
              st._seriesEpisodes.total > 0
                  ? (
                      current: st._seriesEpisodes.current,
                      total: st._seriesEpisodes.total,
                    )
                  : null,
          relatedCount: st._related.length,
          galleryCount: media.gallery?.length ?? 0,
          onSelect: st._selectSubTab,
        ),
        const SizedBox(height: 24),
        // Panel stack: incoming slides over, outgoing recedes (grid cell
        // overlap → AnimatedSwitcher stack).
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic, // cubicOut
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topLeft,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          transitionBuilder: (child, animation) {
            // Incoming: translateX(28 * direction) + opacity. Outgoing:
            // scale 0.97..1 + opacity.
            final isIncoming = child.key == ValueKey(st._activeSubTab);
            if (isIncoming) {
              return FadeTransition(
                opacity: animation,
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => Transform.translate(
                    offset: Offset(
                        28 * st._tabDirection * (1 - animation.value), 0),
                    child: child,
                  ),
                ),
              );
            }
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey(st._activeSubTab),
            color: const Color(0xFF0D0F14), // bg-[#0d0f14]
            child: _buildTabPanel(st, t, media),
          ),
        ),
      ],
    );
  }

  Widget _buildTabPanel(
      _MediaDetailViewState st, I18nDictionary t, MediaDetail media) {
    switch (st._activeSubTab) {
      case SubTab.overview:
        return OverviewTab(
          media: media,
          support: st._overviewSupport,
          progressValue: st._overviewValue,
          progressPercent: st._overviewPercent,
          progressError: st._progressError,
          onStep: st._stepOverview,
          onCounterChange: (val) {
            // Shows route through the per-season endpoint; the generic PUT
            // /progress rejects them.
            if (st._isSeriesOverview) {
              unawaited(st._commitSeriesCounter(val));
              return;
            }
            final target = st._media;
            if (target == null) return;
            final next = val > 0 ? val : 0;
            st.setState(() {
              st._pendingSnapshot ??= st._committedProgress;
              st._progressValue = next;
              st._progressError = null;
            });
            applyOptimisticProgress(_container, target.id, next);
            writeCardProgress(target, next);
            updateCachedDetailProgressRef(_container, target.id, next);
            st._progressDebounce.schedule(target.id, next);
          },
          achievements: st._gameAchievements,
          achievementsTotal: st._gameAchievementsTotal,
          achievementsLoading: st._gameAchievementsLoading,
          achievementsBusy: st._achievementsBusy,
          achievementsTruncated: st._achievementsTruncated,
          unlockedAchievementNames: st._unlockedAchievementNames,
          onOpenMedia: widget.state.widget.onOpenRelated,
          onEdit: st._startEdit,
          onOpenRelink: () => st.setState(() => st._relinkOpen = true),
          onChanged: () => unawaited(st._refreshAfterSourceChange()),
          onSearch: (creatorName) {
            // The card's search button means "works of this creator".
            final record = st._media;
            if (record == null) {
              widget.state.widget.onSearch(creatorName);
              return;
            }
            final type =
                (record.isAnime ?? false) ? 'anime' : record.type.wire;
            widget.state.widget.onSearch(SearchModalContext(
              query: creatorName,
              type: type,
              source: record.externalSource,
              byCreator: true,
            ));
          },
          onToggleAchievement: st._toggleAchievement,
          onToggleAllAchievements: st._toggleAllAchievements,
          onChangeStatus: st._changeStatus,
        );
      case SubTab.gallery:
        return GalleryTab(
          mediaId: media.id,
          gallery: media.gallery ?? const <MediaGalleryItem>[],
          onChanged: () => unawaited(st._refreshAfterSourceChange()),
        );
      case SubTab.related:
        return RelatedTab(
          media: media,
          related: st._related,
          loading: st._relatedLoading,
          error: st._relatedError,
          viewMode: st._relatedViewMode,
          groups: st._relatedGroups,
          timeline: st._timelineEntries,
          onRetry: () {
            if (st._media != null && st._lastRelatedSource != null) {
              unawaited(st._loadRelated(
                  st._media!, st._lastRelatedSource!,
                  forceRefresh: true));
            }
          },
          onSelectViewMode: (mode) =>
              st.setState(() => st._relatedViewMode = mode),
          onOpen: (rel) => unawaited(st._handleRelatedClick(rel)),
          onLoadFrom: (source, {force = false}) {
            st.setState(() => st._lastRelatedSource = source);
            if (st._media != null) {
              unawaited(st._loadRelated(st._media!, source,
                  forceRefresh: force));
            }
          },
        );
      case SubTab.recommendations:
        return RecommendationsTab(
          items: [
            for (final r in st._recommendations)
              RecommendationItem(
                id: r.id,
                title: r.title,
                coverUrl: r.coverUrl,
                rating: r.rating,
                source: r.source,
              ),
          ],
        );
      case SubTab.episodes:
        // The whole section is tab-gated: the season banner must not leak into
        // Related/Recommendations.
        if (media.type != MediaType.tvshow) return const SizedBox.shrink();
        if (st._isSyncing) {
          return SyncRowsSkeleton(label: t.tr('activity.loadingSeasons'));
        }
        return EpisodesTab(
          seasons: st._seasons,
          nextUp: st._nextUp,
          seriesEpisodes: st._seriesEpisodes,
          seriesProgressPercent: st._seriesProgressPercent,
          episodeBusy: st._episodeBusy,
          progressError: st._progressError,
          sortOrder: st._episodeSortOrder,
          onToggleSort: () => st.setState(() {
            st._episodeSortOrder = st._episodeSortOrder == 'asc' ? 'desc' : 'asc';
          }),
          onToggleSeasonCompleteOf: st._toggleSeasonCompleteOf,
          onToggleEpisodeOf: st._toggleEpisodeOf,
          onSetSeasonProgressOf: st._setSeasonProgressOf,
          onWatchNextUp: st._watchNextUp,
          onSetSeriesCounter: (value) =>
              unawaited(st._commitSeriesCounter(value)),
          onMarkAll: st._markAllSeries,
          onResetAll: st._resetSeries,
          onOpenLists: widget.state.widget.onOpenLists,
          formatDate: (value) => formatDate(value, t),
          startedAt: media.startedAt,
          finishedAt: media.finishedAt,
          episodeDuration:
              media.episodeDurationMinutes ?? media.durationMinutes ?? 24,
          episodesBySeason: st._seasonViews,
        );
    }
  }
}
