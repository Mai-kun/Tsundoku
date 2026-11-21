/// 1:1 port of `mediatracker-ui/src/widgets/media-card/MovieCard.svelte`.
///
/// Карточка фильма: подзаголовок — режиссёр (или types.movie); hover-степпер
/// 0/1 — переключение просмотрено/не-просмотрено через createCardStatus
/// (film has no episode/page counter: watched is a single 0/1 toggle).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/change-status/status_controller.dart';
import '../../shared/i18n/index.dart';
import '../../shared/types/enums.dart';
import 'base_card.dart';
import 'card_progress_controls.dart';
import 'card_title_block.dart';
import 'card_types.dart';

class MovieCard extends ConsumerStatefulWidget {
  final MediaCardProps props;

  const MovieCard({super.key, required this.props});

  @override
  ConsumerState<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends ConsumerState<MovieCard> {
  CardStatusState? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status != null) return;
    _status = createCardStatus(CardStatusOptions(
      getItem: () => widget.props.item,
      getOnStatusChange: () => widget.props.onStatusChange,
      getOnProgressCommitted: () =>
          widget.props.onProgressCommitted ?? () {},
      ref: ProviderScope.containerOf(context),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final item = widget.props.item;

    /* A film has no episode/page counter: watched is a single 0/1 toggle. */
    final watched = item.status == MediaStatus.completed;

    Future<void> changeStatus(MediaStatus next) =>
        _status!.changeStatus(next);

    void toggleWatched(int delta) {
      if ((delta > 0) == watched) return;
      // void status.changeStatus(...) — fire-and-forget 1-в-1.
      changeStatus(delta > 0 ? MediaStatus.completed : MediaStatus.planned);
    }

    return BaseCard(
      props: widget.props,
      hover: widget.props.showProgress
          ? CardProgressControls(
              text: watched ? '1 / 1' : '0 / 1',
              onStep: toggleWatched,
              decrementDisabled: !watched,
              incrementDisabled: watched,
            )
          : null,
      children: CardTitleBlock(
        title: item.title,
        subtitle: (item.director?.trim().isNotEmpty ?? false)
            ? item.director!.trim()
            : t.tr('types.movie'),
      ),
    );
  }
}
