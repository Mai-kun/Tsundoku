import { untrack } from "svelte";

// Cross-grid layout invalidation. Grids that share the #main-scroll scroller
// must recompute their scrollMargin whenever any sibling section above them
// changes its rendered footprint. A module-level version counter carries that
// signal without a ResizeObserver on virtualizer-driven heights: every
// MediaGrid bumps the version when its row count, corrected row height, or
// presence on the page changes, and each grid's scrollMargin effect tracks it.
// Margin/transform writes never feed back into row counts or heights, so this
// cannot loop (unlike the old observers on the virtual container and page
// content, which produced "ResizeObserver loop limit exceeded").
let version = $state(0);

export function bumpGridLayout(): void {
  // untrack the read: `version++` inside a caller's $effect would otherwise
  // subscribe that effect to the very signal it writes, which Svelte rejects
  // as effect_update_depth_exceeded.
  version = untrack(() => version) + 1;
}

export function gridLayoutVersion(): number {
  return version;
}
