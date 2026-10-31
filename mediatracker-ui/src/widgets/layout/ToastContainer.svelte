<script lang="ts">
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

  function isExpandable(toast: (typeof toastStore.items)[number]): boolean {
    return Boolean(toast.description) || toast.message.length > 80;
  }

  function toggleExpanded(id: string) {
    expanded[id] = !expanded[id];
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
      class="toast-card pointer-events-auto w-full rounded-xl border border-white/10 bg-[#151a26]/95 p-3.5 shadow-2xl shadow-black/50 backdrop-blur-xl transition-all duration-200"
      role="alert"
    >
      <div class="flex items-start gap-3">
        <div
          class="{badgeClasses[toast.type]} grid size-7 shrink-0 place-items-center rounded-lg border"
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
        <div class="min-w-0 flex-1 pt-0.5">
          <p class="line-clamp-2 text-xs leading-snug font-semibold break-words text-white">
            {toast.message}
          </p>
          {#if expandable}
            <button
              type="button"
              class="mt-1 flex cursor-pointer items-center gap-1 text-[11px] font-medium text-indigo-400 transition hover:text-indigo-300"
              onclick={() => toggleExpanded(toast.id)}
            >
              <span>{isExpanded ? i18n.t.common.collapse : i18n.t.common.details}</span>
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-3 transition-transform duration-200 {isExpanded ? 'rotate-180' : ''}"
                aria-hidden="true"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
              </svg>
            </button>
          {/if}
        </div>
        <button
          type="button"
          class="shrink-0 cursor-pointer rounded-md p-1 text-slate-400 transition hover:bg-white/10 hover:text-white"
          aria-label="Close notification"
          onclick={() => dismissToast(toast.id)}
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
      {#if expandable && isExpanded}
        <div
          class="thin-scroll mt-2 max-h-40 overflow-y-auto border-t border-white/5 pt-2 font-mono text-[11px] leading-relaxed break-words text-slate-300 select-text"
        >
          {toast.message}
          {#if toast.description}
            <p class="mt-1 text-slate-400">{toast.description}</p>
          {/if}
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
</style>
