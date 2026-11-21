/// 1:1 port of `mediatracker-ui/src/widgets/media-card/GameCard.svelte`.
///
/// Игровая карточка: подзаголовок — платформа пользователя (или платформа
/// игры), hover-степпер часов через createCardProgress.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/update-progress/progress_controller.dart';
import '../../features/update-progress/status_promotion_toast.dart';
import '../../shared/i18n/index.dart';
import 'base_card.dart';
import 'card_progress_controls.dart';
import 'card_title_block.dart';
import 'card_types.dart';

class GameCard extends ConsumerStatefulWidget {
  final MediaCardProps props;

  const GameCard({super.key, required this.props});

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard> {
  CardProgressState? _progress;

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_progress != null) return;
    _progress = CardProgressState(CardProgressOptions(
      getItem: () => widget.props.item,
      getOnProgress: () => widget.props.onProgress,
      getOnProgressCommitted: () =>
          widget.props.onProgressCommitted ?? () {},
      getOnStatusChange: () => widget.props.onStatusChange,
      showPromotionToast: (spec) => showStatusPromotionToast(ref, spec),
      ref: ProviderScope.containerOf(context),
      onChange: _onControllerChanged, // решение #36
    ));
    _progress!.addChangeListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _progress
      ?..removeChangeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final item = widget.props.item;

    /** Games list every platform shipped on; only the user's pick is meaningful. */
    final userPlatform = item.userPlatform?.trim();
    final platform =
        (userPlatform?.isNotEmpty ?? false) ? userPlatform : item.platform?.trim();

    return BaseCard(
      props: widget.props,
      hover: widget.props.showProgress
          ? CardProgressControls(
              text: t.tf('card.hours', [_progress!.value]),
              onStep: _progress!.step,
              decrementDisabled: _progress!.value <= 0,
              error: _progress!.error,
            )
          : null,
      children: CardTitleBlock(
        title: item.title,
        subtitle: (platform?.isNotEmpty ?? false)
            ? platform!
            : t.tr('types.game'),
      ),
    );
  }
}
