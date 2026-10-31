<script lang="ts">
  import { dismissToast, toastStore, type ToastType } from "$shared/ui/toast.svelte";

  let containerEl = $state<HTMLDivElement | null>(null);

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
</script>

<div
  bind:this={containerEl}
  popover="manual"
  class="pointer-events-none z-[99999] flex w-72 flex-col gap-2 sm:w-80"
  style="position: fixed; inset: auto; bottom: 1.25rem; right: 1.25rem; left: auto; top: auto; margin: 0;"
  aria-live="polite"
  aria-atomic="false"
>
  {#each toastStore.items as toast (toast.id)}
    <div
      class="toast pointer-events-auto flex w-full cursor-default items-start gap-3 rounded-xl border border-white/10 bg-[#151a26]/95 p-3.5 shadow-2xl shadow-black/50 backdrop-blur-xl"
      role="alert"
    >
      <div class="{badgeClasses[toast.type]} grid size-8 shrink-0 place-items-center rounded-lg">
        {#if toast.type === "error"}
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="h-4 w-4"
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
            class="h-4 w-4"
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
            class="h-4 w-4"
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
        <p class="text-xs leading-snug font-bold break-words text-white">
          {toast.message}
        </p>
        {#if toast.description}
          <p class="mt-0.5 text-[11px] leading-snug break-words text-slate-400">
            {toast.description}
          </p>
        {/if}
      </div>
      <button
        type="button"
        class="shrink-0 cursor-pointer rounded-md p-1 text-slate-500 transition hover:bg-white/5 hover:text-white"
        aria-label="Close notification"
        onclick={() => dismissToast(toast.id)}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2"
          stroke="currentColor"
          class="h-4 w-4"
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  {/each}
</div>

<style>
  /* Slide-up on enter: toasts rise into place instead of popping. */
  .toast {
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
