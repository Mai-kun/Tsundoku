/// 1:1 port of `mediatracker-ui/src/widgets/media-card/BookCard.svelte`.
///
/// Книжная карточка: подзаголовок (автор или формат ранобэ), hover-степпер
/// глав/страниц через createCardProgress (оптимистичный дебаунс + промоушен-
/// тост реальным shower'ом, решение #15).
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

class BookCard extends ConsumerStatefulWidget {
  final MediaCardProps props;

  const BookCard({super.key, required this.props});

  @override
  ConsumerState<BookCard> createState() => _BookCardState();
}

class _BookCardState extends ConsumerState<BookCard> {
  /// Контроллер — один на инстанс карточки; аксессоры читают СВЕЖИЙ
  /// widget.props.item (1-в-1 с Svelte-аксессорами getItem()).
  CardProgressState? _progress;

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Контроллер — один на инстанс карточки; createCardProgress нуждается в
    // container'е → создаём в didChangeDependencies (инициализация ленивая,
    // аксессоры читают СВЕЖИЙ widget.props.item — 1-в-1 с Svelte).
    if (_progress != null) return;
    _progress = CardProgressState(CardProgressOptions(
      getItem: () => widget.props.item,
      getOnProgress: () => widget.props.onProgress,
      getOnProgressCommitted: () =>
          widget.props.onProgressCommitted ?? () {},
      getOnStatusChange: () => widget.props.onStatusChange,
      showPromotionToast: (spec) => showStatusPromotionToast(ref, spec),
      ref: ProviderScope.containerOf(context),
      // Svelte-карточка реактивна на $state value/error; здесь — хук.
      onChange: _onControllerChanged,
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

    final isNovel =
        item.format == 'light_novel' || item.format == 'web_novel';
    final value = _progress!.value;
    final progressText = isNovel
        ? t.tf('card.chapters', [value, item.totalChapters ?? 0])
        : t.tf('card.pages', [value, item.totalPages ?? 0]);

    return BaseCard(
      props: widget.props,
      hover: widget.props.showProgress
          ? CardProgressControls(
              text: progressText,
              onStep: _progress!.step,
              decrementDisabled: value <= 0,
              error: _progress!.error,
            )
          : null,
      // Пассивный слой: заголовок + подзаголовок.
      children: CardTitleBlock(
        title: item.title,
        subtitle: item.author?.isNotEmpty ?? false
            ? item.author!
            : isNovel
                ? item.format == 'web_novel'
                    ? t.tr('detail.mangaFormats.web_novel')
                    : t.tr('detail.mangaFormats.light_novel')
                : t.tr('types.book'),
      ),
    );
  }
}
