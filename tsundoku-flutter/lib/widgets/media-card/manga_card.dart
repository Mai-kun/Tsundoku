/// 1:1 port of `mediatracker-ui/src/widgets/media-card/MangaCard.svelte`.
///
/// Манга-карточка: подзаголовок автор → mangaFormat → types.manga; hover-
/// степпер глав из канонического totalChapters (то же поле, что у
/// «Характеристик»); неизвестный total → «—» вместо вводящего в заблуждение 0.
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

class MangaCard extends ConsumerStatefulWidget {
  final MediaCardProps props;

  const MangaCard({super.key, required this.props});

  @override
  ConsumerState<MangaCard> createState() => _MangaCardState();
}

class _MangaCardState extends ConsumerState<MangaCard> {
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

    // Same canonical `totalChapters` the detail screen reads, so the card and
    // "Характеристики" can never disagree.
    final totalChapters =
        (item.totalChapters != null && item.totalChapters! > 0)
            ? item.totalChapters
            : null;
    final subtitle = (item.author?.trim().isNotEmpty ?? false)
        ? item.author!.trim()
        : (item.mangaFormat?.trim().isNotEmpty ?? false)
            ? item.mangaFormat!.trim()
            : t.tr('types.manga');

    return BaseCard(
      props: widget.props,
      hover: widget.props.showProgress
          ? CardProgressControls(
              text: t.tf(
                  'card.chapters', [_progress!.value, totalChapters ?? 0]),
              onStep: _progress!.step,
              decrementDisabled: _progress!.value <= 0,
              error: _progress!.error,
            )
          : null,
      children: CardTitleBlock(title: item.title, subtitle: subtitle),
    );
  }
}
