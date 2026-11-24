/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/SeasonRow.svelte`.
///
/// Строка сезона tvshow: постер, номер сезона, счётчик эпизодов с дебаунс-
/// отправкой прогресса (optimistic + откат + flush при утилизации).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/progress_rules.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/index.dart' show TvSeason;
import '../../shared/ui/tsundoku_image.dart';
import '../../shared/utils/progress_debounce.dart';

/// Строка сезона (1-в-1 с SeasonRow.svelte).
class SeasonRow extends ConsumerStatefulWidget {
  final TvSeason season;
  final Future<void> Function(String id, int currentEpisode) onProgress;
  final void Function() onProgressCommitted;

  const SeasonRow({
    super.key,
    required this.season,
    required this.onProgress,
    required this.onProgressCommitted,
  });

  @override
  ConsumerState<SeasonRow> createState() => _SeasonRowState();
}

class _SeasonRowState extends ConsumerState<SeasonRow> {
  TvSeason? _trackedSeason;
  late int _currentEpisode = widget.season.currentEpisode;
  late int _committedEpisode = widget.season.currentEpisode;
  int? _pendingSnapshot;
  Object? _mutationError;
  late final ProgressDebouncer _progressDebounce = ProgressDebouncer(
    ProgressDebounceOptions(
      send: (id, value) => widget.onProgress(id, value),
      buildRequest: (id, value) => ProgressRequest(
        url: '/api/seasons/$id/progress',
        body: {'currentEpisode': value},
      ),
      onCommitted: (value) {
        _committedEpisode = value;
        if (_currentEpisode == value) {
          widget.onProgressCommitted();
        }
      },
      onError: (error) {
        _currentEpisode = _pendingSnapshot ?? _committedEpisode;
        _committedEpisode = _currentEpisode;
        _pendingSnapshot = null;
        _mutationError = error;
        if (mounted) setState(() {});
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    _trackedSeason = widget.season;
  }

  @override
  void didUpdateWidget(covariant SeasonRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.season != _trackedSeason) {
      _trackedSeason = widget.season;
      _currentEpisode = widget.season.currentEpisode;
      _committedEpisode = widget.season.currentEpisode;
      _pendingSnapshot = null;
      setState(() {});
    }
  }

  @override
  void dispose() {
    unawaitedFlush();
    super.dispose();
  }

  void unawaitedFlush() {
    _progressDebounce.flush(keepalive: true);
  }

  String _format(int value, Locale locale) =>
      NumberFormat.decimalPattern(locale.wire).format(value);

  void _scheduleProgress(int delta) {
    final next = clampProgress(
        _currentEpisode + delta, widget.season.totalEpisodes);
    if (next == _currentEpisode) return;

    _pendingSnapshot ??= _committedEpisode;
    setState(() {
      _currentEpisode = next;
      _mutationError = null;
    });
    _progressDebounce.schedule(widget.season.id, next);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final th = TsundokuTheme.of(context);
    final locale = ref.watch(i18nProvider);
    final season = widget.season;
    final isDesktop = MediaQuery.sizeOf(context).width >= 640; // sm:

    final poster = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6), // rounded-md
        color: th.bgCanvas, // bg-canvas
      ),
      clipBehavior: Clip.antiAlias,
      child: season.coverUrl != null && season.coverUrl!.isNotEmpty
          ? TsundokuImage(
              imageUrl: season.coverUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    th.bgSurface, // from-panel
                    th.bgElevated, // to-elevated
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  LucideIcons.image,
                  size: 24,
                  color: th.textMuted,
                ),
              ),
            ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t.tr('createModal.fields.season')} ${season.seasonNumber}'
              .toUpperCase(),
          style: TextStyle(
            fontSize: 10, // text-[10px]
            fontWeight: FontWeight.w700, // font-bold
            letterSpacing: 1.6, // tracking-[0.16em]
            color: th.accentSoft, // text-accent-soft
          ),
        ),
        Text(
          season.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14, // text-sm
            fontWeight: FontWeight.w600, // font-semibold
            color: th.textPrimary, // text-ink
          ),
        ),
        const SizedBox(height: 8), // space-y-2
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.tf('card.episodes', [_currentEpisode, season.totalEpisodes]),
                    style: TextStyle(
                      fontSize: 12, // text-xs
                      color: th.textMuted, // text-muted
                    ),
                  ),
                ),
                Text(
                  '${_format(_currentEpisode, locale)} / ${_format(season.totalEpisodes, locale)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: th.textMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (season.totalEpisodes > 0) ...[
              const SizedBox(height: 6), // space-y-1.5
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 6, // h-1.5
                  color: th.bgCanvas,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 200),
                      alignment: Alignment.centerLeft,
                      widthFactor: math
                          .min(_currentEpisode / season.totalEpisodes, 1)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                      heightFactor: 1,
                      child: Container(color: th.accent),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_mutationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8), // space-y-2
            child: Semantics(
              liveRegion: true, // role="alert"
              child: Text(
                errorMessage(_mutationError!, locale),
                style: const TextStyle(
                  fontSize: 12, // text-xs
                  color: Color(0xFFFDA4AF), // text-rose-300
                ),
              ),
            ),
          ),
      ],
    );

    final controls = Container(
      height: 36, // h-9
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6), // rounded-md
        color: th.bgCanvas, // bg-canvas
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: LucideIcons.minus,
            label: t.tr('card.decrement'),
            th: th,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(6)),
            onTap: () => _scheduleProgress(-1),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40), // min-w-10
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8), // px-2
              child: Center(
                child: Text(
                  _format(_currentEpisode, locale),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    fontWeight: FontWeight.w600, // font-semibold
                    color: th.textPrimary, // text-ink
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          _StepperButton(
            icon: LucideIcons.plus,
            label: t.tr('card.increment'),
            th: th,
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(6)),
            onTap: () => _scheduleProgress(1),
          ),
        ],
      ),
    );

    // article: bg-card rounded-lg p-3 gap-4; десктоп — строка
    // [5rem_1fr_auto], мобайл — колонка.
    final card = Container(
      padding: const EdgeInsets.all(12), // p-3
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // rounded-lg
        color: th.bgCard, // bg-card
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center, // items-center
              children: [
                SizedBox(
                  width: 80, // 5rem
                  child: AspectRatio(aspectRatio: 3 / 4, child: poster),
                ),
                const SizedBox(width: 16), // gap-4
                Expanded(child: info),
                const SizedBox(width: 16),
                controls,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // w-20 (80px) постер на мобайле, aspect 3/4.
                SizedBox(
                  width: 80,
                  child: AspectRatio(aspectRatio: 3 / 4, child: poster),
                ),
                const SizedBox(height: 16), // gap-4
                info,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: controls),
              ],
            ),
    );

    return card;
  }
}

/// Кнопка ±: w-9, hover bg-panel/text-ink.
class _StepperButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final TsundokuTheme th;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.label,
    required this.th,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label, // aria-label card.decrement/increment
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 36, // w-9
            height: 36,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              color: _hovered
                  ? widget.th.bgSurface // hover:bg-panel
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered
                  ? widget.th.textPrimary // hover:text-ink
                  : widget.th.textMuted, // text-muted
            ),
          ),
        ),
      ),
    );
  }
}
