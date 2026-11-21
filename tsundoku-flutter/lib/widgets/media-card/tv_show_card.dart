/// 1:1 port of `mediatracker-ui/src/widgets/media-card/TvShowCard.svelte`.
///
/// Карточка сериала: оптимистичный локальный счётчик эпизодов
/// (reconcileProgress держит pending-шаг против устаревших refetch'ей),
/// hover-степпер через stepSeriesEpisodes (контроллер владеет статусным
/// правилом 0→1 ⇒ InProgress); без onEpisodeStep — hover с MediaStatusBadge.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/media_labels.dart';
import '../../entities/media/ui/media_status_badge.dart';
import '../../features/update-progress/optimistic_progress.dart';
import '../../features/update-progress/series_progress_controller.dart';
import '../../shared/i18n/index.dart';
import 'base_card.dart';
import 'card_progress_controls.dart';
import 'card_title_block.dart';
import 'card_types.dart';

class TvShowCard extends ConsumerStatefulWidget {
  final MediaCardProps props;

  const TvShowCard({super.key, required this.props});

  @override
  ConsumerState<TvShowCard> createState() => _TvShowCardState();
}

class _TvShowCardState extends ConsumerState<TvShowCard> {
  /// Optimistic counter: the real commit runs a detail fetch + season POST +
  /// refetch and can take seconds, so the card renders from a local copy that
  /// steps instantly on click and resyncs from props whenever the view sends
  /// refreshed data.
  int _localEpisodesWatched = 0;
  String? _trackedItemId;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final props = widget.props;
    final item = props.item;

    // $effect: localEpisodesWatched = reconcileProgress(item.id,
    // item.totalEpisodesWatched ?? 0) — пересинхронизация на новом item.
    if (_trackedItemId != item.id) {
      _trackedItemId = item.id;
      _localEpisodesWatched = reconcileProgress(
          ProviderScope.containerOf(context),
          item.id,
          item.totalEpisodesWatched ?? 0);
    }

    // The card and the detail screen read the same counters; the guard only
    // covers a show whose seasons have not been written yet.
    final totalEpisodes =
        (item.totalEpisodesCount != null && item.totalEpisodesCount! > 0)
            ? item.totalEpisodesCount
            : null;

    final subtitle = (item.seasonsCount != null && item.seasonsCount! > 0)
        ? '${cardTypeLabel(item, t)} • ${item.seasonsCount}'
        : cardTypeLabel(item, t);

    /* A single-episode title still needs the stepper: 0/1 -> 1/1 is a valid
       step. */
    final showStepper = props.onEpisodeStep != null;

    final episodeText = totalEpisodes != null
        ? '$_localEpisodesWatched / $totalEpisodes'
        : '$_localEpisodesWatched';

    final atLastEpisode =
        totalEpisodes != null && _localEpisodesWatched >= totalEpisodes;

    Future<void> stepEpisode(int delta) async {
      final onEpisodeStep = props.onEpisodeStep;
      if (onEpisodeStep == null) return;
      // Instant local counter; the controller owns the raw item write, the
      // shared optimistic store, the detail-cache patch and the debounced PUT.
      setState(() {
        final next = _localEpisodesWatched + delta;
        _localEpisodesWatched = next < 0 ? 0 : next;
      });
      ref.read(seriesProgressControllerProvider).stepSeriesEpisodes(
            item,
            delta,
            onCommitted: (id) => props.onProgressCommitted?.call(),
          );
      // Absolute value, not a delta: the controller has already applied the
      // step to item, so a parent that added delta again would double-count.
      await onEpisodeStep(item, _localEpisodesWatched);
    }

    return BaseCard(
      props: props,
      hover: showStepper
          ? CardProgressControls(
              text: episodeText,
              onStep: (delta) => unawaited(stepEpisode(delta)),
              decrementDisabled: _localEpisodesWatched <= 0,
              incrementDisabled: atLastEpisode,
            )
          : MediaStatusBadge(
              id: 'status-hover-${item.id}',
              status: item.status,
              // Hover stepper: the series controller owns the status rule
              // (0 → 1 ⇒ InProgress).
              onSelect: (next) =>
                  props.onStatusChange?.call(item, next),
            ),
      children: CardTitleBlock(title: item.title, subtitle: subtitle),
    );
  }
}
