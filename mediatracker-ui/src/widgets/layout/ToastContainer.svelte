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

  const accentClasses: Record<ToastType, string> = {
    error: "text-[#d65563]",
    success: "text-emerald-400",
    warning: "text-amber-400",
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
      class="error-alert pointer-events-auto flex min-h-12 w-full cursor-default items-center justify-between rounded-lg bg-[#232531] px-[10px] py-1.5 shadow-lg shadow-black/40 transition-colors duration-200 sm:min-h-14"
      role="alert"
    >
      <div class="mr-2 flex min-w-0 flex-1 items-center gap-2">
        <div
          class="{accentClasses[
            toast.type
          ]} flex shrink-0 items-center justify-center rounded-lg bg-white/5 p-1 backdrop-blur-xl"
        >
          {#if toast.type === "error"}
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="h-5 w-5 sm:h-6 sm:w-6"
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
              stroke-width="1.5"
              stroke="currentColor"
              class="h-5 w-5 sm:h-6 sm:w-6"
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
              stroke-width="1.5"
              stroke="currentColor"
              class="h-5 w-5 sm:h-6 sm:w-6"
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
        <div class="min-w-0 flex-1">
          <p class="leading-tight font-medium break-words text-white">
            {toast.message}
          </p>
          {#if toast.description}
            <p class="mt-0.5 leading-tight break-words text-gray-500">
              {toast.description}
            </p>
          {/if}
        </div>
      </div>
      <button
        type="button"
        class="shrink-0 cursor-pointer rounded-md p-1 text-gray-600 transition-colors ease-linear hover:bg-white/10 hover:text-gray-300"
        aria-label="Close notification"
        onclick={() => dismissToast(toast.id)}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="h-5 w-5 sm:h-6 sm:w-6"
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  {/each}
</div>
