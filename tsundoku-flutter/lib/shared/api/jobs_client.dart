/// 1:1 port of `mediatracker-ui/src/shared/api/jobsClient.svelte.ts`.
///
/// $state/$derived → Riverpod; EventSource (`/api/jobs/stream`,
/// `text/event-stream`) → dio streamed-ответ (кроссплатформенно, web-тоже);
/// `window.history.pushState/back` для модалки — браузерная фича, в Flutter
/// не нужна (Navigator сам управляет стеком; решение #10).
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../types/dtos.dart';
import '../types/enums.dart';
import 'api.dart';

/// A finished job stays visible long enough for the eye to catch the 100%
/// before it vanishes.
const Duration completedTtl = Duration(milliseconds: 4000);

/// Safety timeout for active jobs if SSE updates stop arriving (server limit
/// is 60s).
const Duration activeJobTimeout = Duration(milliseconds: 70000);

/// Interval to reconcile active jobs with the backend snapshot in case SSE
/// events were lost.
const Duration syncInterval = Duration(seconds: 10);

/// The queue '+ results' pair must not be hammered on every SSE tick.
const Duration pendingRefreshThrottle = Duration(milliseconds: 5000);

bool isActiveJob(JobProgress job) =>
    job.status == JobStatus.running || job.status == JobStatus.queued;

/// `modalTab: "jobs" | "review"`.
enum JobsModalTab { jobs, review }

/// Иммутабельный снимок стейта JobsClient ($state → одно состояние).
@immutable
class JobsState {
  final List<JobProgress> jobs;
  final List<PendingMatchItemDto> pendingMatches;
  final bool isModalOpen;
  final JobsModalTab modalTab;

  const JobsState({
    this.jobs = const <JobProgress>[],
    this.pendingMatches = const <PendingMatchItemDto>[],
    this.isModalOpen = false,
    this.modalTab = JobsModalTab.jobs,
  });

  JobsState copyWith({
    List<JobProgress>? jobs,
    List<PendingMatchItemDto>? pendingMatches,
    bool? isModalOpen,
    JobsModalTab? modalTab,
  }) =>
      JobsState(
        jobs: jobs ?? this.jobs,
        pendingMatches: pendingMatches ?? this.pendingMatches,
        isModalOpen: isModalOpen ?? this.isModalOpen,
        modalTab: modalTab ?? this.modalTab,
      );
}

/// The single live view of the background queue.
class JobsClientController extends Notifier<JobsState> {
  StreamSubscription<Uint8List>? _streamSub;
  final Map<String, Timer> _evictionTimers = <String, Timer>{};
  final Map<String, Timer> _safetyTimers = <String, Timer>{};
  Timer? _syncInterval;
  int _pendingRefreshedAt = 0;
  int _pendingSequence = 0;
  final Set<void Function(JobProgress job)> _jobSettledListeners =
      <void Function(JobProgress)>{};

  @override
  JobsState build() {
    ref.onDispose(disconnect);
    return const JobsState();
  }

  /// Прокси для подсистем (api-провайдер инъекцией).
  late TsundokuApi api;

  void attachApi(TsundokuApi api) {
    this.api = api;
  }

  // ------------------------------------------------------------------
  // onJobSettled.
  // ------------------------------------------------------------------

  void Function() onJobSettled(void Function(JobProgress job) cb) {
    _jobSettledListeners.add(cb);
    return () => _jobSettledListeners.remove(cb);
  }

  // ------------------------------------------------------------------
  // connect / disconnect (EventSource → dio stream).
  // ------------------------------------------------------------------

  void connect() {
    // The socket is opened lazily so importing this module never touches the
    // network from a non-app context.
    if (_streamSub != null) return;

    final request = _dioFetchStream('/api/jobs/stream');
    request.then((response) {
      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .transform(_sseDataLines())
          .listen(
            applyJson,
            onError: (Object _) {
              // Reconcile on reconnect / disconnect in case events were lost.
              syncJobs();
            },
          );
    }).catchError((Object _) {
      syncJobs();
    });
    refreshPendingMatches();

    _syncInterval ??= Timer.periodic(syncInterval, (_) {
      if (activeCount > 0) {
        syncJobs();
      }
    });
  }

  StreamTransformer<String, String> _sseDataLines() =>
      StreamTransformer.fromBind((stream) async* {
        String buffer = '';
        await for (final line in stream) {
          if (line.isEmpty) {
            // Конец события: отдаём накопленный data-буфер (без префикса).
            for (final dataLine in buffer.split('\n')) {
              if (dataLine.startsWith('data:')) {
                yield dataLine.substring(5).trimLeft();
              }
            }
            buffer = '';
          } else {
            buffer = buffer.isEmpty ? line : '$buffer\n$line';
          }
        }
      });

  Future<dynamic> _dioFetchStream(String path) {
    return api.dio.fetch<ResponseBody>(
      RequestOptions(
        path: path,
        method: 'GET',
        responseType: ResponseType.stream,
        sendTimeout: TsundokuApi.requestTimeout,
        receiveTimeout: TsundokuApi.requestTimeout,
      ),
    );
  }

  void disconnect() {
    _streamSub?.cancel();
    _streamSub = null;
    _syncInterval?.cancel();
    _syncInterval = null;
    for (final timer in _safetyTimers.values) {
      timer.cancel();
    }
    _safetyTimers.clear();
    for (final timer in _evictionTimers.values) {
      timer.cancel();
    }
    _evictionTimers.clear();
  }

  // ------------------------------------------------------------------
  // Derived-данные ($derived → методы/геттеры поверх state).
  // ------------------------------------------------------------------

  List<JobProgress> get activeJobs =>
      state.jobs.where(isActiveJob).toList(growable: false);

  int get activeCount => state.jobs.where(isActiveJob).length;

  int get pendingCount => state.pendingMatches.length;

  /// The job currently enriching this media item, if any. Drives the detail
  /// screen skeletons.
  JobProgress? jobFor(String mediaId) {
    for (final job in state.jobs) {
      if (job.mediaId == mediaId) return job;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // syncJobs (reconcile).
  // ------------------------------------------------------------------

  /// Direct snapshot sync with backend to clean up any desynced active jobs.
  Future<void> syncJobs() async {
    try {
      final snapshot = await api.requestJson<List<JobProgress>>(
        '/api/jobs',
        parse: (json) => (json as List<dynamic>)
            .map((e) => JobProgress.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      final activeServerJobMap = <String, JobProgress>{
        for (final j in snapshot) j.jobId: j,
      };

      for (final localJob in List<JobProgress>.from(state.jobs)) {
        if (!isActiveJob(localJob)) continue;
        final serverJob = activeServerJobMap[localJob.jobId];
        if (serverJob == null) {
          // Job is no longer on server (already finished/forgotten).
          applyJson(jsonEncode({
            ...localJob.toJson(),
            'status': 'Completed',
            'progressPercent': 100,
            'currentStep': 'Готово',
          }));
        } else if (serverJob.status != localJob.status ||
            serverJob.progressPercent != localJob.progressPercent) {
          applyJson(jsonEncode(serverJob.toJson()));
        }
      }
    } catch (_) {
      // Игнорируем — как в исходнике (catch {}).
    }
  }

  // ------------------------------------------------------------------
  // Modal (окно «Фоновые процессы»).
  // ------------------------------------------------------------------

  void openModal([JobsModalTab tab = JobsModalTab.jobs]) {
    state = state.copyWith(modalTab: tab, isModalOpen: true);
    // window.history.pushState — браузерная фича; во Flutter стек навигации
    // управляет сам (решение #10). Список ревью протухает при закрытии —
    // открытие дешёвый момент перечитать:
    refreshPendingMatches();
  }

  void closeModal() {
    state = state.copyWith(isModalOpen: false);
  }

  // ------------------------------------------------------------------
  // Pending matches.
  // ------------------------------------------------------------------

  /// Removes one resolved/skipped title from the review list without a round
  /// trip.
  void dropPendingMatch(String id) {
    state = state.copyWith(
      pendingMatches: state.pendingMatches
          .where((item) => item.id != id)
          .toList(growable: false),
    );
  }

  Future<void> refreshPendingMatches() async {
    _pendingRefreshedAt = DateTime.now().millisecondsSinceEpoch;
    final sequence = ++_pendingSequence;
    try {
      final items = await api.getPendingMatches();
      // A stale response must not resurrect a title the user just resolved.
      if (sequence == _pendingSequence) {
        state = state.copyWith(pendingMatches: items);
      }
    } catch (_) {
      // Игнорируем — как в исходнике (.catch(() => {})).
    }
  }

  void _refreshPendingMatchesThrottled(bool force) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _pendingRefreshedAt < pendingRefreshThrottle.inMilliseconds) {
      return;
    }
    refreshPendingMatches();
  }

  // ------------------------------------------------------------------
  // cancel.
  // ------------------------------------------------------------------

  Future<void> cancel(String jobId) async {
    try {
      await api.requestVoid('/api/jobs/$jobId/cancel', method: 'POST');
    } catch (error) {
      // console.error аналог: не роняем вызывающий флоу.
      debugPrint('Failed to cancel job $jobId: $error');
    }
  }

  // ------------------------------------------------------------------
  // #apply (SSE-событие).
  // ------------------------------------------------------------------

  /// Публично для тестов: подставить pending-matches без сетевого refetch
  /// (реальный путь — refreshPendingMatches из connect/openModal).
  @visibleForTesting
  void setPendingMatchesForTest(List<PendingMatchItemDto> items) {
    state = state.copyWith(pendingMatches: items);
  }

  /// Публично для тестов и stream-обработчика: применить raw SSE-payload.
  @visibleForTesting
  void applyJson(String raw) {
    JobProgress job;
    try {
      job = JobProgress.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return;
    }

    final index =
        state.jobs.indexWhere((entry) => entry.jobId == job.jobId);
    final previous = index == -1 ? null : state.jobs[index];
    List<JobProgress> jobs;
    if (index == -1) {
      jobs = [...state.jobs, job];
    } else {
      // Every event carries the full state, so this replaces rather than
      // merges.
      jobs = [
        for (final entry in state.jobs)
          if (entry.jobId == job.jobId) job else entry,
      ];
    }
    state = state.copyWith(jobs: jobs);

    final wasTerminal = previous != null && !isActiveJob(previous);
    final nowTerminal = !isActiveJob(job);
    if (nowTerminal && !wasTerminal) {
      for (final listener in List.of(_jobSettledListeners)) {
        try {
          listener(job);
        } catch (e) {
          debugPrint('Error in jobSettled listener: $e');
        }
      }
    }

    final settled = previous != null && isActiveJob(previous) != isActiveJob(job);
    if (isActiveJob(job)) {
      // A batch job re-checks ambiguous rows as it walks through the import.
      _refreshPendingMatchesThrottled(false);

      // Arm safety timer in case server or SSE stalls indefinitely.
      _safetyTimers[job.jobId]?.cancel();
      _safetyTimers[job.jobId] = Timer(activeJobTimeout, () {
        _safetyTimers.remove(job.jobId);
        applyJson(jsonEncode({
          ...job.toJson(),
          'status': 'Failed',
          'currentStep': 'Таймаут выполнения',
          'errorMessage': 'Превышено время ожидания задачи',
        }));
      });
      return;
    }

    // Job is now terminal: clear safety timer.
    _safetyTimers.remove(job.jobId)?.cancel();

    if (settled) {
      // Completed / failed / cancelled jobs can leave newly parked rows
      // behind.
      _refreshPendingMatchesThrottled(true);
    }

    _evictionTimers[job.jobId]?.cancel();
    _evictionTimers[job.jobId] = Timer(completedTtl, () {
      _evictionTimers.remove(job.jobId);
      state = state.copyWith(
        jobs: state.jobs
            .where((entry) => entry.jobId != job.jobId)
            .toList(growable: false),
      );
    });
  }
}

/// `export const jobsClient = new JobsClient();`
final jobsClientProvider =
    NotifierProvider<JobsClientController, JobsState>(JobsClientController.new);

/// `activeJobs` derived.
final activeJobsProvider = Provider<List<JobProgress>>((ref) {
  return ref.watch(jobsClientProvider).jobs.where(isActiveJob).toList();
});

/// `activeCount` derived.
final activeJobsCountProvider =
    Provider<int>((ref) => ref.watch(activeJobsProvider).length);

/// `pendingCount` derived.
final pendingMatchesCountProvider = Provider<int>(
    (ref) => ref.watch(jobsClientProvider).pendingMatches.length);
