<script lang="ts">
  import { type Snippet } from "svelte";
  import { ChevronUp, type FileText } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import { minWindowSize, type WorkspaceRect, type WorkspaceWindowId } from "./workspaceLayout";

  /** Hard viewport bounds (mirrors workspaceLayout): sides 16, top toolbar band 64, bottom 16. */
  const SIDE_MARGIN = 16;
  const TOP_BAR = 64;
  const BOTTOM_MARGIN = 16;

  /**
   * One floating window of the spatial edit canvas. Draggable by its header, resizable by the
   * bottom-right grip, z-stacked by the parent, collapsible to a bare title bar. Pointer deltas
   * are coalesced through one rAF and applied as `translate3d`, so dragging stays GPU-cheap on
   * high-refresh displays. Text selection and inputs in the body are untouched: the drag surfaces
   * are the header and the grip only.
   */
  interface Props {
    id: WorkspaceWindowId;
    title: string;
    icon: typeof FileText;
    count?: number;
    rect: WorkspaceRect;
    z: number;
    highlighted?: boolean;
    /** Collapsed windows render as a bare title bar; threads follow the shrunk shape. */
    collapsed?: boolean;
    onFront: () => void;
    onHoverChange: (hovered: boolean) => void;
    onDragStateChange: (dragging: boolean) => void;
    onSettled: () => void;
    children: Snippet;
  }

  let {
    id,
    title,
    icon: Icon,
    count,
    rect = $bindable(),
    z,
    highlighted = false,
    collapsed = $bindable(false),
    onFront,
    onHoverChange,
    onDragStateChange,
    onSettled,
    children,
  }: Props = $props();

  // Height of a collapsed window: just the title bar.
  const HEADER_H = 40;
  /** Collapse/expand animates the container height; live resize must stay instant. */
  const HEIGHT_TRANSITION = "height 220ms cubic-bezier(0.16, 1, 0.3, 1)";

  let pending: { x?: number; y?: number; w?: number; h?: number } | null = null;
  let rafId = 0;
  let resizing = $state(false);
  let drag: null | {
    mode: "move" | "resize";
    pointerId: number;
    startX: number;
    startY: number;
    origin: { x: number; y: number; w: number; h: number };
  } = null;

  function queueApply() {
    if (rafId) return;
    rafId = requestAnimationFrame(() => {
      rafId = 0;
      const next = pending;
      pending = null;
      if (!next) return;
      if (next.x !== undefined) rect.x = next.x;
      if (next.y !== undefined) rect.y = next.y;
      if (next.w !== undefined) rect.w = next.w;
      if (next.h !== undefined) rect.h = next.h;
    });
  }

  // Listeners live on `window` for the duration of a drag: the parent reorders nothing, but the
  // editor does mutate z-order/classes mid-drag, and pointer capture silently dies when a node
  // is re-inserted — window-level listeners keep the drag alive no matter what re-renders.
  function startDrag(event: PointerEvent) {
    if (drag) return;
    onFront();
    onDragStateChange(true);
    drag = {
      mode: "move",
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      origin: { x: rect.x, y: rect.y, w: rect.w, h: rect.h },
    };
    window.addEventListener("pointermove", handleMove);
    window.addEventListener("pointerup", endDrag);
    window.addEventListener("pointercancel", endDrag);
  }

  function startResize(event: PointerEvent) {
    if (drag) return;
    event.stopPropagation();
    onFront();
    onDragStateChange(true);
    resizing = true;
    drag = {
      mode: "resize",
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      origin: { x: rect.x, y: rect.y, w: rect.w, h: rect.h },
    };
    window.addEventListener("pointermove", handleMove);
    window.addEventListener("pointerup", endDrag);
    window.addEventListener("pointercancel", endDrag);
  }

  function handleMove(event: PointerEvent) {
    if (!drag || event.pointerId !== drag.pointerId) return;
    const min = minWindowSize(id);
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    if (drag.mode === "move") {
      // Hard viewport bounds, enforced live: the window may never leave the visible band.
      const x = Math.min(
        Math.max(drag.origin.x + (event.clientX - drag.startX), SIDE_MARGIN),
        Math.max(vw - SIDE_MARGIN - rect.w, SIDE_MARGIN),
      );
      const y = Math.min(
        Math.max(drag.origin.y + (event.clientY - drag.startY), TOP_BAR),
        Math.max(vh - BOTTOM_MARGIN - rect.h, TOP_BAR),
      );
      pending = { x, y };
    } else {
      pending = {
        w: Math.max(min.w, Math.min(drag.origin.w + (event.clientX - drag.startX), vw - rect.x - SIDE_MARGIN)),
        h: Math.max(min.h, Math.min(drag.origin.h + (event.clientY - drag.startY), vh - rect.y - BOTTOM_MARGIN)),
      };
    }
    queueApply();
  }

  function finishDrag() {
    if (!drag) return;
    drag = null;
    window.removeEventListener("pointermove", handleMove);
    window.removeEventListener("pointerup", endDrag);
    window.removeEventListener("pointercancel", endDrag);
    // Flush the last coalesced frame synchronously so persistence sees the final geometry.
    if (rafId) {
      cancelAnimationFrame(rafId);
      rafId = 0;
    }
    const next = pending;
    pending = null;
    if (next) {
      if (next.x !== undefined) rect.x = next.x;
      if (next.y !== undefined) rect.y = next.y;
      if (next.w !== undefined) rect.w = next.w;
      if (next.h !== undefined) rect.h = next.h;
    }
    onDragStateChange(false);
    onSettled();
    resizing = false;
  }

  function endDrag(event: PointerEvent) {
    if (!drag || event.pointerId !== drag.pointerId) return;
    finishDrag();
  }

  // Losing the window mid-drag (alt-tab, OS gesture) must never leave a stuck grab cursor or a
  // half-applied frame — force-finish on blur.
  function handleWindowBlur() {
    finishDrag();
  }
</script>

<svelte:window onblur={handleWindowBlur} />

<div
  class="absolute top-0 left-0 will-change-transform"
  style:transform={`translate3d(${rect.x}px, ${rect.y}px, 0)`}
  style:width={`${rect.w}px`}
  style:height={`${collapsed ? HEADER_H : rect.h}px`}
  style:transition={resizing ? "none" : HEIGHT_TRANSITION}
  style:z-index={z}
>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <section
    class="flex h-full flex-col overflow-hidden rounded-xl border bg-[#12151c]/95 shadow-2xl shadow-black/50 {highlighted
      ? 'border-accent/60'
      : 'border-white/[0.08]'}"
    onpointerdown={onFront}
    onpointerenter={() => onHoverChange(true)}
    onpointerleave={() => (drag ? null : onHoverChange(false))}
  >
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <header
      class="flex h-10 shrink-0 touch-none cursor-grab items-center gap-2 border-b border-white/[0.06] bg-white/[0.03] px-3 select-none active:cursor-grabbing"
      onpointerdown={startDrag}
      onpointermove={handleMove}
      onpointerup={endDrag}
      onpointercancel={endDrag}
    >
      <span class="text-accent-soft grid size-6 shrink-0 place-items-center rounded-md bg-white/[0.05]">
        <Icon size={15} aria-hidden="true"></Icon>
      </span>
      <h3 class="text-ink min-w-0 flex-1 truncate text-xs font-bold tracking-[0.14em] uppercase">
        {title}
      </h3>
      {#if typeof count === "number" && count > 0}
        <span class="rounded-full bg-white/[0.06] px-2 py-0.5 text-[11px] font-semibold text-slate-300">
          {count}
        </span>
      {/if}
      <button
        type="button"
        class="text-muted hover:text-ink grid size-6 shrink-0 place-items-center rounded-md transition"
        aria-label={collapsed ? i18n.t.common.expand : i18n.t.common.collapse}
        title={collapsed ? i18n.t.common.expand : i18n.t.common.collapse}
        onpointerdown={(event) => event.stopPropagation()}
        onclick={() => (collapsed = !collapsed)}
      >
        <span
          class="grid place-items-center transition-transform duration-200 {collapsed
            ? 'rotate-180'
            : ''}"
        >
          <ChevronUp size={14} aria-hidden="true" />
        </span>
      </button>
    </header>
    <!-- The body always stays mounted: collapse fades it out while the container height
         animates shut, so the motion is smooth in both directions. -->
    <div
      class="thin-scroll min-h-0 flex-1 overflow-y-auto p-3 transition-opacity duration-200 {collapsed
        ? 'pointer-events-none opacity-0'
        : 'opacity-100'}"
      inert={collapsed}
    >
      {@render children()}
    </div>
    {#if !collapsed}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="absolute right-0 bottom-0 z-10 size-5 cursor-nwse-resize touch-none"
        onpointerdown={startResize}
        onpointermove={handleMove}
        onpointerup={endDrag}
        onpointercancel={endDrag}
      >
        <svg viewBox="0 0 20 20" class="text-muted/60 size-full" aria-hidden="true">
          <path
            d="M19 7 L7 19 M19 12 L12 19 M19 17 L17 19"
            stroke="currentColor"
            stroke-width="1.5"
            fill="none"
          />
        </svg>
      </div>
    {/if}
  </section>
</div>
