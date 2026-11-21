/// 1:1 port of `mediatracker-ui/src/widgets/layout/ActivityDropdown.svelte`.
///
/// Кнопка «фоновые процессы» с бейджами (active/pending) и поповер:
/// очередь задач (прогресс-бары, отмена), pending-review-кнопка, лимиты API
/// (countdown 1s + poll 10s, live только при открытом поповере). Очередь
/// глобальна и переживает вью — сокет открывается один раз при монтировании
/// (connect), а не при каждом открытии.
///
/// CSS anchor-positioning → OverlayPortal с позиционированием от RenderBox
/// кнопки (top: bottom+8, right-выравнивание, w-80/sm:w-96).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/api/api.dart';
import '../../shared/api/jobs_client.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/index.dart' show ApiRateLimitStatus;

class ActivityDropdown extends ConsumerStatefulWidget {
  const ActivityDropdown({super.key});

  @override
  ConsumerState<ActivityDropdown> createState() => _ActivityDropdownState();
}

class _ActivityDropdownState extends ConsumerState<ActivityDropdown> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _buttonKey = GlobalKey();

  List<ApiRateLimitStatus> _rateLimits = const <ApiRateLimitStatus>[];
  bool _rateLimitsRefreshing = false;
  Timer? _countdownTimer;
  Timer? _pollTimer;

  Future<void> _refreshRateLimits() async {
    setState(() => _rateLimitsRefreshing = true);
    try {
      _rateLimits = await ref.read(apiClientProvider).getRateLimits();
    } catch (_) {
      // Ignore polling errors
    } finally {
      if (mounted) setState(() => _rateLimitsRefreshing = false);
    }
  }

  void _startRateLimitTracking() {
    unawaited(_refreshRateLimits());
    _stopRateLimitTracking();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rateLimits.isEmpty) return;
      setState(() {
        _rateLimits = _rateLimits
            .map((item) => ApiRateLimitStatus(
                  provider: item.provider,
                  remaining: item.remaining,
                  limit: item.limit,
                  resetSecondsRemaining:
                      item.resetSecondsRemaining > 0
                          ? item.resetSecondsRemaining - 1
                          : 0,
                  updatedAt: item.updatedAt,
                ))
            .toList();
      });
    });

    _pollTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => unawaited(_refreshRateLimits()));
  }

  void _stopRateLimitTracking() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
      _stopRateLimitTracking();
    } else {
      _portal.show();
      _startRateLimitTracking();
    }
  }

  void _openProcesses(JobsModalTab tab) {
    if (_portal.isShowing) _portal.hide();
    _stopRateLimitTracking();
    ref.read(jobsClientProvider.notifier).openModal(tab);
  }

  String _statusLabel(JobProgress job, I18nDictionary t) {
    switch (job.status) {
      case JobStatus.queued:
        return t.tr('activity.queued');
      case JobStatus.completed:
        return t.tr('activity.completed');
      case JobStatus.failed:
        return t.tr('activity.failed');
      case JobStatus.cancelled:
        return t.tr('activity.cancelled');
      default:
        return job.currentStep;
    }
  }

  bool _isCancellable(JobProgress job) =>
      job.status == JobStatus.queued || job.status == JobStatus.running;

  /// Контроллер сохраняется до dispose: ref в dispose недоступен.
  late JobsClientController _jobs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _jobs = ref.read(jobsClientProvider.notifier);
  }

  @override
  void initState() {
    super.initState();
    // The queue is global and outlives any single view, so the socket is
    // opened once on mount rather than per panel open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jobs.connect();
    });
  }

  @override
  void dispose() {
    _jobs.disconnect();
    _stopRateLimitTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final jobs = ref.watch(jobsClientProvider);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        if (!_portal.isShowing) return const SizedBox.shrink();
        final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return const SizedBox.shrink();
        final buttonTop = box.localToGlobal(Offset.zero).dy;
        final buttonRight = box.localToGlobal(
            Offset(box.size.width, 0)).dx;
        final screenWidth = MediaQuery.sizeOf(overlayContext).width;

        return Positioned(
          top: buttonTop + box.size.height + 8, // top: anchor(bottom) + 8px
          right: screenWidth - buttonRight, // right: anchor(right)
          child: _Popover(
            state: this,
            t: t,
            th: th,
            jobs: jobs,
          ),
        );
      },
      child: _ActivityButton(
        key: _buttonKey,
        t: t,
        th: th,
        activeCount: jobs.jobs.where(isActiveJob).length,
        pendingCount: jobs.pendingMatches.length,
        spinning: jobs.jobs.where(isActiveJob).isNotEmpty,
        onPressed: _toggle,
      ),
    );
  }
}

/// Кнопка 36×36: bg-elevated, border-white/[0.08], Activity 17px (спин 3s
/// при активных задачах), бейдж active (accent-bright) / pending (amber).
class _ActivityButton extends StatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final int activeCount;
  final int pendingCount;
  final bool spinning;
  final VoidCallback onPressed;

  const _ActivityButton({
    super.key,
    required this.t,
    required this.th,
    required this.activeCount,
    required this.pendingCount,
    required this.spinning,
    required this.onPressed,
  });

  @override
  State<_ActivityButton> createState() => _ActivityButtonState();
}

class _ActivityButtonState extends State<_ActivityButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3), // animate-[spin_3s_linear_infinite]
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.th;
    final badge = widget.activeCount > 0
        ? Container(
            constraints: const BoxConstraints(minWidth: 16), // min-w-4
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: th.accentBright, // bg-accent-bright
              borderRadius: BorderRadius.circular(999), // rounded-full
            ),
            child: Text(
              '${widget.activeCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10, // text-[10px]
                height: 16 / 10, // leading-4
                fontWeight: FontWeight.w700, // font-bold
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()], // tabular-nums
              ),
            ),
          )
        : widget.pendingCount > 0
            ? Container(
                constraints: const BoxConstraints(minWidth: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xE6F59E0B), // bg-amber-500/90
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.pendingCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 16 / 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              )
            : null;

    return GestureDetector(
      onTap: widget.onPressed,
      child: Tooltip(
        message: widget.t.tr('activity.open'),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36, // h-9 w-9
              height: 36,
              decoration: BoxDecoration(
                color: th.bgElevated, // bg-elevated
                borderRadius: BorderRadius.circular(8), // rounded-lg
                border: Border.all(color: Colors.white.withAlpha(20)), // white/[0.08]
              ),
              child: Center(
                child: widget.spinning
                    ? RotationTransition(
                        turns: _spin,
                        child: Icon(
                          LucideIcons.activity, // Activity size={17}
                          size: 17,
                          color: th.textMuted, // text-muted
                        ),
                      )
                    : Icon(
                        LucideIcons.activity,
                        size: 17,
                        color: th.textMuted,
                      ),
              ),
            ),
            if (badge != null)
              Positioned(top: -4, right: -4, child: badge), // -top-1 -right-1
          ],
        ),
      ),
    );
  }
}

/// Поповер: заголовок + active-бейдж, pending-review-кнопка, список задач,
/// лимиты API, кнопка «Открыть окно процессов».
class _Popover extends StatelessWidget {
  final _ActivityDropdownState state;
  final I18nDictionary t;
  final TsundokuTheme th;
  final JobsState jobs;

  const _Popover({
    required this.state,
    required this.t,
    required this.th,
    required this.jobs,
  });

  String _statusLabel(JobProgress job) => state._statusLabel(job, t);
  bool _isCancellable(JobProgress job) => state._isCancellable(job);

  @override
  Widget build(BuildContext context) {
    final activeCount = jobs.jobs.where(isActiveJob).length;
    final pendingCount = jobs.pendingMatches.length;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 384, // sm:w-96
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(12), // p-3
        decoration: BoxDecoration(
          color: const Color(0xFF181B24), // bg-[#181b24]
          borderRadius: BorderRadius.circular(8), // rounded-lg
          border: Border.all(color: Colors.white.withAlpha(26)), // border-white/10
          boxShadow: const [
            BoxShadow(
              color: Color(0xB3000000), // shadow-black/70
              offset: Offset(0, 25),
              blurRadius: 50,
              spreadRadius: -12,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(th: th, t: t, activeCount: activeCount),
              const SizedBox(height: 8), // mb-2
              if (pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PendingReviewButton(
                    t: t,
                    pendingCount: pendingCount,
                    onPressed: () => state._openProcesses(JobsModalTab.review),
                  ),
                ),
              if (jobs.jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
                  child: Column(
                    children: [
                      Text(
                        t.tr('activity.empty'),
                        style: TextStyle(
                          fontSize: 14, // text-sm
                          fontWeight: FontWeight.w500, // font-medium
                          color: th.textPrimary, // text-ink
                        ),
                      ),
                      const SizedBox(height: 4), // mt-1
                      Text(
                        t.tr('activity.emptyHint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12, // text-xs
                          color: th.textMuted, // text-muted
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...[for (final job in jobs.jobs) _JobCard(job: job, t: t, th: th,
                    statusLabel: _statusLabel(job),
                    cancellable: _isCancellable(job),
                    onCancel: () =>
                        unawaited(state.ref
                            .read(jobsClientProvider.notifier)
                            .cancel(job.jobId)))],
              if (state._rateLimits.isNotEmpty)
                _RateLimitsSection(
                  state: state,
                  t: t,
                  th: th,
                ),
              const SizedBox(height: 12), // mt-3
              _OpenWindowButton(
                t: t,
                th: th,
                onPressed: () => state._openProcesses(JobsModalTab.jobs),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TsundokuTheme th;
  final I18nDictionary t;
  final int activeCount;

  const _Header({required this.th, required this.t, required this.activeCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            t.tr('activity.label').toUpperCase(), // uppercase
            style: TextStyle(
              fontSize: 12, // text-xs
              fontWeight: FontWeight.w700, // font-bold
              letterSpacing: 0.05 * 12, // tracking-wider
              color: const Color(0xFFCBD5E1), // text-slate-300
            ),
          ),
        ),
        if (activeCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // px-2 py-0.5
            decoration: BoxDecoration(
              color: th.accentBright.withAlpha(51), // bg-accent-bright/20
              borderRadius: BorderRadius.circular(999), // rounded-full
            ),
            child: Text(
              '$activeCount',
              style: const TextStyle(
                fontSize: 10, // text-[10px]
                fontWeight: FontWeight.w700, // font-bold
                color: Color(0xFF8F7FFF), // text-[#8f7fff]
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}

class _PendingReviewButton extends StatefulWidget {
  final I18nDictionary t;
  final int pendingCount;
  final VoidCallback onPressed;

  const _PendingReviewButton({
    required this.t,
    required this.pendingCount,
    required this.onPressed,
  });

  @override
  State<_PendingReviewButton> createState() => _PendingReviewButtonState();
}

class _PendingReviewButtonState extends State<_PendingReviewButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xE6FBBF24) // hover:bg-amber-400/90
                : const Color(0xE6F59E0B), // bg-amber-500/90
            borderRadius: BorderRadius.circular(6), // rounded-md
          ),
          child: Center(
            child: Text(
              widget.t.tf('backgroundJobs.pendingCount', [widget.pendingCount]),
              style: const TextStyle(
                fontSize: 12, // text-xs
                fontWeight: FontWeight.w700, // font-bold
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Задача: title + cancel (если очередная/запущенная), прогресс-бар,
/// статус/ошибка + проценты.
class _JobCard extends StatelessWidget {
  final JobProgress job;
  final I18nDictionary t;
  final TsundokuTheme th;
  final String statusLabel;
  final bool cancellable;
  final VoidCallback onCancel;

  const _JobCard({
    required this.job,
    required this.t,
    required this.th,
    required this.statusLabel,
    required this.cancellable,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (job.progressPercent / 100).clamp(0.0, 1.0).toDouble();

    return Container(
      margin: const EdgeInsets.only(top: 8), // space-y-2
      padding: const EdgeInsets.all(10), // p-2.5
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8), // bg-white/[0.03]
        borderRadius: BorderRadius.circular(6), // rounded-md
        border: Border.all(color: Colors.white.withAlpha(15)), // white/[0.06]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // truncate
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    color: th.textPrimary, // text-ink
                  ),
                ),
              ),
              if (cancellable)
                _CancelButton(t: t, title: job.title, onCancel: onCancel),
            ],
          ),
          const SizedBox(height: 8), // mt-2
          // progressbar: bg-white/[0.08] h-1 rounded-full; fill accent-bright.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 4, color: Colors.white.withAlpha(20)),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 4,
                    color: th.accentBright, // bg-accent-bright
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6), // mt-1.5
          Row(
            children: [
              Expanded(
                child: Text(
                  job.errorMessage ?? statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11, // text-[11px]
                    color: job.status == JobStatus.failed
                        ? const Color(0xFFFDA4AF) // text-rose-300
                        : th.textMuted, // text-muted
                  ),
                ),
              ),
              Text(
                '${job.progressPercent.round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500, // font-medium
                  color: const Color(0xFF94A3B8), // text-slate-400
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Кнопка отмены задачи: h-6 w-6 rounded-full, hover:bg-rose-500/20
/// hover:text-rose-300.
class _CancelButton extends StatefulWidget {
  final I18nDictionary t;
  final String title;
  final VoidCallback onCancel;

  const _CancelButton({
    required this.t,
    required this.title,
    required this.onCancel,
  });

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.t.tr('activity.cancel'),
        child: GestureDetector(
          onTap: widget.onCancel,
          child: Semantics(
            button: true,
            label: widget.t.tf('activity.cancelAria', [widget.title]),
            child: Container(
              width: 24, // h-6 w-6
              height: 24,
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0x33F43F5E) // hover:bg-rose-500/20
                    : Colors.transparent,
                shape: BoxShape.circle, // rounded-full
              ),
              child: Icon(
                LucideIcons.x, // X size={13}
                size: 13,
                color: _hovered
                    ? const Color(0xFFFDA4AF) // hover:text-rose-300
                    : Colors.white.withAlpha(120), // text-muted
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Лимиты API: countdown 1s (resetSecondsRemaining), poll 10s (состояние в
/// родителе), refresh-кнопка, unlimited-ветка, цветные полосы.
class _RateLimitsSection extends StatelessWidget {
  final _ActivityDropdownState state;
  final I18nDictionary t;
  final TsundokuTheme th;

  const _RateLimitsSection({
    required this.state,
    required this.t,
    required this.th,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12), // mt-3
      padding: const EdgeInsets.only(top: 10), // pt-2.5
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))), // white/[0.08]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.tr('activity.rateLimitsTitle').toUpperCase(),
                  style: TextStyle(
                    fontSize: 11, // text-[11px]
                    fontWeight: FontWeight.w700, // font-bold
                    letterSpacing: 0.05 * 11, // tracking-wider
                    color: const Color(0xFF94A3B8), // text-slate-400
                  ),
                ),
              ),
              _RefreshButton(
                t: t,
                refreshing: state._rateLimitsRefreshing,
                onRefresh: () => unawaited(state._refreshRateLimits()),
              ),
            ],
          ),
          const SizedBox(height: 8), // mb-2
          for (final limit in state._rateLimits)
            _RateLimitCard(limit: limit, t: t, th: th),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  final I18nDictionary t;
  final bool refreshing;
  final VoidCallback onRefresh;

  const _RefreshButton({
    required this.t,
    required this.refreshing,
    required this.onRefresh,
  });

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1), // animate-spin
  );

  @override
  void initState() {
    super.initState();
    if (widget.refreshing) _spin.repeat();
  }

  @override
  void didUpdateWidget(_RefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshing) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: t.tr('activity.rateLimitsRefresh'),
        child: GestureDetector(
          onTap: widget.onRefresh,
          child: Container(
            width: 24, // h-6 w-6
            height: 24,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6), // rounded-md
            ),
            child: RotationTransition(
              turns: _spin,
              child: Icon(
                LucideIcons.rotateCw, // RefreshCw size={13}
                size: 13,
                color: Colors.white.withAlpha(120), // text-muted
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка лимита: unlimited (limit <= 0) или полоса remaining/limit с
/// reset-секундами.
class _RateLimitCard extends StatelessWidget {
  final ApiRateLimitStatus limit;
  final I18nDictionary t;
  final TsundokuTheme th;

  const _RateLimitCard({
    required this.limit,
    required this.t,
    required this.th,
  });

  @override
  Widget build(BuildContext context) {
    // limit <= 0 (Shikimori sends no headers): no 0/0 bar, just "unlimited".
    if (limit.limit <= 0) {
      return Container(
        margin: const EdgeInsets.only(top: 8), // space-y-2
        padding: const EdgeInsets.all(8), // p-2
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8), // bg-white/[0.03]
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withAlpha(15)), // white/[0.06]
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                limit.provider,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w500, // font-medium
                  color: Color(0xFFE2E8F0), // text-slate-200
                ),
              ),
            ),
            Text(
              t.tr('activity.rateLimitsUnlimited'),
              style: TextStyle(
                fontSize: 11, // text-[11px]
                color: th.textMuted, // text-muted
              ),
            ),
          ],
        ),
      );
    }

    final ratio = limit.limit > 0 ? limit.remaining / limit.limit : 0.0;
    final percent = (ratio * 100).round().clamp(0, 100);
    final barColor = limit.remaining <= 0
        ? const Color(0xE6F43F5E) // bg-rose-500/90
        : ratio < 0.3
            ? const Color(0xE6F59E0B) // bg-amber-500/90
            : const Color(0xE610B981); // bg-emerald-500/90

    return Container(
      margin: const EdgeInsets.only(top: 8), // space-y-2
      padding: const EdgeInsets.all(8), // p-2
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  limit.provider,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
              ),
              Text(
                t.tf('activity.remaining', [limit.remaining, limit.limit]),
                style: const TextStyle(
                  fontSize: 11, // text-[11px]
                  fontWeight: FontWeight.w500, // font-medium
                  color: Color(0xFF94A3B8), // text-slate-400
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6), // mt-1.5
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 4, color: Colors.white.withAlpha(20)),
                FractionallySizedBox(
                  widthFactor: percent / 100,
                  alignment: Alignment.centerLeft,
                  child: Container(height: 4, color: barColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4), // mt-1
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                limit.resetSecondsRemaining > 0
                    ? t.tf('activity.resetInSeconds', [limit.resetSecondsRemaining])
                    : t.tr('activity.resetReady'),
                style: TextStyle(
                  fontSize: 10, // text-[10px]
                  color: th.textMuted, // text-muted
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 10, // text-[10px]
                  color: th.textMuted, // text-muted
                  // font-mono tabular-nums
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Кнопка «Открыть окно процессов»: bg-field, border-white/10,
/// hover:bg-elevated hover:text-white.
class _OpenWindowButton extends StatefulWidget {
  final I18nDictionary t;
  final TsundokuTheme th;
  final VoidCallback onPressed;

  const _OpenWindowButton({
    required this.t,
    required this.th,
    required this.onPressed,
  });

  @override
  State<_OpenWindowButton> createState() => _OpenWindowButtonState();
}

class _OpenWindowButtonState extends State<_OpenWindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // px-3 py-2
          decoration: BoxDecoration(
            color: _hovered
                ? widget.th.bgElevated // hover:bg-elevated
                : widget.th.bgSurface, // bg-field (— var(--bg-surface))
            borderRadius: BorderRadius.circular(6), // rounded-md
            border: Border.all(color: Colors.white.withAlpha(26)), // white/10
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.t.tr('backgroundJobs.openWindow'),
                style: TextStyle(
                  fontSize: 12, // text-xs
                  fontWeight: FontWeight.w600, // font-semibold
                  color: _hovered
                      ? Colors.white // hover:text-white
                      : widget.th.textPrimary, // text-ink
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
