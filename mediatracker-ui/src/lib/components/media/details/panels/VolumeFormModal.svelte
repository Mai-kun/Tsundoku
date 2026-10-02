<script lang="ts">
    import Check from "lucide-svelte/icons/check";
    import Plus from "lucide-svelte/icons/plus";
    import { i18n } from "$lib/i18n/index.svelte";

    interface Props {
        /** "add" shows title + chapters; "edit" adds the page/chapter counters. */
        mode: "add" | "edit";
        open: boolean;
        busy: boolean;
        title: string;
        chapters: number;
        pages?: number;
        currentChapter?: number;
        currentPage?: number;
        onTitleChange: (value: string) => void;
        onChaptersChange: (value: number) => void;
        /** Only used in "edit" mode. */
        onPagesChange?: (value: number) => void;
        /** Only used in "edit" mode. */
        onCurrentChapterChange?: (value: number) => void;
        /** Only used in "edit" mode. */
        onCurrentPageChange?: (value: number) => void;
        onClose: () => void;
        onSubmit: () => void;
    }

    let {
        mode,
        open,
        busy,
        title,
        chapters,
        pages = 200,
        currentChapter = 0,
        currentPage = 0,
        onTitleChange,
        onChaptersChange,
        onPagesChange = () => {},
        onCurrentChapterChange = () => {},
        onCurrentPageChange = () => {},
        onClose,
        onSubmit,
    }: Props = $props();

    const inputClass =
        "h-9 w-full rounded-md border border-white/[0.08] bg-[var(--color-field)] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[var(--color-accent)]";
    const labelClass = "block text-xs text-muted mb-1";

    /** number inputs report "" while cleared, which valueAsNumber turns into NaN. */
    function onNumber(
        handler: (value: number) => void,
        event: Event & { currentTarget: HTMLInputElement },
    ) {
        handler(event.currentTarget.valueAsNumber || 0);
    }

    const heading = $derived(
        mode === "add"
            ? i18n.current === "ru"
                ? "Добавить том"
                : "Add Volume"
            : i18n.current === "ru"
              ? "Изменить том"
              : "Edit Volume",
    );
</script>

{#if open}
    <div
        class="fixed inset-0 z-50 flex items-center justify-center bg-canvas/80 backdrop-blur-sm p-4"
        role="presentation"
        onclick={(e) => {
            if (e.target === e.currentTarget) onClose();
        }}
    >
        <div
            class="w-full max-w-sm rounded-xl border border-white/[0.08] bg-[var(--color-track-mid)] p-6 shadow-2xl space-y-4"
        >
            <h3 class="text-sm font-bold text-white">{heading}</h3>
            <div class="space-y-3">
                <div>
                    <label class={labelClass} for="vol-title">
                        {i18n.current === "ru" ? "Название" : "Title"}
                    </label>
                    <input
                        id="vol-title"
                        type="text"
                        class={inputClass}
                        value={title}
                        oninput={(e) => onTitleChange(e.currentTarget.value)}
                        onkeydown={(e) => {
                            if (e.key === "Enter") onSubmit();
                        }}
                    />
                </div>

                {#if mode === "add"}
                    <div>
                        <label class={labelClass} for="vol-chapters">
                            {i18n.current === "ru" ? "Главы" : "Chapters"}
                        </label>
                        <input
                            id="vol-chapters"
                            type="number"
                            min="0"
                            class={inputClass}
                            value={chapters}
                            oninput={(e) => onNumber(onChaptersChange, e)}
                        />
                    </div>
                {:else}
                    <div class="grid grid-cols-2 gap-2">
                        <div>
                            <label class={labelClass} for="vol-current-chapter">
                                {i18n.current === "ru"
                                    ? "Текущая глава"
                                    : "Current Chapter"}
                            </label>
                            <input
                                id="vol-current-chapter"
                                type="number"
                                min="0"
                                class={inputClass}
                                value={currentChapter}
                                oninput={(e) =>
                                    onNumber(onCurrentChapterChange, e)}
                            />
                        </div>
                        <div>
                            <label class={labelClass} for="vol-chapters">
                                {i18n.current === "ru"
                                    ? "Всего глав"
                                    : "Total Chapters"}
                            </label>
                            <input
                                id="vol-chapters"
                                type="number"
                                min="0"
                                class={inputClass}
                                value={chapters}
                                oninput={(e) => onNumber(onChaptersChange, e)}
                            />
                        </div>
                    </div>
                    <div class="grid grid-cols-2 gap-2">
                        <div>
                            <label class={labelClass} for="vol-current-page">
                                {i18n.current === "ru"
                                    ? "Текущая страница"
                                    : "Current Page"}
                            </label>
                            <input
                                id="vol-current-page"
                                type="number"
                                min="0"
                                class={inputClass}
                                value={currentPage}
                                oninput={(e) =>
                                    onNumber(onCurrentPageChange, e)}
                            />
                        </div>
                        <div>
                            <label class={labelClass} for="vol-pages">
                                {i18n.current === "ru"
                                    ? "Всего страниц"
                                    : "Total Pages"}
                            </label>
                            <input
                                id="vol-pages"
                                type="number"
                                min="1"
                                class={inputClass}
                                value={pages}
                                oninput={(e) => onNumber(onPagesChange, e)}
                            />
                        </div>
                    </div>
                {/if}
            </div>
            <div class="flex justify-end gap-2 pt-1">
                <button
                    type="button"
                    class="inline-flex h-8 items-center rounded-md border border-white/[0.08] px-3 text-xs font-medium text-muted hover:text-white transition"
                    onclick={onClose}
                >
                    {i18n.current === "ru" ? "Отмена" : "Cancel"}
                </button>
                <button
                    type="button"
                    class="inline-flex h-8 items-center gap-1.5 rounded-md bg-[var(--color-accent)] px-3 text-xs font-semibold text-white transition hover:bg-[var(--color-accent-bright)] disabled:opacity-50"
                    disabled={busy}
                    onclick={onSubmit}
                >
                    {#if mode === "add"}
                        <Plus size={13} aria-hidden="true" />
                        {i18n.current === "ru" ? "Добавить" : "Add"}
                    {:else}
                        <Check size={13} aria-hidden="true" />
                        {i18n.current === "ru" ? "Сохранить" : "Save"}
                    {/if}
                </button>
            </div>
        </div>
    </div>
{/if}