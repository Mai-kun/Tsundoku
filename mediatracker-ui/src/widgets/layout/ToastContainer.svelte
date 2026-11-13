<script lang="ts">
  import { flip } from "svelte/animate";
  import { fade, fly } from "svelte/transition";
  import { SvelteSet } from "svelte/reactivity";
  import { Check, ChevronDown, ChevronUp, RotateCcw, Tag, X } from "$shared/ui/Icons";
  import {
    dismissToast,
    toastStore,
    type ToastAction,
    type ToastItem,
    type ToastType,
  } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";

  let containerEl = $state<HTMLDivElement | null>(null);
  let expanded = new SvelteSet<string>();
  let hovered = new SvelteSet<string>();

  // Native <dialog showModal()> lives in the browser Top Layer and outranks any z-index, so the
  // container becomes a "manual" popover as well when toasts are present to share that Top Layer.
  $effect(() => {
    if (!containerEl) return;
    if (toastStore.items.length > 0) {
      try {
        containerEl.showPopover?.();
      } catch {}
    } else {
      try {
        containerEl.hidePopover?.();
      } catch {}
    }
  });

  const badgeClasses: Record<ToastType, string> = {
    error: "bg-rose-500/15 border border-rose-500/30 text-rose-400",
    success: "bg-emerald-500/15 border border-emerald-500/30 text-emerald-400",
    warning: "bg-amber-500/15 border border-amber-500/30 text-amber-400",
    info: "bg-sky-500/15 border border-sky-500/30 text-sky-400",
  };

  const timerBarClasses: Record<ToastType, string> = {
    error: "bg-rose-400/90",
    success: "bg-emerald-400/90",
    warning: "bg-amber-400/90",
    info: "bg-sky-400/90",
  };

  /* ---------- JS-driven countdown (pause on hover, 1s grace on leave) ----------
     The bar and the auto-dismiss share one rAF clock: pausing freezes the bar
     exactly where it is and delays the dismissal by the same amount, so the
     strip can never desync from the actual lifetime. */

  /** Grace window after the pointer leaves: the countdown stays frozen for
   *  exactly 1s and only then smoothly resumes (a re-enter cancels it). */
  const GRACE_MS = 1000;

  interface TimerState {
    elapsed: number;
    last: number | null;
    grace: number | null;
  }

  const timers = new Map<string, TimerState>();
  let progress = $state<Record<string, number>>({});
  let rafId = 0;

  function hasButtons(toast: ToastItem): boolean {
    return toast.showOk || toast.undo !== undefined || toast.actions.length > 0;
  }

  function startTimer(toast: ToastItem) {
    if (toast.durationMs <= 0) return;
    if (!timers.has(toast.id)) {
      timers.set(toast.id, { elapsed: 0, last: null, grace: null });
    }
    ensureRaf();
  }

  function stopTimer(id: string) {
    timers.delete(id);
    delete progress[id];
  }

  function isPaused(id: string): boolean {
    return hovered.has(id) || expanded.has(id);
  }

  function tick(now: number) {
    let active = false;
    for (const toast of toastStore.items) {
      const timer = timers.get(toast.id);
      if (!timer) continue;

      if (timer.last === null) {
        timer.last = now;
        active = true;
        continue;
      }

      const dt = now - timer.last;
      timer.last = now;
      if (isPaused(toast.id)) {
        timer.grace = null; // back on the card: any pending grace is cancelled
      } else if (timer.grace !== null) {
        timer.grace -= dt;
        if (timer.grace <= 0) timer.grace = null; // grace over → resume next frame
      } else {
        timer.elapsed += dt;
      }

      const remaining = Math.max(0, 1 - timer.elapsed / toast.durationMs);
      progress[toast.id] = remaining;
      if (remaining <= 0) {
        // Auto-expiry: dismiss without onClose, which stays reserved for the X button.
        toastStore.dismiss(toast.id);
        stopTimer(toast.id);
        continue;
      }
      active = true;
    }
    // Drop clocks of toasts removed through dismissToast (buttons, X).
    for (const id of [...timers.keys()]) {
      if (!toastStore.items.some((t) => t.id === id)) stopTimer(id);
    }
    rafId = active ? requestAnimationFrame(tick) : 0;
  }

  function ensureRaf() {
    if (!rafId) rafId = requestAnimationFrame(tick);
  }

  // One clock per toast: registered when the toast appears, unregistered when it
  // leaves, so the rAF driver, the countdown bar and the auto-dismiss stay in lockstep.
  $effect(() => {
    const ids = new Set<string>();
    for (const toast of toastStore.items) {
      ids.add(toast.id);
      startTimer(toast);
    }
    for (const id of [...timers.keys()]) {
      if (!ids.has(id)) stopTimer(id);
    }
  });

  function enterCard(toast: ToastItem) {
    hovered.add(toast.id);
    const timer = timers.get(toast.id);
    if (timer) timer.grace = null; // returning before 1s cancels the pending resume
  }

  function leaveCard(toast: ToastItem) {
    hovered.delete(toast.id);
    const timer = timers.get(toast.id);
    // While expanded the clock stays frozen; otherwise hold exactly 1s, then resume.
    if (timer && !expanded.has(toast.id)) timer.grace = GRACE_MS;
  }

  function toggleExpanded(toast: ToastItem) {
    if (expanded.has(toast.id)) expanded.delete(toast.id);
    else expanded.add(toast.id);
  }

  function close(toast: ToastItem) {
    toast.onClose?.();
    stopTimer(toast.id);
    dismissToast(toast.id);
  }

  function runAction(toast: ToastItem, onClick: () => void) {
    stopTimer(toast.id);
    dismissToast(toast.id);
    onClick();
  }

  /** Collapsed compact glyph for a custom action button. */
  function actionIcon(action: ToastAction) {
    switch (action.id) {
      case "keepStatus":
        return Tag;
      default:
        return null;
    }
  }
</script>

<div
  bind:this={containerEl}
  popover="manual"
  class="pointer-events-none fixed right-5 bottom-5 z-[99999] flex w-[420px] max-w-[calc(100vw-2rem)] flex-col gap-2.5"
  style="inset: auto; bottom: 1.25rem; right: 1.25rem; left: auto; top: auto; margin: 0;"
  aria-live="polite"
  aria-atomic="false"
>
  {#each toastStore.items as toast (toast.id)}
    {@const isExpanded = expanded.has(toast.id)}
    {@const isHovered = hovered.has(toast.id)}
    {@const showChevron = isHovered || isExpanded}
    {@const buttons = hasButtons(toast)}
    <div
      class="toast-card group pointer-events-auto relative w-full overflow-hidden rounded-xl border border-white/10 bg-[#151a26]/95 p-3.5 shadow-2xl shadow-black/50 backdrop-blur-xl transition duration-200"
      role="alert"
      animate:flip={{ duration: 200 }}
      in:fly={{ y: 14, duration: 220 }}
      out:fly={{ y: 10, duration: 160 }}
      onmouseenter={() => enterCard(toast)}
      onmouseleave={() => leaveCard(toast)}
    >
      <div class="flex items-center gap-2.5">
        <!-- Fixed icon slot: the type badge and the expand chevron crossfade
             in place, so the text never shifts while swapping. -->
        <div class="relative size-8 shrink-0">
          <div
            class="{badgeClasses[
              toast.type
            ]} absolute inset-0 grid place-items-center rounded-lg border transition-[opacity,transform] duration-200 {showChevron
              ? 'pointer-events-none scale-75 opacity-0'
              : 'scale-100 opacity-100'}"
          >
            {#if toast.type === "error"}
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-4"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z"
                />
              </svg>
            {:else if toast.type === "success"}
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-4"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                />
              </svg>
            {:else if toast.type === "warning"}
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-4"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
                />
              </svg>
            {:else}
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-4"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"
                />
              </svg>
            {/if}
          </div>
          <button
            type="button"
            class="absolute inset-0 grid cursor-pointer place-items-center rounded-lg text-slate-300 transition-[opacity,transform] duration-200 hover:bg-white/10 hover:text-white {showChevron
              ? 'scale-100 opacity-100'
              : 'pointer-events-none scale-75 opacity-0'}"
            title={isExpanded ? i18n.t.toast.collapse : i18n.t.toast.expand}
            aria-label={isExpanded ? i18n.t.toast.collapse : i18n.t.toast.expand}
            aria-expanded={isExpanded}
            onclick={() => toggleExpanded(toast)}
          >
            {#if isExpanded}
              <span in:fade={{ duration: 150 }} class="grid place-items-center">
                <ChevronUp size={16} aria-hidden="true" />
              </span>
            {:else}
              <span in:fade={{ duration: 150 }} class="grid place-items-center">
                <ChevronDown size={16} aria-hidden="true" />
              </span>
            {/if}
          </button>
        </div>
        <p class="min-w-0 flex-1 text-xs leading-snug font-semibold break-words text-white">
          {toast.title}
        </p>
        {#if !isExpanded && buttons}
          <!-- Compact icon row: collapses into the expanded footer below. -->
          <div class="flex items-center gap-1.5" in:fade={{ duration: 150 }} out:fade={{ duration: 100 }}>
            {#if toast.undo}
              <button
                type="button"
                class="grid size-7 shrink-0 cursor-pointer place-items-center rounded-lg border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10 hover:text-white"
                title={i18n.t.toast.undo}
                aria-label={i18n.t.toast.undo}
                onclick={() => runAction(toast, toast.undo!)}
              >
                <RotateCcw size={14} aria-hidden="true" />
              </button>
            {/if}
            {#each toast.actions as action (action.id)}
              {@const Icon = actionIcon(action)}
              <button
                type="button"
                class="grid size-7 shrink-0 cursor-pointer place-items-center rounded-lg border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10 hover:text-white"
                title={action.label}
                aria-label={action.label}
                onclick={() => runAction(toast, action.onClick)}
              >
                {#if Icon}
                  <Icon size={14} aria-hidden="true" />
                {:else}
                  <span class="text-[11px] font-semibold" aria-hidden="true">{action.label.charAt(0)}</span>
                {/if}
              </button>
            {/each}
            {#if toast.showOk}
              <button
                type="button"
                class="grid size-7 shrink-0 cursor-pointer place-items-center rounded-lg bg-indigo-600 text-white transition hover:bg-indigo-500"
                title={i18n.t.toast.ok}
                aria-label={i18n.t.toast.ok}
                onclick={() => runAction(toast, () => {})}
              >
                <Check size={15} aria-hidden="true" />
              </button>
            {/if}
          </div>
        {/if}
        <button
          type="button"
          class="shrink-0 cursor-pointer rounded-md p-1 text-slate-400 transition hover:bg-white/10 hover:text-white"
          aria-label={i18n.t.common.close}
          onclick={() => close(toast)}
        >
          <X size={16} aria-hidden="true" />
        </button>
      </div>
      <!-- grid-rows 0fr→1fr animates the height without knowing it; the card is
           anchored at the bottom edge, so it grows upward and pulls the full
           description and the labelled action buttons in with it. -->
      <div class="toast-expand" class:open={isExpanded}>
        <div class="toast-expand-inner">
          {#if isExpanded}
            <div class="border-t border-white/5 pt-2" in:fade={{ duration: 180 }}>
              <p
                class="thin-scroll max-h-40 overflow-y-auto text-[11px] leading-relaxed break-words text-slate-300 select-text"
              >
                {toast.description}
              </p>
              {#if buttons}
                <div class="mt-2 flex flex-wrap items-center gap-1.5">
                  {#if toast.undo}
                    <button
                      type="button"
                      class="cursor-pointer rounded-md border border-white/10 bg-white/5 px-2.5 py-1 text-[11px] font-medium text-slate-200 transition hover:bg-white/10 hover:text-white"
                      onclick={() => runAction(toast, toast.undo!)}
                    >
                      {i18n.t.toast.undo}
                    </button>
                  {/if}
                  {#each toast.actions as action (action.id)}
                    <button
                      type="button"
                      class="cursor-pointer rounded-md border border-white/10 bg-white/5 px-2.5 py-1 text-[11px] font-medium text-slate-200 transition hover:bg-white/10 hover:text-white"
                      onclick={() => runAction(toast, action.onClick)}
                    >
                      {action.label}
                    </button>
                  {/each}
                  {#if toast.showOk}
                    <button
                      type="button"
                      class="cursor-pointer rounded-md bg-indigo-600 px-2.5 py-1 text-[11px] font-semibold text-white transition hover:bg-indigo-500"
                      onclick={() => runAction(toast, () => {})}
                    >
                      {i18n.t.toast.ok}
                    </button>
                  {/if}
                </div>
              {/if}
            </div>
          {/if}
        </div>
      </div>
      {#if toast.durationMs > 0}
        <div class="pointer-events-none absolute inset-x-0 bottom-0 h-0.5 bg-white/5">
          <!-- JS-synced countdown: scaleX is written by the shared rAF clock,
               so hover pauses freeze the bar at the exact remaining fraction. -->
          <div
            class="{timerBarClasses[toast.type]} h-full origin-left"
            style="transform: scaleX({progress[toast.id] ?? 1});"
          ></div>
        </div>
      {/if}
    </div>
  {/each}
</div>

<style>
  /* Expand/collapse: animated grid row count keeps the card's height in sync
     with its content; content itself clips via the inner overflow wrapper. */
  .toast-expand {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows 250ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  .toast-expand.open {
    grid-template-rows: 1fr;
  }

  .toast-expand-inner {
    overflow: hidden;
    min-height: 0;
  }
</style>
