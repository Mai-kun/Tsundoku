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
            [ctx: { popoverTargetId: string; anchorName: string }]
        >;
        placement?: "bottom" | "bottom-start" | "bottom-end" | "top";
        class?: string;
        optionClass?: string;
        /** Stretch the menu to the trigger's width (CSS `anchor-size()`, Chromium 125+). */
        matchTriggerWidth?: boolean;
        /** Open on hover and close after `closeDelay` ms, so the cursor can travel to the options. */
        openOnHover?: boolean;
        /** Replaces the default label row — used by icon-only menus (sort, grouping). */
        renderOption?: Snippet<
            [ctx: { option: PopoverOption<unknown>; selected: boolean }]
        >;
        closeDelay?: number;
        label: string;
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
    }: Props<unknown> = $props();

    const popoverId = $derived(`popover-${id}`);
    const anchorName = $derived(`--${popoverId}`);

    /* Firefox has no CSS anchor positioning (as of 2026), so there the popover has to
     be placed by hand. Chromium/Safari keep the pure-CSS path. */
    const supportsAnchor =
        typeof CSS !== "undefined" && CSS.supports("anchor-name", "--a");

    const GAP = 8;
    const EDGE = 8;

    const placementStyle: Record<string, string> = {
        bottom: "top: calc(anchor(bottom) + 8px); left: anchor(center); translate: -50% 0;",
        "bottom-start": "top: calc(anchor(bottom) + 8px); left: anchor(left);",
        "bottom-end":
            "top: calc(anchor(bottom) + 8px); left: auto; right: anchor(right);",
        top: "bottom: calc(anchor(top) + 8px); top: auto; left: anchor(left);",
    };

    let popoverEl = $state<HTMLDivElement | null>(null);
    let isOpen = $state(false);
    /* Only used on the no-anchor path: `left`/`top` (+ width) in viewport coordinates. */
    let fallbackStyle = $state("");

    function placeFallback() {
        if (supportsAnchor) return;
        const el = popoverEl;
        // The trigger is rendered by the parent snippet, so find it by its popover target.
        const trigger = document.querySelector<HTMLElement>(
            `[popovertarget="${CSS.escape(popoverId)}"]`,
        );
        if (!el || !trigger) return;

        // A closed popover is `display: none`, so measure it off-screen first.
        el.style.display = "block";
        el.style.visibility = "hidden";
        const { width, height } = el.getBoundingClientRect();
        el.style.display = "";
        el.style.visibility = "";

        const rect = trigger.getBoundingClientRect();
        let left =
            placement === "bottom-end"
                ? rect.right - width
                : placement === "bottom"
                  ? rect.left + rect.width / 2 - width / 2
                  : rect.left;
        left = Math.min(Math.max(EDGE, left), window.innerWidth - width - EDGE);

        let top =
            placement === "top" ? rect.top - height - GAP : rect.bottom + GAP;
        // Flip above the trigger only when the menu would leave the viewport.
        if (
            top + height > window.innerHeight - EDGE &&
            rect.top - height - GAP > EDGE
        ) {
            top = rect.top - height - GAP;
        }

        fallbackStyle = `left:${Math.round(left)}px; top:${Math.round(top)}px;${
            matchTriggerWidth ? ` width:${Math.round(rect.width)}px;` : ""
        }`;
    }

    function handleBeforeToggle(event: ToggleEvent) {
        if (event.newState === "open") placeFallback();
    }

    function handleToggle(event: ToggleEvent) {
        isOpen = event.newState === "open";
        if (isOpen) placeFallback();
    }

    /* Keep the hand-placed menu glued to the trigger while the page scrolls or resizes. */
    $effect(() => {
        if (!isOpen || supportsAnchor) return;
        const reposition = () => placeFallback();
        window.addEventListener("scroll", reposition, true);
        window.addEventListener("resize", reposition);
        return () => {
            window.removeEventListener("scroll", reposition, true);
            window.removeEventListener("resize", reposition);
        };
    });

    const styleAttr = $derived(
        supportsAnchor
            ? `position: fixed; inset: auto; margin: 0; position-anchor: ${anchorName};${
                  matchTriggerWidth ? " width: anchor-size(width);" : ""
              } ${placementStyle[placement]}`
            : `position: fixed; inset: auto; margin: 0; ${fallbackStyle}`,
    );

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
        cancelPendingClose();
        closeTimer = setTimeout(() => {
            closeTimer = null;
            popoverEl?.hidePopover();
        }, closeDelay);
    }

    function openOnEnter() {
        if (!openOnHover) return;
        cancelPendingClose();
        if (popoverEl && !popoverEl.matches(":popover-open"))
            popoverEl.showPopover();
    }

    $effect(() => () => cancelPendingClose());
</script>

<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions -->
<div
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
            {@render trigger({ popoverTargetId: popoverId, anchorName })}
        </span>
    {:else}
        {@render trigger({ popoverTargetId: popoverId, anchorName })}
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
            class="tap flex w-full items-center justify-between gap-3 rounded-sm px-3 py-2 text-left text-sm transition hover:bg-white/5 hover:text-ink {option.value ===
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
                    <Check
                        size={14}
                        class="shrink-0 text-accent-soft"
                        aria-hidden="true"
                    />
                {/if}
            {/if}
        </button>
    {/each}
</div>
