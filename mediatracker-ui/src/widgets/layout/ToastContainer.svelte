<script lang="ts">
    import {
        dismissToast,
        toastStore,
        type ToastType,
    } from "$shared/ui/toast.svelte";

    const accentClasses: Record<ToastType, string> = {
        error: "text-[#d65563]",
        success: "text-emerald-400",
        warning: "text-amber-400",
    };
</script>

<div
    class="pointer-events-none fixed bottom-5 right-5 z-50 flex flex-col gap-2 w-60 sm:w-72 text-[10px] sm:text-xs"
    aria-live="polite"
    aria-atomic="false"
>
    {#each toastStore.items as toast (toast.id)}
        <div
            class="error-alert pointer-events-auto cursor-default flex items-center justify-between w-full min-h-12 sm:min-h-14 rounded-lg bg-[#232531] px-[10px] py-1.5 shadow-lg shadow-black/40 transition-colors duration-200"
            role="alert"
        >
            <div class="flex items-center gap-2 min-w-0 flex-1 mr-2">
                <div
                    class="{accentClasses[toast.type]} bg-white/5 backdrop-blur-xl p-1 rounded-lg shrink-0 flex items-center justify-center"
                >
                    {#if toast.type === "error"}
                        <svg
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                            class="w-5 h-5 sm:w-6 sm:h-6"
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
                            class="w-5 h-5 sm:w-6 sm:h-6"
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
                            class="w-5 h-5 sm:w-6 sm:h-6"
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
                    <p class="text-white font-medium leading-tight break-words">
                        {toast.message}
                    </p>
                    {#if toast.description}
                        <p class="text-gray-500 leading-tight mt-0.5 break-words">
                            {toast.description}
                        </p>
                    {/if}
                </div>
            </div>
            <button
                type="button"
                class="text-gray-600 hover:text-gray-300 hover:bg-white/10 p-1 rounded-md transition-colors ease-linear shrink-0 cursor-pointer"
                aria-label="Close notification"
                onclick={() => dismissToast(toast.id)}
            >
                <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="w-5 h-5 sm:w-6 sm:h-6"
                    aria-hidden="true"
                >
                    <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M6 18 18 6M6 6l12 12"
                    />
                </svg>
            </button>
        </div>
    {/each}
</div>
