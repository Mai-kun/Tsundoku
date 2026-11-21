/// 1:1 port of `mediatracker-ui/src/widgets/media-grid/MediaGrid.svelte`.
///
/// Сетка медиа-карточек. JS-виртуализатор TanStack заменён нативными слайверами
/// (⏭️ virtualGrid: SliverGrid сам держит окно монтирования — поведение окна
/// удаления проверяется golden-ами). Возвращает СПИСОК СЛАЙВЕРОВ: страница
/// (Phase 3) собирает секции в один CustomScrollView — эквивалент общего
/// #main-scroll; scrollMargin/gridLayoutVersion в нативной схеме не нужны.
/// Для standalone-использования — [MediaGridView] (shrinkWrap-обёртка).
///
/// Состояния 1-в-1: loading/empty placeholder (min-h-60), error-box с Retry,
/// empty-box (Inbox + library.emptyTitle/emptyHint); карточка с
/// timeHint (getTimeHint || evaluateTimeFit) и опциональной кнопкой
/// onRemoveFromList (X, top-right).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../entities/media/model/time_budget.dart';
import '../../shared/api/api.dart';
import '../../shared/i18n/index.dart';
import '../../shared/theme/tsundoku_tokens.dart';
import '../../shared/types/enums.dart' show MediaStatus;
import '../../shared/types/models.dart';
import '../../shared/utils/ui_settings.dart';
import '../media-card/card_types.dart';
import '../media-card/media_card.dart';

/// Breakpoint-таблица virtualGrid.ts (⏭️ портирована сюда: MediaGrid — её
/// единственный потребитель).
/// 6 cards per row on 2xl / desktop (enlarged card width ~190-220px).
int columnsForWidth(double viewportWidth) {
  if (viewportWidth < 640) return 2;
  if (viewportWidth < 1024) return 3;
  if (viewportWidth < 1280) return 4;
  if (viewportWidth < 1536) return 5;
  return 6;
}

/// Ниже этого количества карточек плоская сетка дешевле механизма
/// виртуализации. В Dart SliverGrid виртуален всегда — лимит ни на что не
/// влияет (решение #37), оставлен константой для 1-в-1 документации.
const int flatLimit = 15;

const double rowGap = 16; // matches gap-4

/// MediaGrid-слайверы: [loading/error/empty-боксы] + [SliverGrid].
class MediaGrid extends ConsumerWidget {
  final List<MediaItem> items;
  final TimeBudgetMinutes? timeBudget;
  final CardTimeHint? Function(MediaItem item)? getTimeHint;
  final bool showProgress;
  final bool loading;
  final bool isInitialLoading;
  final Object? error;
  final VoidCallback? onRetry;
  final void Function(MediaItem item)? onOpen;
  final Future<void> Function(String id, int currentProgress)? onProgress;
  final VoidCallback? onProgressCommitted;
  final void Function(MediaItem item, MediaStatus newStatus)? onStatusChange;
  final Future<void> Function(MediaItem item)? onDelete;
  final void Function(MediaItem item)? onEdit;
  final FutureOr<void> Function(MediaItem item, int newWatched)? onEpisodeStep;
  final Future<void> Function(MediaItem item)? onRemoveFromList;

  /// Render every item flat: multi-section dashboards must never collapse
  /// into a virtual void. В Dart слайверы в общем скроллере виртуальны сами —
  /// флаг сохранён для 1-в-1 контракта, поведения не меняет.
  final bool forceFlat;

  const MediaGrid({
    super.key,
    required this.items,
    this.timeBudget,
    this.getTimeHint,
    this.showProgress = true,
    this.loading = false,
    this.isInitialLoading = false,
    this.error,
    this.onRetry,
    this.onOpen,
    this.onProgress,
    this.onProgressCommitted,
    this.onStatusChange,
    this.onDelete,
    this.onEdit,
    this.onEpisodeStep,
    this.onRemoveFromList,
    this.forceFlat = false,
  });

  CardTimeHint? _timeHint(WidgetRef ref, MediaItem item, Locale locale) {
    final hint = getTimeHint?.call(item);
    if (hint != null) return hint;
    final budget = timeBudget;
    if (budget == null) return null;
    final settings = ref.read(uiSettingsProvider);
    final res = evaluateTimeFit(
      item,
      budget,
      settings.bookPageMinutes,
      settings.mangaChapterMinutes,
      locale: locale.wire,
    );
    return CardTimeHint(
        label: res.sessionLabel, canFinishNow: res.canFinishNow);
  }

  Widget _card(WidgetRef ref, MediaItem item, I18nDictionary t) {
    final locale = ref.watch(i18nProvider);
    final timeHint = _timeHint(ref, item, locale);

    final card = MediaCard(props: MediaCardProps(
      item: item,
      timeHint: timeHint,
      showProgress: showProgress,
      onOpen: onOpen,
      onProgress: onProgress,
      onProgressCommitted: onProgressCommitted,
      onStatusChange: onStatusChange,
      onDelete: onDelete,
      onEdit: onEdit,
      onEpisodeStep: onEpisodeStep,
    ));

    final removeFromList = onRemoveFromList;
    if (removeFromList == null) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: 8, // top-2
          right: 8, // right-2
          child: _RemoveFromListButton(
            semanticLabel: t.tr('views.listRemoveItem'),
            onPressed: () => unawaited(removeFromList(item)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(i18nProvider);

    final slivers = <Widget>[];

    if ((loading || isInitialLoading) && items.isEmpty) {
      // Clean placeholder: a quiet empty box holds the layout without pulsing
      // skeleton cards, which strobed on every category switch.
      slivers.add(const SliverToBoxAdapter(
        child: SizedBox(height: 240, key: ValueKey('grid-loading')), // min-h-60
      ));
      slivers.add(SliverToBoxAdapter(
        // sr-only role="status"
        child: Semantics(
          liveRegion: true,
          child: Visibility(
            visible: false,
            maintainState: true,
            child: Text(t.tr('common.loading')),
          ),
        ),
      ));
      return SliverMainAxisGroup(slivers: slivers);
    }

    if (error != null && items.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.only(top: 16, bottom: 16),
          constraints: const BoxConstraints(minHeight: 288), // min-h-72
          decoration: BoxDecoration(
            color: const Color(0x0DF43F5E), // bg-rose-400/5
            borderRadius: BorderRadius.circular(8), // rounded-lg
          ),
          padding: const EdgeInsets.all(24), // p-6
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                // role="alert"
                errorMessage(error!, locale),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14, // text-sm
                  color: Color(0xFFFECDD3), // text-rose-200
                ),
              ),
              const SizedBox(height: 12), // gap-3
              Center(
                child: _RetryButton(
                  label: t.tr('common.retry'),
                  onRetry: onRetry ?? () {},
                ),
              ),
            ],
          ),
        ),
      ));
      return SliverMainAxisGroup(slivers: slivers);
    }

    if (items.isEmpty && !loading && !isInitialLoading) {
      slivers.add(SliverToBoxAdapter(
        child: Container(
          constraints: const BoxConstraints(minHeight: 288), // min-h-72
          decoration: BoxDecoration(
            color: TsundokuTheme.of(context).bgSurface, // bg-surface
            borderRadius: BorderRadius.circular(8), // rounded-lg
          ),
          padding: const EdgeInsets.all(24), // p-6
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48, // h-12 w-12
                height: 48,
                decoration: BoxDecoration(
                  color: TsundokuTheme.of(context).bgCard, // bg-card
                  borderRadius: BorderRadius.circular(8), // rounded-lg
                ),
                child: Icon(
                  LucideIcons.inbox, // Inbox size={22}
                  size: 22,
                  color: Colors.white.withAlpha(120), // text-muted
                ),
              ),
              const SizedBox(height: 12), // gap-3
              Text(
                t.tr('library.emptyTitle'),
                style: TextStyle(
                  fontWeight: FontWeight.w600, // font-semibold
                  color: TsundokuTheme.of(context).textPrimary, // text-ink
                ),
              ),
              const SizedBox(height: 4), // mt-1
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
                child: Text(
                  t.tr('library.emptyHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14, // text-sm
                    color: Colors.white.withAlpha(120), // text-muted
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      return SliverMainAxisGroup(slivers: slivers);
    }

    // Сетка: колонки из ширины ОКНА (1-в-1 с window.innerWidth — Tailwind
    // breakpoint-классы реагируют на вьюпорт, не на контейнер).
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final columnsCount = columnsForWidth(viewportWidth);

    slivers.add(SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnsCount,
        crossAxisSpacing: rowGap,
        mainAxisSpacing: rowGap,
        childAspectRatio: 2 / 3, // aspect-[2/3]: титул живёт на постере
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return _card(ref, item, ref.watch(tProvider));
        },
        childCount: items.length,
        // Ключи карточек 1-в-1 с {#each items (item.id)} — keyed each.
        findChildIndexCallback: (key) {
          final valueKey = key as ValueKey<String>?;
          if (valueKey == null) return null;
          final id = valueKey.value;
          final index = items.indexWhere((i) => i.id == id);
          return index < 0 ? null : index;
        },
      ),
    ));

    return SliverMainAxisGroup(slivers: slivers);
  }
}

/// Кнопка X «убрать из списка» (onRemoveFromList): absolute top-2 right-2,
/// h-8 w-8 rounded-lg border-white/10 bg-black/75, hover:bg-rose-500.
class _RemoveFromListButton extends StatefulWidget {
  final String semanticLabel;
  final VoidCallback onPressed;

  const _RemoveFromListButton({
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  State<_RemoveFromListButton> createState() => _RemoveFromListButtonState();
}

class _RemoveFromListButtonState extends State<_RemoveFromListButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.semanticLabel, // title + aria-label
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 32, // h-8 w-8
            height: 32,
            padding: const EdgeInsets.all(8.5), // X size={15} в 32px
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFFF43F5E) // hover:bg-rose-500
                  : const Color(0xBF000000), // bg-black/75
              borderRadius: BorderRadius.circular(8), // rounded-lg
              border: Border.all(color: Colors.white.withAlpha(26)), // border-white/10
            ),
            child: const Icon(LucideIcons.x, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Кнопка Retry (error-box): bg-accent hover:bg-accent-hover, RefreshCw 15px.
class _RetryButton extends StatefulWidget {
  final String label;
  final VoidCallback onRetry;

  const _RetryButton({required this.label, required this.onRetry});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final th = TsundokuTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onRetry,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // px-4 py-2
          decoration: BoxDecoration(
            color: _hovered ? th.accentHover : th.accent, // bg-accent(-hover)
            borderRadius: BorderRadius.circular(6), // rounded-md
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.rotateCw, // RefreshCw size={15}
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: 8), // gap-2
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 14, // text-sm
                  fontWeight: FontWeight.w500, // font-medium
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

/// Standalone-обёртка для тестов/единичного использования: shrinkWrap-
/// скроллер с MediaGrid-слайверами. В рабочих вью (Phase 3) слайверы
/// встраиваются в общий CustomScrollView.
class MediaGridView extends ConsumerWidget {
  final MediaGrid grid;

  const MediaGridView({super.key, required this.grid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [grid.build(context, ref)],
    );
  }
}
