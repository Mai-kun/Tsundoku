<script lang="ts">
  import { Check, ChevronDown, ChevronUp, RotateCcw } from "$shared/ui/Icons";
  import { dismissToast, toastStore, type ToastType } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";

  let containerEl = $state<HTMLDivElement | null>(null);
  let expanded = $state<Record<string, boolean>>({});

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
  };

  const timerBarClasses: Record<ToastType, string> = {
    error: "bg-rose-400",
    success: "bg-emerald-400",
    warning: "bg-amber-400",
  };

  function isExpandable(toast: (typeof toastStore.items)[number]): boolean {
    return Boolean(toast.description) || toast.message.length > 80;
  }

  function toggleExpanded(id: string) {
    expanded[id] = !expanded[id];
  }

  function close(toast: (typeof toastStore.items)[number]) {
    toast.onClose?.();
    dismissToast(toast.id);
  }
</script>

<div
  bind:this={containerEl}
  popover="manual"
  class="pointer-events-none fixed right-5 bottom-5 z-[99999] flex w-[360px] max-w-[calc(100vw-2.5rem)] flex-col gap-2.5"
  style="inset: auto; bottom: 1.25rem; right: 1.25rem; left: auto; top: auto; margin: 0;"
  aria-live="polite"
  aria-atomic="false"
>
  {#each toastStore.items as toast (toast.id)}
    {@const expandable = isExpandable(toast)}
    {@const isExpanded = expanded[toast.id] === true}
    <div
      class="toast-card group pointer-events-auto relative w-full overflow-hidden rounded-xl border border-white/10 bg-[#151a26]/95 p-3.5 shadow-2xl shadow-black/50 backdrop-blur-xl transition duration-200"
      role="alert"
    >
      <div class="flex items-center gap-2.5">
        <div
          class="{badgeClasses[
            toast.type
          ]} grid size-7 shrink-0 place-items-center rounded-lg border"
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
                d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
              />
            </svg>
          {/if}
        </div>
        <p
          class="min-w-0 flex-1 text-xs leading-snug font-semibold break-words text-white {isExpanded
            ? ''
            : 'line-clamp-2'}"
        >
          {toast.message}
        </p>
        {#if expandable}
          <!-- Chevron appears on hover (always when expanded). Collapsed shows ▲:
               the card anchored at the screen bottom grows upward when opened. -->
          <button
            type="button"
            class="grid size-5 shrink-0 cursor-pointer place-items-center rounded-md text-slate-400 transition hover:bg-white/10 hover:text-white {isExpanded
              ? 'opacity-100'
              : 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100'}"
            title={isExpanded ? i18n.t.toast.collapse : i18n.t.toast.expand}
            aria-label={isExpanded ? i18n.t.toast.collapse : i18n.t.toast.expand}
            aria-expanded={isExpanded}
            onclick={() => toggleExpanded(toast.id)}
          >
            {#if isExpanded}
              <ChevronDown size={13} aria-hidden="true" />
            {:else}
              <ChevronUp size={13} aria-hidden="true" />
            {/if}
          </button>
        {/if}
        {#if toast.action}
          <button
            type="button"
            class="grid size-7 shrink-0 cursor-pointer place-items-center rounded-lg bg-indigo-600 text-white transition hover:bg-indigo-500"
            title={toast.action.label}
            aria-label={toast.action.label}
            onclick={() => {
              toast.action?.onClick();
              dismissToast(toast.id);
            }}
          >
            <Check size={15} aria-hidden="true" />
          </button>
        {/if}
        {#if toast.cancelAction}
          <button
            type="button"
            class="grid size-7 shrink-0 cursor-pointer place-items-center rounded-lg border border-white/10 bg-white/5 text-slate-300 transition hover:bg-white/10 hover:text-white"
            title={toast.cancelAction.label}
            aria-label={toast.cancelAction.label}
            onclick={() => {
              toast.cancelAction?.onClick();
              dismissToast(toast.id);
            }}
          >
            <RotateCcw size={14} aria-hidden="true" />
          </button>
        {/if}
        <button
          type="button"
          class="shrink-0 cursor-pointer rounded-md p-1 text-slate-400 transition hover:bg-white/10 hover:text-white"
          aria-label="Close notification"
          onclick={() => close(toast)}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="size-4"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      {#if expandable}
        <!-- grid-rows 0fr→1fr animates height without knowing it; the card is
             anchored at the bottom edge, so it grows upward and pulls the
             full text in with the shared spring-like easing. -->
        <div class="toast-expand" class:open={isExpanded}>
          <div class="toast-expand-inner">
            <div
              class="thin-scroll max-h-40 overflow-y-auto border-t border-white/5 pt-2 font-mono text-[11px] leading-relaxed break-words text-slate-300 select-text"
            >
              {toast.message}
              {#if toast.description}
                <p class="mt-1 text-slate-400">{toast.description}</p>
              {/if}
            </div>
          </div>
        </div>
      {/if}
      {#if toast.showTimerProgress}
        <div class="pointer-events-none absolute inset-x-0 bottom-0 h-0.5 bg-white/5">
          <div
            class="toast-timer {timerBarClasses[toast.type]} h-full origin-left"
            style="animation-duration: {toast.durationMs ?? 4000}ms;"
          ></div>
        </div>
      {/if}
    </div>
  {/each}
</div>

<style>
  /* Slide-up on enter: toasts rise into place instead of popping. Named toast-card because the
     bare "toast" class is a daisyUI component (position:fixed full-width) and hijacks the card. */
  .toast-card {
    animation: toast-in 200ms ease-out;
  }

  @keyframes toast-in {
    from {
      opacity: 0;
      transform: translateY(10px) scale(0.98);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  /* Countdown bar: linear scaleX from full width to zero across the toast's lifetime. */
  .toast-timer {
    animation-name: toast-timer-shrink;
    animation-timing-function: linear;
    animation-fill-mode: forwards;
  }

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

  @keyframes toast-timer-shrink {
    from {
      transform: scaleX(1);
    }
    to {
      transform: scaleX(0);
    }
  }
</style>
