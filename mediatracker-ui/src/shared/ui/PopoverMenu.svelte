<script lang="ts">
  import { Check } from "$shared/ui/Icons.svelte";
  import type { Snippet } from "svelte";

  export interface PopoverOption<T> {
    value: T;
    label: string;
  }

  interface Props<T> {
    id: string;
    options: readonly PopoverOption<T>[];
    selected: T;
    onSelect: (value: T) => void;
    trigger: Snippet<
      [
        ctx: {
          popoverTargetId: string;
          anchorName: string;
          /** True while the menu is open. */
          isOpen: boolean;
        },
      ]
    >;
    placement?: "bottom" | "bottom-start" | "bottom-end" | "top";
    class?: string;
    optionClass?: string;
    /** Stretch the menu to the trigger's width. */
    matchTriggerWidth?: boolean;
    /** Open on hover and close after `closeDelay` ms. */
    openOnHover?: boolean;
    /** Replaces the default label row — used by icon-only menus (sort, grouping). */
    renderOption?: Snippet<[ctx: { option: PopoverOption<unknown>; selected: boolean }]>;
    closeDelay?: number;
    label: string;
    footer?: Snippet<[ctx: { close: () => void }]>;
  }

  let {
    id,
    options,
    selected,
    onSelect,
    trigger,
    placement = "bottom-start",
    class: className = "",
    optionClass = "",
    matchTriggerWidth = false,
    openOnHover = false,
    renderOption,
    closeDelay = 180,
    label,
    footer,
  }: Props<unknown> = $props();

  const popoverId = $derived(`popover-${id}`);
  const anchorName = $derived(`--${popoverId}`);

  const EDGE = 8;

  let popoverEl = $state<HTMLDivElement | null>(null);
  let triggerWrapper = $state<HTMLDivElement | null>(null);
  let isOpen = $state(false);
  /* Popover coordinates in viewport space. Avoids position-anchor breakage with virtualized lists. */
  let explicitStyle = $state("");

  function placePopover() {
    const el = popoverEl;
    if (!el) return;

    const triggerEl =
      triggerWrapper?.querySelector<HTMLElement>("[popovertarget]") ??
      document.querySelector<HTMLElement>(`[popovertarget="${CSS.escape(popoverId)}"]`);
    if (!triggerEl) return;

    const rect = triggerEl.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return;

    const width = el.offsetWidth || 144;
    const height = el.offsetHeight || 220;

    let left =
      placement === "bottom-end"
        ? rect.right - width
        : placement === "bottom"
          ? rect.left + rect.width / 2 - width / 2
          : rect.left;
    left = Math.min(Math.max(EDGE, left), window.innerWidth - width - EDGE);

    let top = rect.bottom + 8;
    if (
      placement === "top" ||
      (top + height > window.innerHeight - EDGE && rect.top - height - 8 > EDGE)
    ) {
      top = rect.top - height - 8;
    } else if (top + height > window.innerHeight - EDGE) {
      top = window.innerHeight - height - EDGE;
    }
    top = Math.max(EDGE, top);

    const newStyle = `left: ${Math.round(left)}px; top: ${Math.round(top)}px; position: fixed; margin: 0;${
      matchTriggerWidth ? ` width: ${Math.round(rect.width)}px;` : ""
    }`;

    explicitStyle = newStyle;
    el.style.position = "fixed";
    el.style.left = `${Math.round(left)}px`;
    el.style.top = `${Math.round(top)}px`;
    el.style.margin = "0";
    if (matchTriggerWidth) {
      el.style.width = `${Math.round(rect.width)}px`;
    }
  }

  function handleBeforeToggle(event: ToggleEvent) {
    if (event.newState === "open") {
      isOpen = true;
      placePopover();
    } else {
      isOpen = false;
    }
  }

  function handleToggle(event: ToggleEvent) {
    isOpen = event.newState === "open";
    if (isOpen) placePopover();
  }

  /* Keep the menu glued to the trigger while the page scrolls or resizes. */
  $effect(() => {
    if (!isOpen) return;
    const reposition = () => placePopover();
    window.addEventListener("scroll", reposition, true);
    window.addEventListener("resize", reposition);
    return () => {
      window.removeEventListener("scroll", reposition, true);
      window.removeEventListener("resize", reposition);
    };
  });

  const styleAttr = $derived(explicitStyle || `position: fixed; inset: auto; margin: 0;`);

  /* Cards listen for clicks on the whole <article>; without isolation a click on
     the trigger or the menu also opens the detail view. */
  function isolate(event: Event) {
    event.stopPropagation();
  }

  function select(value: unknown) {
    onSelect(value);
  }

  /* Hover mode: the cursor has to cross the gap between trigger and menu, so the
     close is deferred and cancelled again as soon as the menu is entered. */
  let closeTimer: ReturnType<typeof setTimeout> | null = null;

  function cancelPendingClose() {
    if (closeTimer === null) return;
    clearTimeout(closeTimer);
    closeTimer = null;
  }

  function scheduleClose() {
    if (!openOnHover) return;
    if (popoverEl && popoverEl.contains(document.activeElement)) return;
    cancelPendingClose();
    closeTimer = setTimeout(() => {
      closeTimer = null;
      popoverEl?.hidePopover();
    }, closeDelay);
  }

  function openOnEnter() {
    if (!openOnHover) return;
    cancelPendingClose();
    placePopover();
    if (popoverEl && !popoverEl.matches(":popover-open")) {
      popoverEl.showPopover();
    }
  }

  $effect(() => () => cancelPendingClose());
</script>

<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions -->
<div
  bind:this={triggerWrapper}
  class="contents"
  role="presentation"
  onclick={isolate}
  onpointerdown={isolate}
>
  <!-- Hover mode needs a real box to receive enter/leave; `contents` has none. -->
  {#if openOnHover}
    <span
      class="inline-flex"
      role="presentation"
      onpointerenter={openOnEnter}
      onpointerleave={scheduleClose}
    >
      {@render trigger({ popoverTargetId: popoverId, anchorName, isOpen })}
    </span>
  {:else}
    {@render trigger({ popoverTargetId: popoverId, anchorName, isOpen })}
  {/if}
</div>

<!-- A strict rectangle: no decorative arrow/::after, so the menu can never render a stray
     triangle that drifts off the trigger. -->
<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions -->
<div
  id={popoverId}
  bind:this={popoverEl}
  popover="auto"
  role="listbox"
  tabindex="-1"
  aria-label={label}
  class="z-30 w-max min-w-36 rounded-md border border-white/10 bg-[#1c202b] p-1 shadow-2xl outline-none {className}"
  style={styleAttr}
  onbeforetoggle={handleBeforeToggle}
  ontoggle={handleToggle}
  onclick={isolate}
  onpointerdown={isolate}
  onpointerenter={cancelPendingClose}
  onpointerleave={scheduleClose}
>
  {#each options as option (String(option.value))}
    <button
      type="button"
      role="option"
      aria-selected={option.value === selected}
      class="tap hover:text-ink flex w-full items-center justify-between gap-3 rounded-sm px-3 py-2 text-left text-sm transition hover:bg-white/5 {option.value ===
      selected
        ? 'text-accent-soft'
        : 'text-muted'} {optionClass}"
      onclick={() => select(option.value)}
    >
      {#if renderOption}
        {@render renderOption({ option, selected: option.value === selected })}
      {:else}
        <span class="truncate">{option.label}</span>
        {#if option.value === selected}
          <Check size={14} class="text-accent-soft shrink-0" aria-hidden="true" />
        {/if}
      {/if}
    </button>
  {/each}
  {#if footer}
    <div class="mt-1 border-t border-white/10 px-1.5 pt-1.5 pb-1">
      {@render footer({ close: () => popoverEl?.hidePopover() })}
    </div>
  {/if}
</div>
