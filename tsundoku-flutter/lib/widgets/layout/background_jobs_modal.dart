/// 1:1 port of `mediatracker-ui/src/widgets/layout/BackgroundJobsModal.svelte`.
///
/// Модалка фоновых задач: таб «Очередь» (прогресс/отмена, batch-import ETA)
/// и таб «Review» — master-detail разбор pending-совпадений: поиск кандидатов
/// (в т.ч. по прямой ссылке), скоринг/сортировка, resolve/keep/delete,
/// duplicate-вердикты (merge/keep-separate), hotkeys 1–4/S/Space/Delete,
/// превью кандидата в ExternalDetailModal.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/ui/placeholder404.dart';
import '../../shared/api/api.dart';
import '../../shared/api/jobs_client.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart';
import '../../shared/ui/modal.dart';
import '../../shared/ui/tsundoku_scroll.dart';
import '../../shared/ui/toast.dart';
import '../../shared/ui/tsundoku_image.dart';
import '../../shared/utils/url_media_parser.dart';
import '../media-detail/external_detail_modal.dart';

// ─── Чистые функции скоринга/сортировки (аналог <script module>) ────────────

final RegExp _cyrillicRe = RegExp('[а-яА-ЯёЁ]');
final RegExp _latinLetterRe = RegExp('[a-zA-Z]');

/// Тип кандидата: anime — search-only тип, приоритет у метки hit'а/строки.
String candidateType(ExternalMedia cand, PendingMatchItemDto item) {
  if (cand.type == 'anime' || (item.isAnime ?? false)) return 'anime';
  if (cand.type.isNotEmpty) return cand.type;
  return item.type.isNotEmpty ? item.type : 'manga';
}

const Map<String, List<String>> defaultPriorities = {
  'anime': ['anilist', 'shikimori', 'kitsu', 'simkl', 'sociallib'],
  'manga': ['anilist', 'mangadex', 'shikimori', 'mangaupdates', 'kitsu', 'sociallib'],
  'movie': ['tmdb', 'kinopoisk', 'imdb', 'simkl'],
  'tvshow': ['tmdb', 'kinopoisk', 'imdb', 'simkl'],
  'book': ['sociallib', 'shikimori', 'anilist', 'kitsu', 'openlibrary'],
  'game': ['steam', 'rawg'],
};

String? extractLatin(String title) {
  if (title.isEmpty) return null;
  final match = RegExp(r'\(([^)]*[a-zA-Z]{2,}[^)]*)\)').firstMatch(title);
  if (match != null) return match.group(1)!.trim();
  final isLatin = !_cyrillicRe.hasMatch(title) && _latinLetterRe.hasMatch(title);
  if (isLatin) return title.trim();
  return null;
}

String extractRussian(String title) {
  if (title.isEmpty) return '';
  final match =
      RegExp(r'^([^\(]+)\s*\([^)]*[a-zA-Z][^)]*\)').firstMatch(title);
  if (match != null && _cyrillicRe.hasMatch(match.group(1)!)) {
    return match.group(1)!.trim();
  }
  return title.trim();
}

String _cleanSuffix(String? s) => (s ?? '')
    .replaceAll(
        RegExp(r'\s*[\(\[](?:новелла|манхва|манга|сборник|ранобэ)[\)\]]',
            caseSensitive: false),
        '')
    .trim();

String _norm(String? s) =>
    _cleanSuffix(s).toLowerCase().replaceAll(RegExp('[^a-z0-9а-яё]'), '');

/// Скоринг кандидата 0..100: точное/частичное совпадение названий,
/// direct-url (100), год, автор/студия, количество, manhwa/manga-миссматч.
int scoreCandidate(PendingMatchItemDto item, ExternalMedia cand) {
  // A candidate the user pinned by pasting a direct link is the exact answer, not a guess.
  if (cand.isDirectUrl ?? false) return 100;

  final targets = <String?>[
    item.title,
    item.romajiTitle,
    item.originalTitle,
    extractRussian(item.title),
    extractLatin(item.title),
    ...(item.altTitles ?? const <String>[]),
  ].map(_norm).where((t) => t.isNotEmpty).toList();

  final candTitles = <String?>[
    cand.title,
    cand.originalTitle,
    cand.romajiTitle,
    ...(cand.synonyms ?? const <String>[]),
  ].map(_norm).where((t) => t.isNotEmpty).toList();

  var best = 0;
  for (final t in targets) {
    for (final c in candTitles) {
      if (t == c) {
        best = math.max(best, 60);
      } else if (t.length >= 5 && (t.contains(c) || c.contains(t))) {
        best = math.max(best, 40);
      }
    }
  }

  // Direct search result base score >= 40% (eliminates false 0% for API
  // matches with shared query tokens).
  if (best == 0) {
    final itemTokens = targets
        .expand((t) => RegExp('[a-z0-9а-яё]{3,}').allMatches(t).map((m) => m.group(0)!))
        .toList();
    final candTokens = candTitles
        .expand((c) => RegExp('[a-z0-9а-яё]{3,}').allMatches(c).map((m) => m.group(0)!))
        .toList();
    final shared =
        itemTokens.where((tok) => candTokens.contains(tok)).toList();
    if (shared.isNotEmpty &&
        shared.length >=
            0.3 *
                math.min(itemTokens.isEmpty ? 1 : itemTokens.length,
                    candTokens.isEmpty ? 1 : candTokens.length)) {
      best = 40;
    }
  }

  if (best == 0) return 0;

  var total = best;

  // 1. Release Year
  if (item.releaseYear != null && cand.releaseYear != null) {
    final diff = (item.releaseYear! - cand.releaseYear!).abs();
    if (diff <= 1) {
      total += 20;
    } else if (diff > 2) {
      total -= 25;
    }
  } else if (best >= 60) {
    total += 20;
  }

  // 2. Author / Studio
  final ia = _norm(item.author);
  final ca = _norm(cand.author).isNotEmpty
      ? _norm(cand.author)
      : _norm(cand.studio);
  if (ia.isNotEmpty && ca.isNotEmpty) {
    if (ia == ca || ia.contains(ca) || ca.contains(ia)) {
      total += 15;
    } else {
      total -= 40;
    }
  } else if (best >= 60) {
    total += 15;
  }

  // 3. Chapter / Page / Episode Counts
  final ic = item.totalCount ?? 0;
  final cc = cand.totalCount ?? cand.chapters ?? 0;
  if (ic > 0 && cc > 0) {
    final ratio = math.min(ic, cc) / math.max(ic, cc);
    if (ratio >= 0.8) {
      total += 10;
    } else if (ratio < 0.6) {
      total -= 30;
    }
  } else if (best >= 60) {
    total += 10;
  }

  // 4. Format / Country Mismatch (manhwa vs manga / KR vs JP)
  String? resolveFormat(String? mangaFmt, String? fmt, String? country) {
    final mf = (mangaFmt ?? '').toLowerCase().trim();
    if (mf == 'manhwa' || mf == 'manga' || mf == 'manhua') return mf;
    final f = (fmt ?? '').toLowerCase().trim();
    if (f == 'manhwa' || f == 'manga' || f == 'manhua') return f;
    final c = (country ?? '').toUpperCase().trim();
    if (c == 'KR') return 'manhwa';
    if (c == 'JP') return 'manga';
    if (c == 'CN') return 'manhua';
    return null;
  }

  final itemFmt = resolveFormat(item.mangaFormat, null, item.countryOfOrigin);
  final candFmt = resolveFormat(cand.mangaFormat, cand.format, cand.countryOfOrigin);
  var formatMismatch = (itemFmt == 'manhwa' && candFmt == 'manga') ||
      (itemFmt == 'manga' && candFmt == 'manhwa');

  if (!formatMismatch &&
      item.countryOfOrigin != null &&
      cand.countryOfOrigin != null) {
    final icountry = item.countryOfOrigin!.toUpperCase().trim();
    final ccountry = cand.countryOfOrigin!.toUpperCase().trim();
    if ((icountry == 'KR' && ccountry == 'JP') ||
        (icountry == 'JP' && ccountry == 'KR')) {
      formatMismatch = true;
    }
  }

  if (formatMismatch) {
    total -= 20;
  }

  return math.min(100, math.max(0, total));
}

/// Сортировка по приоритетам источников (сервер → дефолт), внутри
/// приоритета — по скорингу.
List<ExternalMedia> sortCandidates(List<ExternalMedia> list,
    PendingMatchItemDto item, Map<String, List<String>> sourcePriorities) {
  final priorities = ((sourcePriorities[item.type]?.isNotEmpty ?? false)
          ? sourcePriorities[item.type]!
          : defaultPriorities[item.type] ??
              const <String>[])
      .map((s) => s.toLowerCase())
      .toList();

  int getRank(String? source) {
    if (source == null) return 999;
    final idx = priorities.indexOf(source.toLowerCase());
    return idx >= 0 ? idx : 999;
  }

  final copy = [...list];
  copy.sort((a, b) {
    final rankA = getRank(a.externalSource);
    final rankB = getRank(b.externalSource);
    if (rankA != rankB) return rankA - rankB;
    return scoreCandidate(item, b) - scoreCandidate(item, a);
  });
  return copy;
}

/// Batch-import steps look like «[12/377] Title (авто: …)».
({int current, int total})? stepCounts(String? step) {
  final match = RegExp(r'\[(\d+)\s*\/\s*(\d+)\]').firstMatch(step ?? '');
  if (match == null) return null;
  return (
    current: int.parse(match.group(1)!),
    total: int.parse(match.group(2)!),
  );
}

bool isBatchImport(JobProgress job) {
  return job.status == JobStatus.running &&
      (job.title.toLowerCase().contains('импорт') ||
          stepCounts(job.currentStep) != null);
}

/// The queue walks one title every 2.5 s (the provider rate-limit pause), so
/// the rest is linear.
int? etaMinutes(JobProgress job) {
  final counts = stepCounts(job.currentStep);
  if (counts == null || counts.total <= counts.current) return null;
  return ((counts.total - counts.current) * 2.5 / 60).ceil();
}

String? statusLabelOf(JobProgress job, I18nDictionary t) {
  switch (job.status) {
    case JobStatus.queued:
      return t.tr('activity.queued');
    case JobStatus.completed:
      return t.tr('activity.completed');
    case JobStatus.failed:
      return t.tr('activity.failed');
    case JobStatus.cancelled:
      return t.tr('activity.cancelled');
    case JobStatus.running:
      return job.currentStep;
  }
}

bool isCancellableJob(JobProgress job) {
  return job.status == JobStatus.queued || job.status == JobStatus.running;
}

/// Tailwind-палитра бейджей источников (sourceBadges из Svelte).
({Color background, Color text, Color border})? sourceBadgeColors(String? source) {
  if (source == null) return null;
  const colors = {
    'anilist': (Color(0x3310B981), Color(0xFF6EE7B7), Color(0x4D10B981)),
    'shikimori': (Color(0x330EA5E9), Color(0xFF7DD3FC), Color(0x4D0EA5E9)),
    'mangadex': (Color(0x33F43F5E), Color(0xFFFDA4AF), Color(0x4DF43F5E)),
    'tmdb': (Color(0x33F59E0B), Color(0xFFFCD34D), Color(0x4DF59E0B)),
    'kinopoisk': (Color(0x33F97316), Color(0xFFFDBA74), Color(0x4DF97316)),
    'imdb': (Color(0x33EAB308), Color(0xFFFDE047), Color(0x4DEAB308)),
    'steam': (Color(0x333B82F6), Color(0xFF93C5FD), Color(0x4D3B82F6)),
    'rawg': (Color(0x33A855F7), Color(0xFFD8B4FE), Color(0x4DA855F7)),
  };
  final entry = colors[source.toLowerCase()];
  if (entry == null) return null;
  return (background: entry.$1, text: entry.$2, border: entry.$3);
}

/// Manual-search panel state per review card. `results` stays null until the
/// user searches.
class ManualSearchData {
  final bool open;
  String query;
  List<ExternalMedia>? results;
  bool loading;

  ManualSearchData({
    required this.open,
    required this.query,
    required this.results,
    required this.loading,
  });
}

/// Модалка фоновых задач (1-в-1 с BackgroundJobsModal.svelte; рендерится
/// из App при jobsClient.isModalOpen).
class BackgroundJobsModal extends ConsumerStatefulWidget {
  final VoidCallback? onMediaChanged;

  const BackgroundJobsModal({super.key, this.onMediaChanged});

  @override
  ConsumerState<BackgroundJobsModal> createState() =>
      _BackgroundJobsModalState();
}

class _BackgroundJobsModalState extends ConsumerState<BackgroundJobsModal> {
  final Map<String, ManualSearchData> _manualSearches = {};
  bool _dismissingAll = false;
  bool _resolvingAll = false;

  /// A candidate cover that failed once shows the 404-tan instead of a broken image icon.
  final Map<String, bool> _candidateImgErrors = {};
  ({ExternalMedia item, PendingMatchItemDto parentItem})? _previewCandidate;
  final Map<String, bool> _resolvingCandidates = {};

  /// Duplicate-conflict rows currently being merged into their existing titles.
  final Map<String, bool> _mergingDuplicates = {};

  /// Master-detail: the row picked in the left list, or null while the list settles.
  String? _selectedMatchId;
  final TextEditingController _pendingQueryController = TextEditingController();
  Map<String, List<String>> _sourcePriorities = {};
  final Set<String> _autoSearchScheduled = <String>{};

  /// bind:value-аналог: один контроллер на строку ревью (оба поисковых
  /// поля — шапка и тело — шарят один search.query).
  final Map<String, TextEditingController> _queryControllers = {};

  TextEditingController _queryControllerFor(String id, String initial) {
    return _queryControllers.putIfAbsent(
        id, () => TextEditingController(text: initial));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(apiClientProvider)
          .getSourcePriority()
          .then((p) {
            if (mounted && p.isNotEmpty) {
              setState(() => _sourcePriorities = p);
            }
          })
          .catchError((Object _) {});
    });
  }

  @override
  void dispose() {
    _pendingQueryController.dispose();
    for (final controller in _queryControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TsundokuApi get _api => ref.read(apiClientProvider);

  I18nDictionary get _t => ref.read(tProvider);

  Locale get _locale => ref.read(i18nProvider);

  void _errorToast(Object error) {
    showToast(
      ref,
      ToastOptions(
        title: _t.tr('toast.actionFailed'),
        description: errorMessage(error, _locale),
        type: ToastType.error,
      ),
    );
  }

  int get _pendingCount => ref.read(pendingMatchesCountProvider);

  List<PendingMatchItemDto> get _visiblePending {
    final jobs = ref.read(jobsClientProvider);
    final query = _pendingQueryController.text.trim().toLowerCase();
    if (query.isEmpty) return jobs.pendingMatches;
    return jobs.pendingMatches
        .where((item) => [item.title, item.romajiTitle, item.originalTitle]
            .any((title) => title?.toLowerCase().contains(query) ?? false))
        .toList();
  }

  PendingMatchItemDto? get _selectedItem {
    final visible = _visiblePending;
    return visible.where((item) => item.id == _selectedMatchId).firstOrNull ??
        visible.firstOrNull;
  }

  int get _selectedIndex {
    final item = _selectedItem;
    if (item == null) return -1;
    return _visiblePending.indexWhere((it) => it.id == item.id);
  }

  String _preferredSearchQuery(PendingMatchItemDto item) {
    return (item.romajiTitle?.isNotEmpty ?? false)
        ? item.romajiTitle!
        : item.title;
  }

  ManualSearchData _emptySearch(PendingMatchItemDto item) {
    return ManualSearchData(
      open: true,
      query: _preferredSearchQuery(item),
      results: null,
      loading: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final jobs = ref.watch(jobsClientProvider);
    final pendingCount = ref.watch(pendingMatchesCountProvider);
    final activeCount = ref.watch(activeJobsCountProvider);

    // The review tab only exists while there is something to review; a list
    // emptied elsewhere (job finished, all resolved) must not strand the
    // modal on an empty tab.
    if (jobs.modalTab == JobsModalTab.review && pendingCount == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(pendingMatchesCountProvider) == 0 &&
            ref.read(jobsClientProvider).modalTab == JobsModalTab.review) {
          ref.read(jobsClientProvider.notifier).setModalTab(JobsModalTab.jobs);
        }
      });
    }

    final visible = _visiblePending;
    final selectedItem = _selectedItem;
    final selectedIndex = _selectedIndex;

    // Every selected row gets its own search draft; a row with no candidates
    // searches itself once. Duplicate-conflict rows have no candidate list at
    // all — their verdict is merge or keep.
    if (selectedItem != null && !_manualSearches.containsKey(selectedItem.id)) {
      final item = selectedItem;
      if (_autoSearchScheduled.add(item.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _manualSearches[item.id] = _emptySearch(item);
            _queryControllerFor(
                item.id, _manualSearches[item.id]!.query);
          });
          final duplicate = item.duplicate;
          if (duplicate == null &&
              (item.candidates.isEmpty)) {
            unawaited(_runSearch(item));
          }
        });
      }
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _handleHotkey,
      child: Stack(
        children: [
          TsundokuModal(
            isOpen: true,
            onClose: () => ref.read(jobsClientProvider.notifier).closeModal(),
            size: ModalSize.jobs,
            contentPadding: EdgeInsets.zero,
            child: Column(
              children: [
                _buildHeader(t, th, jobs, pendingCount, activeCount),
                Expanded(
                  child: jobs.modalTab == JobsModalTab.jobs
                      ? _buildJobsTab(t, th, jobs, pendingCount)
                      : _buildReviewTab(t, th, jobs, visible, selectedItem,
                          selectedIndex, pendingCount),
                ),
              ],
            ),
          ),
          // Превью кандидата ({#if previewCandidate}) поверх jobs-модалки;
          // hotkeys не работают, пока превью открыто (гейт в _handleHotkey).
          if (_previewCandidate != null)
            ExternalDetailModal(
              item: _previewCandidate!.item,
              type: candidateType(
                  _previewCandidate!.item, _previewCandidate!.parentItem),
              onClose: () => setState(() => _previewCandidate = null),
              actions: _previewActions(_previewCandidate!),
            ),
        ],
      ),
    );
  }

  // ─── Header + табы ────────────────────────────────────────────────────────

  Widget _buildHeader(I18nDictionary t, TsundokuTheme th, JobsState jobs,
      int pendingCount, int activeCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Иконка: bg-accent-bright/20, #8f7fff.
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: th.accentBright.withAlpha(51), // /20
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.activity,
                    size: 19, color: Color(0xFF8F7FFF)),
              ),
              const SizedBox(width: 12),
              Text(
                t.tr('activity.label'),
                style: TextStyle(
                  fontSize: 16, // text-base
                  fontWeight: FontWeight.w700, // font-bold
                  color: th.textPrimary, // text-ink
                ),
              ),
              const Spacer(),
              _HeaderCloseButton(
                semanticLabel: t.tr('common.close'),
                onClose: () {
                  ref.read(jobsClientProvider.notifier).closeModal();
                },
              ),
            ],
          ),
          const SizedBox(height: 12), // gap-3
          // role=tablist: bg-black/25 rounded-lg p-1.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(64), // bg-black/25
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _JobsTabButton(
                  label: t.tr('backgroundJobs.tabQueue'),
                  count: activeCount > 0 ? activeCount : null,
                  active: jobs.modalTab == JobsModalTab.jobs,
                  activeBackground: th.accentBright,
                  activeForeground: Colors.white,
                  th: th,
                  onTap: () => ref
                      .read(jobsClientProvider.notifier)
                      .setModalTab(JobsModalTab.jobs),
                ),
                if (pendingCount > 0)
                  _JobsTabButton(
                    label: t.tr('backgroundJobs.tabReview'),
                    count: pendingCount,
                    active: jobs.modalTab == JobsModalTab.review,
                    activeBackground: const Color(0xE6F59E0B), // bg-amber-500/90
                    activeForeground: Colors.black,
                    th: th,
                    onTap: () => ref
                        .read(jobsClientProvider.notifier)
                        .setModalTab(JobsModalTab.review),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Таб «Очередь» ────────────────────────────────────────────────────────

  Widget _buildJobsTab(I18nDictionary t, TsundokuTheme th, JobsState jobs,
      int pendingCount) {
    return TsundokuSmoothScrollView(
      key: const ValueKey('jobs-queue-scroll'),
      padding: const EdgeInsets.all(20), // p-5
      child: Column(
        children: [
          if (pendingCount > 0) ...[
            // Banner: border-amber-500/40 bg-amber-500/10.
            Container(
              margin: const EdgeInsets.only(bottom: 16), // mb-4
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12), // rounded-xl
                border: Border.all(
                    color: const Color(0x66F59E0B)), // border-amber-500/40
                color: const Color(0x1AF59E0B), // bg-amber-500/10
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.triangleAlert,
                      size: 18, color: Color(0xFFFBBF24)), // text-amber-400
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.tf('backgroundJobs.banner', [pendingCount]),
                      style: const TextStyle(
                        fontSize: 14, // text-sm
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFFDE68A), // text-amber-200
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => ref
                        .read(jobsClientProvider.notifier)
                        .setModalTab(JobsModalTab.review),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6), // px-3.5 py-1.5
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xE6F59E0B), // bg-amber-500/90
                      ),
                      child: Text(
                        t.tr('backgroundJobs.gotoReview'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700, // font-bold
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (jobs.jobs.isEmpty)
            _emptyState(t, th)
          else
            Column(
              children: [
                for (final job in jobs.jobs)
                  _JobCard(
                    job: job,
                    th: th,
                    t: t,
                    onCancel: () => unawaited(ref
                        .read(jobsClientProvider.notifier)
                        .cancel(job.jobId)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _emptyState(I18nDictionary t, TsundokuTheme th,
      {bool amber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: amber
                  ? const Color(0x1AF59E0B) // bg-amber-500/10
                  : Colors.white.withAlpha(10), // bg-white/[0.04]
            ),
            child: Icon(
              amber ? LucideIcons.triangleAlert : LucideIcons.activity,
              size: 24,
              color: amber ? const Color(0xFFFBBF24) : th.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.tr('activity.empty'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600, // font-semibold
              color: th.textPrimary, // text-ink
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
            child: Text(
              t.tr('activity.emptyHint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: th.textMuted, // text-muted
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Таб «Review» ─────────────────────────────────────────────────────────

  Widget _buildReviewTab(I18nDictionary t, TsundokuTheme th, JobsState jobs,
      List<PendingMatchItemDto> visible,
      PendingMatchItemDto? selectedItem,
      int selectedIndex,
      int pendingCount) {
    if (jobs.pendingMatches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20), // p-4 sm:p-5
        child: _emptyState(t, th, amber: true),
      );
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= 768; // md:

    return Padding(
      padding: EdgeInsets.all(isDesktop ? 20 : 16), // p-4 sm:p-5
      child: Column(
        children: [
          // Intro-панель: reviewIntro + resolveAll + keepAll.
          Container(
            margin: const EdgeInsets.only(bottom: 16), // mb-4
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(21)), // /[0.08]
              color: Colors.white.withAlpha(8), // bg-white/[0.03]
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                  child: Text(
                    t.tr('backgroundJobs.reviewIntro'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.625, // leading-relaxed
                      color: th.textMuted,
                    ),
                  ),
                ),
                _ReviewActionButton(
                  th: th,
                  label: '⚡ ${t.tr('backgroundJobs.resolveAllPriority')}',
                  tooltip: 'Автоматически привязать кандидатов с надежным совпадением (балл ≥ 50)',
                  disabled: _resolvingAll || pendingCount == 0,
                  loading: _resolvingAll,
                  onTap: () => unawaited(_resolveAllByPriority()),
                ),
                _ReviewSecondaryButton(
                  th: th,
                  label: t.tr('backgroundJobs.keepAll'),
                  tooltip: 'Оставить все как есть (без привязки)',
                  disabled: _dismissingAll || pendingCount == 0,
                  loading: _dismissingAll,
                  onTap: () => unawaited(_keepAll()),
                ),
              ],
            ),
          ),

          Expanded(
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 320, // md:w-80
                        child: _masterList(t, th, visible, selectedItem,
                            selectedIndex),
                      ),
                      const SizedBox(width: 16), // gap-4
                      Expanded(
                        child: _detailPane(t, th, selectedItem),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 256), // max-h-64
                        child: _masterList(t, th, visible, selectedItem,
                            selectedIndex),
                      ),
                      const SizedBox(height: 16), // gap-4
                      Expanded(child: _detailPane(t, th, selectedItem)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Master list: every unresolved title, filterable and keyboard-driven.
  Widget _masterList(I18nDictionary t, TsundokuTheme th,
      List<PendingMatchItemDto> visible,
      PendingMatchItemDto? selectedItem,
      int selectedIndex) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        border: Border.all(color: Colors.white.withAlpha(21)),
        color: Colors.white.withAlpha(8),
      ),
      child: Column(
        children: [
          // Поиск + счётчик.
          Container(
            padding: const EdgeInsets.all(12), // p-3
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
            ),
            child: Column(
              children: [
                Container(
                  // relative: иконка слева.
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32), // pl-8 pr-3
                  decoration: BoxDecoration(
                    color: th.bgSurface, // bg-field
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withAlpha(26)), // white/10
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.search,
                          size: 14, color: th.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _pendingQueryController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: t.tr('backgroundJobs.listSearchPlaceholder'),
                            hintStyle:
                                TextStyle(color: th.textMuted, fontSize: 12),
                            border: InputBorder.none,
                            filled: false,
                          ),
                          style: TextStyle(
                              fontSize: 12, color: th.textPrimary), // text-xs
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8), // space-y-2
                Row(
                  children: [
                    Text(
                      '[ ${selectedIndex >= 0 ? selectedIndex + 1 : 0} / ${visible.length} ]',
                      style: TextStyle(
                        fontSize: 11, // text-[11px]
                        fontWeight: FontWeight.w500,
                        color: th.textMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      t.tr('backgroundJobs.pendingShort'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: th.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Список строк.
          Expanded(
            child: visible.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      t.tr('backgroundJobs.noListResults'),
                      style: TextStyle(fontSize: 12, color: th.textMuted),
                    ),
                  )
                : TsundokuSmoothScrollView(
                    key: const ValueKey('jobs-pending-list'),
                    padding: const EdgeInsets.all(8), // p-2
                    child: Column(
                      children: [
                        for (final item in visible)
                          _PendingRow(
                            item: item,
                            active: item.id == selectedItem?.id,
                            candidateCount: _candidateCount(item),
                            th: th,
                            suggestionsTitle: t.tr('backgroundJobs.suggestions'),
                            onTap: () =>
                                setState(() => _selectedMatchId = item.id),
                          ),
                      ],
                    ),
                  ),
          ),
          // Футер: подсказка + Skip.
          Container(
            padding: const EdgeInsets.all(8), // p-2
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                  child: Text(
                    t.tr('backgroundJobs.hotkeysHint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10, // text-[10px]
                      height: 1.625,
                      color: th.textMuted,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _skipCurrent,
                  child: Container(
                    height: 36, // px-3 py-2 ≈ h-9
                    decoration: BoxDecoration(
                      color: th.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withAlpha(26)), // white/10
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.chevronRight,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          t.tr('backgroundJobs.skipNext'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600, // font-semibold
                            color: Color(0xFFCBD5E1), // text-slate-300
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Detail: the selected title and its candidate grid.
  Widget _detailPane(
      I18nDictionary t, TsundokuTheme th, PendingMatchItemDto? selectedItem) {
    if (selectedItem == null) return const SizedBox.shrink();
    final item = selectedItem;
    final search =
        _manualSearches[item.id] ?? _emptySearch(item);
    final candidates = _candidatesFor(item);
    final duplicate = item.duplicate;
    final isWide = MediaQuery.sizeOf(context).width >= 1280; // xl:
    final progressText =
        '${item.currentProgress}${item.totalCount != null ? ' / ${item.totalCount}' : ''}';
    final progressUnit =
        (item.isAnime ?? false) || item.type == 'tvshow' || item.type == 'anime'
            ? ' эп.'
            : ' гл.';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        border: Border.all(color: Colors.white.withAlpha(21)),
        color: Colors.white.withAlpha(5), // bg-white/[0.02]
      ),
      child: Column(
        children: [
          // Sticky-шапка: identity + quick actions + search (не для duplicates).
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF151A26), // bg-[#151a26]
              border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _typePill(t, th, item),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: item.title,
                          style: TextStyle(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w700, // font-bold
                            color: th.textPrimary,
                          ),
                          children: [
                            if (item.originalTitle != null ||
                                (item.romajiTitle != null &&
                                    item.romajiTitle != item.title)) ...[
                              const WidgetSpan(child: SizedBox(width: 4)),
                              TextSpan(
                                text:
                                    '(${item.originalTitle ?? item.romajiTitle})',
                                style: TextStyle(
                                  fontSize: 12, // text-xs
                                  fontWeight: FontWeight.w400, // font-normal
                                  color: th.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.currentProgress != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6), // rounded-md
                          color: Colors.white.withAlpha(15), // bg-white/[0.06]
                        ),
                        child: Text(
                          '$progressText$progressUnit',
                          style: TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w500,
                            color: th.textMuted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    _IconActionButton(
                      icon: LucideIcons.x,
                      size: 15,
                      tooltip: 'Оставить как есть (без привязки)',
                      semanticLabel: t.tr('backgroundJobs.keepAsIs'),
                      th: th,
                      onTap: () => unawaited(_keep(item)),
                    ),
                    const SizedBox(width: 6), // gap-1.5
                    _DeleteActionButton(
                      semanticLabel: t.tr('backgroundJobs.delete'),
                      onTap: () => _deleteItem(item.id),
                    ),
                  ],
                ),
                if (duplicate == null) ...[
                  const SizedBox(height: 8), // mt-2
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(left: 12),
                          decoration: BoxDecoration(
                            color: th.bgSurface, // bg-field
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    Colors.white.withAlpha(26)), // white/10
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller:
                                      _queryControllerFor(item.id, search.query),
                                  onSubmitted: (_) =>
                                      unawaited(_runSearch(item)),
                                  onChanged: (value) {
                                    search.query = value;
                                    setState(() {}); // активность RU/EN-тогглов
                                  },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText:
                                        t.tr('backgroundJobs.searchPlaceholder'),
                                    hintStyle: TextStyle(
                                        color: Colors.white.withAlpha(115),
                                        fontSize: 14), // placeholder:text-zinc-500
                                    border: InputBorder.none,
                                  ),
                                  style: TextStyle(
                                      fontSize: 14, color: th.textPrimary),
                                ),
                              ),
                              // RU/EN языковые переключатели в поле.
                              _LanguageToggle(
                                label: 'RU',
                                active:
                                    search.query == extractRussian(item.title),
                                th: th,
                                onTap: () {
                                  search.query = extractRussian(item.title);
                                  _queryControllerFor(item.id, search.query)
                                      .text = search.query;
                                  setState(() {});
                                  unawaited(_runSearch(item));
                                },
                              ),
                              _LanguageToggle(
                                label: 'EN',
                                active:
                                    search.query == _preferredSearchQuery(item),
                                th: th,
                                onTap: () {
                                  search.query = _preferredSearchQuery(item);
                                  _queryControllerFor(item.id, search.query)
                                      .text = search.query;
                                  setState(() {});
                                  unawaited(_runSearch(item));
                                },
                              ),
                              const SizedBox(width: 8), // pr-2 gap-1
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8), // gap-2
                      _SearchRunButton(
                        th: th,
                        loading: search.loading,
                        semanticLabel: t.tr('backgroundJobs.findManually'),
                        onTap: () => unawaited(_runSearch(item)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Контент: duplicate-вердикт или кандидаты.
          Expanded(
            child: TsundokuSmoothScrollView(
              key: ValueKey('jobs-pending-detail-${item.id}'),
              padding: const EdgeInsets.all(16), // p-4
              child: duplicate != null
                  ? _duplicateCard(t, th, item, duplicate)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12), // px-3
                                decoration: BoxDecoration(
                                  color: th.bgSurface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.white
                                          .withAlpha(26)), // white/10
                                ),
                                child: TextField(
                                  controller:
                                      _queryControllerFor(item.id, search.query),
                                  onSubmitted: (_) =>
                                      unawaited(_runSearch(item)),
                                  onChanged: (value) {
                                    search.query = value;
                                    setState(() {});
                                  },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: t
                                        .tr('backgroundJobs.searchPlaceholder'),
                                    hintStyle: TextStyle(
                                        color: th.textMuted, fontSize: 14),
                                    border: InputBorder.none,
                                  ),
                                  style: TextStyle(
                                      fontSize: 14, color: th.textPrimary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SearchRunButton(
                              th: th,
                              loading: search.loading,
                              semanticLabel:
                                  t.tr('backgroundJobs.findManually'),
                              onTap: () => unawaited(_runSearch(item)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12), // space-y-3
                        if (candidates.isEmpty)
                          Text(
                            t.tr('backgroundJobs.noCandidates'),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.625, // leading-relaxed
                              color: th.textMuted,
                            ),
                          )
                        else
                          // grid xl:grid-cols-2 gap-4: две колонки при
                          // окне ≥1280 (xl), ширина от фактической панели.
                          LayoutBuilder(builder: (context, constraints) {
                            final columns = isWide &&
                                    constraints.maxWidth.isFinite &&
                                    constraints.maxWidth > 400
                                ? 2
                                : 1;
                            final gap = 16.0; // gap-4
                            final cardWidth = columns == 2
                                ? (constraints.maxWidth - gap) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (var index = 0;
                                    index < candidates.length;
                                    index++)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _candidateCard(
                                        t, th, item, candidates[index], index),
                                  ),
                              ],
                            );
                          }),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typePill(I18nDictionary t, TsundokuTheme th, PendingMatchItemDto item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6), // rounded-md
        color: th.accentBright.withAlpha(51), // bg-accent-bright/20
      ),
      child: Text(
        '${item.type}${(item.isAnime ?? false) ? ' · anime' : ''}',
        style: const TextStyle(
          fontSize: 10, // text-[10px]
          fontWeight: FontWeight.w600, // font-semibold
          color: Color(0xFF8F7FFF),
        ),
      ),
    );
  }

  Widget _duplicateCard(I18nDictionary t, TsundokuTheme th,
      PendingMatchItemDto item, DuplicateConflictDto duplicate) {
    final merging = _mergingDuplicates[item.id] ?? false;
    return Container(
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        border: Border.all(
            color: const Color(0x4DF59E0B)), // border-amber-500/30
        color: const Color(0x12F59E0B), // bg-amber-500/[0.07]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.tf('backgroundJobs.duplicateIntro', [
              duplicate.incomingTitle ?? item.title,
              duplicate.existingTitle,
            ]),
            style: const TextStyle(
              fontSize: 14, // text-sm
              height: 1.625, // leading-relaxed
              color: Color(0xFFFDE68A), // text-amber-200
            ),
          ),
          const SizedBox(height: 16), // mt-4
          Wrap(
            spacing: 8, // gap-2
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: merging ? null : () => unawaited(_mergeDuplicate(item)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8), // px-4 py-2
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: th.accent, // bg-accent
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (merging)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(LucideIcons.check,
                            size: 14, color: Colors.white), // stroke-width 2.5 (#26)
                      const SizedBox(width: 6), // gap-1.5
                      Text(
                        t.tr('backgroundJobs.duplicateMerge'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700, // font-bold
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => unawaited(_keepSeparate(item)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: th.bgSurface, // bg-field
                    border: Border.all(
                        color: Colors.white.withAlpha(26)), // white/10
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.x,
                          size: 14, color: Color(0xFFCBD5E1)),
                      const SizedBox(width: 6),
                      Text(
                        t.tr('backgroundJobs.duplicateKeep'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500, // font-medium
                          color: Color(0xFFCBD5E1), // text-slate-300
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _candidateCard(I18nDictionary t, TsundokuTheme th,
      PendingMatchItemDto item, ExternalMedia candidate, int index) {
    final key = '${candidate.externalSource}${candidate.externalId}';
    final candKey =
        '${item.id}:${candidate.externalSource}:${candidate.externalId}';
    final isResolving = _resolvingCandidates[candKey] ?? false;
    final match = scoreCandidate(item, candidate);
    final badgeColors = sourceBadgeColors(candidate.externalSource);
    final countValue = candidate.totalCount ?? candidate.chapters;
    final countSuffix =
        (candidate.type == 'anime' || (item.isAnime ?? false)) ? 'эп.' : 'гл.';

    return Container(
      padding: const EdgeInsets.all(16), // sm:p-4
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        border: Border.all(color: Colors.white.withAlpha(21)),
        color: Colors.white.withAlpha(8), // bg-white/[0.03]
        boxShadow: const [
          // shadow-sm
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Постер: aspect 2/3, w-24 sm:w-28; hover — Eye-оверлей.
          _CandidatePoster(
            candidate: candidate,
            imgError: _candidateImgErrors[key] ?? false,
            th: th,
            viewLabel: 'Нажмите для подробного просмотра',
            onPreview: () => setState(() => _previewCandidate =
                (item: candidate, parentItem: item)),
            onImgError: () => setState(() => _candidateImgErrors[key] = true),
          ),
          const SizedBox(width: 16), // gap-4
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (index < 4) ...[
                      Container(
                        width: 20, // h-5 w-5
                        height: 20,
                        margin: const EdgeInsets.only(top: 2), // mt-0.5
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(6), // rounded-md
                          color: th.accentBright, // bg-accent-bright
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 10, // text-[10px]
                              fontWeight: FontWeight.w700, // font-bold
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6), // gap-1.5
                    ],
                    Expanded(
                      child: Text(
                        candidate.title,
                        maxLines: 2, // line-clamp-2
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14, // text-sm
                          height: 1.375, // leading-snug
                          fontWeight: FontWeight.w700, // font-bold
                          letterSpacing: -0.25, // tracking-tight
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (candidate.originalTitle != null ||
                    candidate.romajiTitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2), // mt-0.5
                    child: Text(
                      candidate.originalTitle ?? candidate.romajiTitle ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12, // text-xs
                        color: th.textMuted,
                      ),
                    ),
                  ),
                const SizedBox(height: 8), // mt-2
                Wrap(
                  spacing: 6, // gap-1.5
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (candidate.externalSource?.isNotEmpty ?? false)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2), // px-2 py-0.5
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: badgeColors?.background ??
                              Colors.white.withAlpha(18), // bg-white/[0.07]
                          border: badgeColors != null
                              ? Border.all(color: badgeColors.border)
                              : null,
                        ),
                        child: Text(
                          candidate.externalSource!,
                          style: TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w700, // font-bold
                            letterSpacing: 0.5, // tracking-wide
                            color: badgeColors?.text ??
                                const Color(0xFFCBD5E1), // text-slate-300
                          ),
                        ),
                      ),
                    if (candidate.releaseYear != null)
                      _metaPill(
                        th,
                        '${candidate.releaseYear}',
                        tabular: true,
                      ),
                    if (countValue != null)
                      _metaPill(
                        th,
                        '$countValue$countSuffix',
                        tabular: true,
                      ),
                    if ((candidate.author?.isNotEmpty ?? false) ||
                        (candidate.studio?.isNotEmpty ?? false))
                      _metaPill(
                        th,
                        candidate.author ?? candidate.studio ?? '',
                        maxWidth: 140, // max-w-[140px] truncate
                      ),
                    // Match score: border-emerald-500/30 bg-emerald-500/15
                    // text-emerald-300.
                    Tooltip(
                      message: t.tf('backgroundJobs.matchScore', [match]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0x4D10B981)), // emerald-500/30
                          color: const Color(0x2610B981), // emerald-500/15
                        ),
                        child: Text(
                          t.tf('backgroundJobs.matchScore', [match]),
                          style: const TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w700, // font-bold
                            color: Color(0xFF6EE7B7), // text-emerald-300
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12), // pt-3
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: isResolving
                              ? null
                              : () => _resolve(item, candidate),
                          child: Container(
                            height: 34, // px-3 py-2
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: th.accent, // bg-accent
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isResolving)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                else
                                  const Icon(LucideIcons.check,
                                      size: 14, color: Colors.white),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    t.tr('backgroundJobs.choose'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8), // gap-2
                      Tooltip(
                        message: 'Подробнее',
                        child: GestureDetector(
                          onTap: () => setState(() => _previewCandidate =
                              (item: candidate, parentItem: item)),
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12), // px-3
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: th.bgSurface,
                              border: Border.all(
                                  color:
                                      Colors.white.withAlpha(26)), // white/10
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.eye,
                                    size: 14, color: Color(0xFFCBD5E1)),
                                const SizedBox(width: 6),
                                Text(
                                  t.tr('common.details'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ],
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
        ],
      ),
    );
  }

  Widget _metaPill(TsundokuTheme th, String text,
      {bool tabular = false, double? maxWidth}) {
    final style = TextStyle(
      fontSize: 10, // text-[10px]
      fontWeight: FontWeight.w500, // font-medium
      color: th.textMuted, // text-muted
      fontFeatures: tabular ? [FontFeature.tabularFigures()] : null,
    );
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // px-2 py-0.5
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withAlpha(18), // bg-white/[0.07]
      ),
      constraints:
          maxWidth != null ? BoxConstraints(maxWidth: maxWidth) : null,
      child: maxWidth != null
          ? Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: style)
          : Text(text, style: style),
    );
  }

  /// Actions-слот превью: «Выбрать» закрывает превью и резолвит кандидата.
  Widget _previewActions(
      ({ExternalMedia item, PendingMatchItemDto parentItem}) preview) {
    final t = ref.watch(tProvider);
    return _PreviewChooseButton(
      label: t.tr('backgroundJobs.choose'),
      onTap: () {
        setState(() => _previewCandidate = null);
        _resolve(preview.parentItem, preview.item);
      },
    );
  }

  // ─── Логика поиска/действий (1-в-1 с Svelte-функциями) ────────────────────

  List<ExternalMedia> _candidatesFor(PendingMatchItemDto item) {
    final search = _manualSearches[item.id];
    final raw = search?.results ?? item.candidates;
    return sortCandidates(raw, item, _sourcePriorities);
  }

  int _candidateCount(PendingMatchItemDto item) {
    return (_manualSearches[item.id]?.results ?? item.candidates).length;
  }

  /// Auto-advance: keep the cursor on the row after the removed one, falling
  /// back to the previous row at the end of the list.
  void _advanceSelection(String itemId) {
    final list = _visiblePending;
    final index = list.indexWhere((item) => item.id == itemId);
    final next =
        (index + 1 < list.length ? list[index + 1] : null) ??
            (index - 1 >= 0 ? list[index - 1] : null);
    _selectedMatchId = (next != null && next.id != itemId) ? next.id : null;
  }

  void _skipCurrent() {
    final visible = _visiblePending;
    if (visible.isEmpty) return;
    final index = visible.indexWhere((item) => item.id == _selectedItem?.id);
    _selectedMatchId =
        visible[(index + 1) % visible.length].id;
    setState(() {});
  }

  /// Svelte мутирует details на месте (type/externalSource/externalId из
  /// parsed URL, isDirectUrl = true); Dart — read-only DTO, пересобираем.
  ExternalMedia _pinDirect(ExternalMedia d, ParsedMediaUrl p) {
    return ExternalMedia(
      externalId: d.externalId.isNotEmpty ? d.externalId : p.id,
      externalSource: (d.externalSource?.isNotEmpty ?? false)
          ? d.externalSource
          : p.source,
      title: d.title,
      originalTitle: d.originalTitle,
      romajiTitle: d.romajiTitle,
      coverUrl: d.coverUrl,
      description: d.description,
      trailerVideoId: d.trailerVideoId,
      releaseYear: d.releaseYear,
      releaseDate: d.releaseDate,
      endDate: d.endDate,
      releaseStatus: d.releaseStatus,
      format: d.format,
      runtimeMinutes: d.runtimeMinutes,
      type: d.type.isNotEmpty ? d.type : p.type,
      author: d.author,
      studio: d.studio,
      isbn: d.isbn,
      covers: d.covers,
      totalCount: d.totalCount,
      chapters: d.chapters,
      volumes: d.volumes,
      mangaFormat: d.mangaFormat,
      countryOfOrigin: d.countryOfOrigin,
      platform: d.platform,
      rating: d.rating,
      ratingVotes: d.ratingVotes,
      ratings: d.ratings,
      episodes: d.episodes,
      genres: d.genres,
      tags: d.tags,
      synonyms: d.synonyms,
      isDirectUrl: true,
    );
  }

  /// Поиск: direct-URL → точный тайтл (100%), http-ссылка → ошибка домена,
  /// иначе — топ-3 приоритетных источников с per-source подменой языка.
  Future<void> _runSearch(PendingMatchItemDto item) async {
    if (item.duplicate != null) return;
    final search = _manualSearches[item.id];
    if (search == null || search.query.trim().isEmpty || search.loading) return;

    search.loading = true;
    setState(() {});
    final t = _t;
    try {
      // A pasted direct link skips the text search entirely.
      final parsedUrl = parseMediaUrl(search.query.trim());
      if (parsedUrl != null) {
        final details = await _api.getExternalDetails(
          parsedUrl.type,
          parsedUrl.id,
          '',
          source: parsedUrl.source,
        );
        if (details != null) {
          search.results = [_pinDirect(details, parsedUrl)];
        } else {
          search.results = [];
          showToast(
            ref,
            ToastOptions(
              title: t.tr('searchModal.directLinkError'),
              description: t.tr('toast.descRetry'),
              type: ToastType.error,
            ),
          );
        }
        return;
      }

      final trimmedQuery = search.query.trim();
      if (trimmedQuery.startsWith('http://') ||
          trimmedQuery.startsWith('https://')) {
        search.results = [];
        showToast(
          ref,
          ToastOptions(
            title: t.tr('searchModal.unsupportedLinkError'),
            description: t.tr('toast.descValidation'),
            type: ToastType.error,
          ),
        );
        return;
      }

      final priorities = (_sourcePriorities[item.type]?.isNotEmpty ?? false)
          ? _sourcePriorities[item.type]!
          : defaultPriorities[item.type] ?? const <String>[];

      final activeSources = priorities.take(3).toList();
      final latin = extractLatin(search.query);
      final russian = extractRussian(search.query);

      if (activeSources.isNotEmpty) {
        final perSourceResults = await Future.wait(activeSources.map((source) {
          var q = search.query;
          if ((source == 'anilist' || source == 'mangadex') &&
              (latin != null || (item.romajiTitle?.isNotEmpty ?? false))) {
            q = latin ?? item.romajiTitle ?? search.query;
          } else if ((source == 'shikimori' || source == 'kinopoisk') &&
              (russian.isNotEmpty || item.title.isNotEmpty)) {
            q = russian.isNotEmpty ? russian : item.title;
          }
          return _api
              .searchExternal(item.type, q, source: source)
              .catchError((Object _) => <ExternalMedia>[]);
        }));
        final collected = <ExternalMedia>[];
        final seen = <String>{};
        for (final list in perSourceResults) {
          for (final cand in list.take(4)) {
            final key = '${cand.externalSource}:${cand.externalId}';
            if (!seen.contains(key)) {
              seen.add(key);
              collected.add(cand);
            }
          }
        }
        search.results = sortCandidates(collected, item, _sourcePriorities);
      } else {
        final results = await _api.searchExternal(item.type, search.query);
        search.results =
            sortCandidates(results.take(4).toList(), item, _sourcePriorities);
      }
    } catch (error) {
      showToast(
        ref,
        ToastOptions(
          title: t.tr('toast.actionFailed'),
          description: errorMessage(error, _locale),
          type: ToastType.error,
        ),
      );
    } finally {
      search.loading = false;
      if (mounted) setState(() {});
    }
  }

  void _resolve(PendingMatchItemDto item, ExternalMedia candidate) {
    final candKey =
        '${item.id}:${candidate.externalSource}:${candidate.externalId}';
    _resolvingCandidates[candKey] = true;
    _advanceSelection(item.id);

    final t = _t;
    showToast(
      ref,
      ToastOptions(
        title: t.tr('backgroundJobs.resolvedAsyncToast'),
        description: t.tr('toast.descResolved'),
      ),
    );
    unawaited(() async {
      try {
        await _api.resolvePendingMatch(
          item.id,
          externalId: candidate.externalId,
          source: candidate.externalSource ?? '',
          type: candidate.type.isNotEmpty ? candidate.type : item.type,
          title: candidate.title,
        );
      } catch (error) {
        if (!mounted) return;
        _errorToast(error);
      } finally {
        _resolvingCandidates.remove(candKey);
        if (mounted) {
          setState(() {});
          widget.onMediaChanged?.call();
        }
      }
    }());

    // The server already queued the highest-priority enrichment, so the row
    // can leave the list now.
    ref.read(jobsClientProvider.notifier).dropPendingMatch(item.id);
    setState(() {});
  }

  Future<void> _keep(PendingMatchItemDto item) async {
    try {
      await _api.dismissPendingMatch(item.id);
      _advanceSelection(item.id);
      ref.read(jobsClientProvider.notifier).dropPendingMatch(item.id);
      if (mounted) {
        setState(() {});
        widget.onMediaChanged?.call();
      }
    } catch (error) {
      if (!mounted) return;
      _errorToast(error);
    }
  }

  /// Duplicate verdict "leave as separate": the phantom row goes back to a
  /// normal library card.
  Future<void> _keepSeparate(PendingMatchItemDto item) async {
    await _keep(item);
    if (!mounted) return;
    showToast(
      ref,
      ToastOptions(
        title: _t.tr('backgroundJobs.duplicateKeepToast'),
        description: _t.tr('toast.descResolved'),
      ),
    );
  }

  /// Duplicate verdict "merge": the row's sources and ratings join the
  /// existing title and the duplicate is deleted.
  Future<void> _mergeDuplicate(PendingMatchItemDto item) async {
    final duplicate = item.duplicate;
    if (duplicate == null || (_mergingDuplicates[item.id] ?? false)) return;
    _mergingDuplicates[item.id] = true;
    _advanceSelection(item.id);
    setState(() {});
    try {
      await _api.mergeDuplicateSources(duplicate.existingMediaId, item.id);
      ref.read(jobsClientProvider.notifier).dropPendingMatch(item.id);
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: _t.tr('backgroundJobs.duplicateMergeToast'),
          description: _t.tr('toast.descResolved'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _errorToast(error);
    } finally {
      _mergingDuplicates.remove(item.id);
      if (mounted) {
        setState(() {});
        widget.onMediaChanged?.call();
      }
    }
  }

  Future<void> _keepAll() async {
    if (_dismissingAll) return;
    _dismissingAll = true;
    setState(() {});
    final count = _pendingCount;
    final t = _t;
    try {
      await _api.dismissAllPendingMatches();
      ref.read(jobsClientProvider.notifier).clearPendingMatches();
      if (count > 0 && mounted) {
        showToast(
          ref,
          ToastOptions(
            title: t.tf('backgroundJobs.keptToast', [count]),
            description: t.tr('toast.descResolved'),
          ),
        );
      }
      widget.onMediaChanged?.call();
    } catch (error) {
      if (!mounted) return;
      _errorToast(error);
    } finally {
      _dismissingAll = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _resolveAllByPriority() async {
    if (_pendingCount == 0 || _resolvingAll) return;
    _resolvingAll = true;
    setState(() {});
    final t = _t;
    try {
      final result = await _api.resolveAllPendingMatchesByPriority();
      if (!mounted) return;
      showToast(
        ref,
        ToastOptions(
          title: t.tf(
              'backgroundJobs.resolvedByPriorityToast',
              [result.resolvedCount, result.skippedCount]),
          description: t.tr('toast.descResolved'),
        ),
      );
      // Weak rows stay in review on purpose: reread so they appear back in
      // the list.
      await ref.read(jobsClientProvider.notifier).refreshPendingMatches();
      if (_pendingCount == 0) {
        ref
            .read(jobsClientProvider.notifier)
            .setModalTab(JobsModalTab.jobs);
      }
    } catch (error) {
      if (!mounted) return;
      _errorToast(error);
    } finally {
      _resolvingAll = false;
      if (mounted) {
        setState(() {});
        widget.onMediaChanged?.call();
      }
    }
  }

  /// The row is a junk import, no candidates or a manual search will save it:
  /// remove it entirely.
  void _deleteItem(String id) {
    _advanceSelection(id);
    ref.read(jobsClientProvider.notifier).dropPendingMatch(id);
    final t = _t;
    unawaited(() async {
      try {
        await _api.deleteMedia(id);
        if (!mounted) return;
        showToast(
          ref,
          ToastOptions(
            title: t.tr('backgroundJobs.deletedToast'),
            description: t.tr('toast.descDeleted'),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        _errorToast(error);
      } finally {
        if (mounted) widget.onMediaChanged?.call();
      }
    }());
    setState(() {});
  }

  /// 1–4 pick a candidate, S/Space skips, Delete removes — never while the
  /// user is typing.
  KeyEventResult _handleHotkey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final jobs = ref.read(jobsClientProvider);
    final hw = HardwareKeyboard.instance;
    if (jobs.modalTab != JobsModalTab.review ||
        _previewCandidate != null ||
        hw.isControlPressed ||
        hw.isMetaPressed ||
        hw.isAltPressed ||
        _isTextEntryFocused() ||
        _selectedItem == null) {
      return KeyEventResult.ignored;
    }

    final character = event.character;
    final selectedItem = _selectedItem!;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= '1'.codeUnitAt(0) &&
        character.codeUnitAt(0) <= '4'.codeUnitAt(0)) {
      final index = int.parse(character) - 1;
      final candidates = _candidatesFor(selectedItem);
      if (index >= candidates.length) return KeyEventResult.ignored;
      _resolve(selectedItem, candidates[index]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _skipCurrent();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _deleteItem(selectedItem.id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// isTextEntry-аналог: первичный фокус внутри EditableText (TextField).
  bool _isTextEntryFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    var found = false;
    ctx.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}

// ─── Приватные виджеты шаблона ──────────────────────────────────────────────

/// Кнопка закрытия шапки: h-8 w-8 hover:bg-white/10 hover:text-white.
class _HeaderCloseButton extends StatefulWidget {
  final VoidCallback onClose;
  final String semanticLabel;
  const _HeaderCloseButton({
    required this.onClose,
    required this.semanticLabel,
  });

  @override
  State<_HeaderCloseButton> createState() => _HeaderCloseButtonState();
}

class _HeaderCloseButtonState extends State<_HeaderCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return Semantics(
      button: true,
      label: widget.semanticLabel, // aria-label common.close
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _hovered
                  ? Colors.white.withAlpha(26) // hover:bg-white/10
                  : Colors.transparent,
            ),
            child: Icon(
              LucideIcons.x,
              size: 18,
              color: _hovered
                  ? Colors.white // hover:text-white
                  : th.textMuted, // text-muted
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка таба (role=tab): px-3.5 py-1.5 text-xs font-semibold rounded-md.
class _JobsTabButton extends StatelessWidget {
  final String label;
  final int? count;
  final bool active;
  final Color activeBackground;
  final Color activeForeground;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _JobsTabButton({
    required this.label,
    required this.count,
    required this.active,
    required this.activeBackground,
    required this.activeForeground,
    required this.th,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active, // aria-selected
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // rounded-md
            color: active ? activeBackground : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: active
                      ? activeForeground
                      : th.textMuted, // text-muted (hover:text-ink — hover-стейт кнопок не несёт семантики)
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8), // gap-2
                Container(
                  constraints: const BoxConstraints(minWidth: 16), // min-w-4
                  padding: const EdgeInsets.symmetric(horizontal: 4), // px-1
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999), // rounded-full
                    color: active
                        ? Colors.white.withAlpha(51) // bg-white/20
                        : const Color(0xE6F59E0B), // bg-amber-500/90
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10, // text-[10px]
                      height: 1.0, // leading-4
                      fontWeight: FontWeight.w700, // font-bold
                      color: active
                          ? activeForeground
                          : Colors.black, // text-black
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка задачи очереди: title, процент, отмена, прогресс-бар (scaleX),
/// batch-import notice + ETA, step/error строка.
class _JobCard extends StatelessWidget {
  final JobProgress job;
  final TsundokuTheme th;
  final I18nDictionary t;
  final VoidCallback onCancel;

  const _JobCard({
    required this.job,
    required this.th,
    required this.t,
    required this.onCancel,
  });

  /// TS печатает числа без хвостовых нулей: 45 → «45», 45.5 → «45.5».
  String get _percentText {
    final v = job.progressPercent;
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final failed = job.status == JobStatus.failed;
    final cancellable = isCancellableJob(job);
    final batch = isBatchImport(job);
    final eta = etaMinutes(job);
    final counts = stepCounts(job.currentStep);

    return Container(
      margin: const EdgeInsets.only(bottom: 12), // space-y-3
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.white.withAlpha(15)), // /[0.06]
        color: Colors.white.withAlpha(8), // bg-white/[0.03]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    fontWeight: FontWeight.w600, // font-semibold
                    color: th.textPrimary, // text-ink
                  ),
                ),
              ),
              const SizedBox(width: 12), // gap-3
              Text(
                '${failed ? '${t.tr('activity.failed')} · ' : ''}$_percentText%',
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: Color(0xFF94A3B8), // text-slate-400
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (cancellable) ...[
                const SizedBox(width: 12),
                Tooltip(
                  message: t.tr('activity.cancel'),
                  child: GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4), // px-2.5 py-1
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withAlpha(21)), // /[0.08]
                        color: th.bgSurface, // bg-field
                      ),
                      child: Text(
                        t.tr('activity.cancel'),
                        style: const TextStyle(
                          fontSize: 11, // text-[11px]
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8), // text-muted
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12), // mt-3
          // role=progressbar: h-2 rounded-full bg-white/[0.08]; fill
          // scaleX(progress) — transition 500ms ease-out.
          Semantics(
            button: false,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 8,
                color: Colors.white.withAlpha(21),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: job.progressPercent / 100),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value.clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: failed
                            ? const Color(0xE6F43F5E) // bg-rose-500/90
                            : job.status == JobStatus.completed
                                ? const Color(0xE610B981) // bg-emerald-500/90
                                : th.accentBright, // bg-accent-bright
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (batch) ...[
            const SizedBox(height: 8), // mt-2
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: th.accentBright.withAlpha(26), // bg-accent-bright/10
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.tr('backgroundJobs.throttleNotice'),
                      style: const TextStyle(
                        fontSize: 11, // text-[11px]
                        height: 1.625, // leading-relaxed
                        color: Color(0xFFA99CFF), // text-[#a99cff]
                      ),
                    ),
                  ),
                  if (eta != null && counts != null) ...[
                    const SizedBox(width: 8), // gap-2
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2), // px-2 py-0.5
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6), // rounded-md
                        color: th.accentBright, // bg-accent-bright
                      ),
                      child: Text(
                        t.tf('backgroundJobs.remainingMin', [eta]),
                        style: const TextStyle(
                          fontSize: 10, // text-[10px]
                          fontWeight: FontWeight.w700, // font-bold
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 8), // mt-2
          Text(
            job.errorMessage ?? statusLabelOf(job, t) ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12, // text-xs
              color: failed
                  ? const Color(0xFFFDA4AF) // text-rose-300
                  : th.textMuted, // text-muted
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопки intro-панели review: resolveAll (accent) / keepAll (secondary).
class _ReviewActionButton extends StatelessWidget {
  final TsundokuTheme th;
  final String label;
  final String tooltip;
  final bool disabled;
  final bool loading;
  final VoidCallback onTap;

  const _ReviewActionButton({
    required this.th,
    required this.label,
    required this.tooltip,
    required this.disabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 36, // h-9
          padding:
              const EdgeInsets.symmetric(horizontal: 14), // px-3.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: th.accent.withAlpha(102)), // border-accent/40
            color: th.accent.withAlpha(51), // bg-accent/20
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFA5B4FC)),
                ),
              const SizedBox(width: 6), // gap-1.5
              Text(
                label,
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: disabled ? th.textMuted : th.accentSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewSecondaryButton extends StatelessWidget {
  final TsundokuTheme th;
  final String label;
  final String tooltip;
  final bool disabled;
  final bool loading;
  final VoidCallback onTap;

  const _ReviewSecondaryButton({
    required this.th,
    required this.label,
    required this.tooltip,
    required this.disabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Colors.white.withAlpha(26)), // border-white/10
            color: th.bgSurface, // bg-field
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF94A3B8)),
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500, // font-medium
                  color: disabled
                      ? th.textMuted
                      : const Color(0xFFCBD5E1), // text-slate-300
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка master-списка: активная — border-accent/60 bg-accent/15.
class _PendingRow extends StatelessWidget {
  final PendingMatchItemDto item;
  final bool active;
  final int candidateCount;
  final TsundokuTheme th;
  final String suggestionsTitle;
  final VoidCallback onTap;

  const _PendingRow({
    required this.item,
    required this.active,
    required this.candidateCount,
    required this.th,
    required this.suggestionsTitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // space-y-1
      child: Semantics(
        button: true,
        selected: active, // aria-current
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8), // px-2.5 py-2
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12), // rounded-xl
              border: Border.all(
                color: active
                    ? th.accent.withAlpha(153) // border-accent/60
                    : Colors.transparent,
              ),
              color: active
                  ? th.accent.withAlpha(38) // bg-accent/15
                  : Colors.transparent,
              boxShadow: active
                  ? const [
                      // shadow-sm
                      BoxShadow(
                        color: Color(0x0D000000),
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    color: active
                        ? Colors.white
                        : const Color(0xFFCBD5E1), // text-slate-300
                  ),
                ),
                const SizedBox(height: 4), // mt-1
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2), // px-1.5 py-0.5
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: th.accentBright
                            .withAlpha(51), // bg-accent-bright/20
                      ),
                      child: Text(
                        '${item.type}${(item.isAnime ?? false) ? ' · anime' : ''}',
                        style: const TextStyle(
                          fontSize: 10, // text-[10px]
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8F7FFF),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6), // gap-1.5
                    Tooltip(
                      message: suggestionsTitle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white.withAlpha(15), // bg-white/[0.06]
                        ),
                        child: Text(
                          '$candidateCount',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: th.textMuted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка size-8: keep (X) / delete (Trash2, rose).
class _IconActionButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final String tooltip;
  final String semanticLabel;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.size,
    required this.tooltip,
    required this.semanticLabel,
    required this.th,
    required this.onTap,
  });

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.semanticLabel, // aria-label
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 32, // size-8
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.white.withAlpha(26)), // border-white/10
                color: _hovered
                    ? TsundokuTheme.of(context).bgElevated // hover:bg-elevated
                    : TsundokuTheme.of(context).bgSurface, // bg-field
              ),
              child: Icon(
                widget.icon,
                size: widget.size,
                color: _hovered
                    ? Colors.white // hover:text-white
                    : const Color(0xFFCBD5E1), // text-slate-300
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteActionButton extends StatefulWidget {
  final String semanticLabel;
  final VoidCallback onTap;

  const _DeleteActionButton({
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  State<_DeleteActionButton> createState() => _DeleteActionButtonState();
}

class _DeleteActionButtonState extends State<_DeleteActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Удалить тайтл из библиотеки',
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hovered
                      ? const Color(0x66F43F5E) // hover:border-rose-500/40
                      : const Color(0x33F43F5E), // border-rose-500/20
                ),
                color: _hovered
                    ? const Color(0x33F43F5E) // hover:bg-rose-500/20
                    : const Color(0x1AF43F5E), // bg-rose-500/10
              ),
              child: const Icon(
                LucideIcons.trash2,
                size: 15,
                color: Color(0xFFF87171), // text-rose-400
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Языковой тоггл RU/EN в поисковом поле: px-1.5 py-0.5 text-[10px] font-bold.
class _LanguageToggle extends StatefulWidget {
  final String label;
  final bool active;
  final TsundokuTheme th;
  final VoidCallback onTap;

  const _LanguageToggle({
    required this.label,
    required this.active,
    required this.th,
    required this.onTap,
  });

  @override
  State<_LanguageToggle> createState() => _LanguageToggleState();
}

class _LanguageToggleState extends State<_LanguageToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label == 'RU'
          ? 'Искать по русскому названию'
          : 'Искать по латинице / Romaji',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 2), // px-1.5 py-0.5
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), // rounded-md
              border: Border.all(
                color: widget.active
                    ? widget.th.accent // border-accent
                    : Colors.white.withAlpha(26), // border-white/10
              ),
              color: widget.active
                  ? widget.th.accent // bg-accent
                  : Colors.white.withAlpha(10), // bg-white/[0.04]
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 10, // text-[10px]
                fontWeight: FontWeight.w700, // font-bold
                color: widget.active
                    ? Colors.white
                    : (_hovered
                        ? Colors.white // hover:text-white
                        : TsundokuTheme.of(context).textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка запуска поиска: size-9 bg-accent, спиннер при loading.
class _SearchRunButton extends StatelessWidget {
  final TsundokuTheme th;
  final bool loading;
  final String semanticLabel;
  final VoidCallback onTap;

  const _SearchRunButton({
    required this.th,
    required this.loading,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          onTap: loading ? null : onTap,
          child: Container(
            width: 36, // size-9
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: th.accent, // bg-accent
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.search,
                      size: 15, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Actions-кнопка превью: bg-emerald-600/90 rounded-xl, Check + choose
/// (hover:bg-emerald-500/90).
class _PreviewChooseButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _PreviewChooseButton({required this.label, required this.onTap});

  @override
  State<_PreviewChooseButton> createState() => _PreviewChooseButtonState();
}

class _PreviewChooseButtonState extends State<_PreviewChooseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10), // px-4 py-2.5
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), // rounded-xl
            color: _hovered
                ? const Color(0xE610B981) // hover:bg-emerald-500/90
                : const Color(0xE6059669), // bg-emerald-600/90
            boxShadow: const [
              // shadow-md
              BoxShadow(
                color: Color(0x1A000000),
                offset: Offset(0, 4),
                blurRadius: 6,
                spreadRadius: -1,
              ),
              BoxShadow(
                color: Color(0x1A000000),
                offset: Offset(0, 2),
                blurRadius: 4,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.check,
                  size: 16, color: Colors.white), // stroke-width 2.5 (#26)
              const SizedBox(width: 8), // gap-2
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w700, // font-bold
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Постер кандидата: aspect 2/3, w-24 sm:w-28; hover — Eye-оверлей.
class _CandidatePoster extends StatefulWidget {
  final ExternalMedia candidate;
  final bool imgError;
  final TsundokuTheme th;
  final String viewLabel;
  final VoidCallback onPreview;
  final VoidCallback onImgError;

  const _CandidatePoster({
    required this.candidate,
    required this.imgError,
    required this.th,
    required this.viewLabel,
    required this.onPreview,
    required this.onImgError,
  });

  @override
  State<_CandidatePoster> createState() => _CandidatePosterState();
}

class _CandidatePosterState extends State<_CandidatePoster> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width >= 640 ? 112.0 : 96.0; // sm:w-28
    final hasCover = widget.candidate.coverUrl?.isNotEmpty ?? false;
    return Tooltip(
      message: widget.viewLabel,
      child: GestureDetector(
        onTap: widget.onPreview,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12), // rounded-xl
              boxShadow: const [
                // shadow-md
                BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 4),
                  blurRadius: 6,
                  spreadRadius: -1,
                ),
                BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(0, 2),
                  blurRadius: 4,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: 2 / 3, // aspect-[2/3]
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withAlpha(26)), // ring-white/10
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasCover && !widget.imgError
                        ? TsundokuImage(
                            imageUrl: widget.candidate.coverUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: Builder(
                              builder: (context) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  widget.onImgError();
                                });
                                return Container(
                                    color: TsundokuTheme.of(context).bgCanvas);
                              },
                            ),
                          )
                        : const Placeholder404(),
                  ),
                  // Eye-оверлей: bg-black/40, opacity 0 → 1 при hover.
                  if (_hovered)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.black.withAlpha(102), // bg-black/40
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.eye,
                            size: 20, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
