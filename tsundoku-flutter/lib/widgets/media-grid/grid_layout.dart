/// 1:1 port of `mediatracker-ui/src/widgets/media-grid/gridLayout.svelte.ts`.
///
/// Cross-grid layout invalidation. Grids that share the #main-scroll scroller
/// must recompute their scrollMargin whenever any sibling section above them
/// changes its rendered footprint. A module-level version counter carries
/// that signal without a ResizeObserver on virtualizer-driven heights: every
/// MediaGrid bumps the version when its row count, corrected row height, or
/// presence on the page changes, and each grid's scrollMargin effect tracks
/// it. Margin/transform writes never feed back into row counts or heights, so
/// this cannot loop (unlike the old observers on the virtual container and
/// page content, which produced "ResizeObserver loop limit exceeded").
///
/// Svelte `let version = $state(0)` → Riverpod Notifier\<int\> (глобальный
/// стор, отслеживается watch'ем — аналог эффект-трекинга).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `export function gridLayoutVersion(): number`.
final gridLayoutVersionProvider =
    NotifierProvider<GridLayoutVersionController, int>(
        GridLayoutVersionController.new);

class GridLayoutVersionController extends Notifier<int> {
  @override
  int build() => 0;

  /// `bumpGridLayout()`: untrack-чтение не нужно — Notifier.bump пишет state
  /// напрямую (эффекты Riverpod не подписываются на собственные записи).
  void bump() => state = state + 1;
}

/// `export function bumpGridLayout(): void`.
void bumpGridLayout(dynamic ref) =>
    ref.read(gridLayoutVersionProvider.notifier).bump();
