<script lang="ts">
    import { CalendarDays, ChevronDown, ExternalLink, Image as ImageIcon, Link2, List, Pencil, RefreshCw, Star, Trash2 } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AppView, MediaDetail, MediaStatus } from "$shared/types";
    import { statusLabel } from "$entities/media/model/mediaLabels";

    export interface SpecRow {
        label: string;
        value: string;
        /** Absolute URL when the value is a link; the sidebar renders an anchor instead of plain text. */
        href?: string;
    }

    interface Props {
        media: MediaDetail;
        statusOptions: readonly MediaStatus[];
        statusBusy: boolean;
        onChangeStatus: (status: MediaStatus) => Promise<void>;
        statusError: unknown;
        scoreValue: number | null;
        ratingOpen: boolean;
        onRatingOpen: () => void;
        onRatingClose: () => void;
        onRatingHide: () => void;
        onSetScore: (score: number) => Promise<void>;
        onClearScore: () => void;
        formatDate: (value: string | null) => string;
        historyProgressText: () => string;
        watchedOnInput: string;
        watchedOnOptions: readonly string[];
        onWatchedOnInput: (value: string) => void;
        onWatchedOnDirty: () => void;
        onSaveWatchedOn: () => Promise<void>;
        platformOptions: readonly string[];
        onSelectPlatform: (platform: string) => Promise<void>;
        refreshBusy: boolean;
        refreshError: unknown;
        onRefreshMetadata: () => Promise<void>;
        onRelink: () => void;
        onStartEdit: () => void;
        deleteBusy: boolean;
        deleteError: unknown;
        onDelete: () => Promise<void>;
        onNavigate: (view: AppView) => void;
        specRows: readonly SpecRow[];
        /** Background enrichment is still running: only the poster waits, the rest of the page does not. */
        syncing?: boolean;
    }

    let {
        media,
        statusOptions,
        statusBusy,
        onChangeStatus,
        statusError,
        scoreValue,
        ratingOpen,
        onRatingOpen,
        onRatingClose,
        onRatingHide,
        onSetScore,
        onClearScore,
        formatDate,
        historyProgressText,
        watchedOnInput,
        watchedOnOptions,
        onWatchedOnInput,
        onWatchedOnDirty,
        onSaveWatchedOn,
        platformOptions,
        onSelectPlatform,
        refreshBusy,
        refreshError,
        onRefreshMetadata,
        onRelink,
        onStartEdit,
        deleteBusy,
        deleteError,
        onDelete,
        onNavigate,
        specRows,
        syncing = false,
    }: Props = $props();

    const statusMenuItems = $derived(
        statusOptions.map((value) => ({ value, label: statusLabel(value) })),
    );

    const platformMenuItems = $derived(
        platformOptions.map((value) => ({ value, label: value })),
    );
</script>

<aside
    class="w-full space-y-6 lg:sticky lg:top-4 lg:self-start lg:w-80 lg:shrink-0"
>
    <div
        class="aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] shadow-lg"
    >
        {#if syncing && !media.coverUrl}
            <div
                class="flex h-full animate-pulse flex-col items-center justify-center gap-2 bg-white/[0.04]"
            >
                <ImageIcon
                    size={32}
                    stroke-width={1.25}
                    class="text-muted"
                    aria-hidden="true"
                />
                <p class="px-3 text-center text-xs text-muted">
                    {i18n.t.activity.loadingCover}
                </p>
            </div>
        {:else if media.coverUrl}
            <img
                src={media.coverUrl}
                alt={media.title}
                class="h-full w-full object-cover object-top"
            />
        {:else}
            <div class="grid h-full place-items-center text-muted">
                <ImageIcon size={40} stroke-width={1.25} aria-hidden="true" />
            </div>
        {/if}
    </div>

    <!-- Status selector and User Rating in a unified row -->
    <div class="flex items-center gap-2">
        <div class="relative flex-1">
            <PopoverMenu
                id={`detail-status-${media.id}`}
                options={statusMenuItems}
                selected={media.status}
                onSelect={(value) => onChangeStatus(value as MediaStatus)}
                label={i18n.t.status.label}
                matchTriggerWidth
                class="min-w-40"
                optionClass="hover:bg-[var(--color-panel-raised)]"
            >
                {#snippet trigger({ popoverTargetId, anchorName })}
                    <button
                        type="button"
                        popovertarget={popoverTargetId}
                        popovertargetaction="toggle"
                        style="anchor-name: {anchorName}"
                        disabled={statusBusy}
                        class="tap flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-white/[0.08] bg-[var(--color-panel-line)] px-3.5 text-sm font-medium text-white transition hover:bg-[var(--color-panel-raised)] has-[:popover-open]:ring-2 has-[:popover-open]:ring-accent-soft disabled:cursor-not-allowed disabled:opacity-70"
                        aria-haspopup="listbox"
                    >
                        <span class="truncate">{statusLabel(media.status)}</span
                        >
                        <ChevronDown
                            size={15}
                            class="shrink-0 transition group-[:popover-open]:rotate-180 has-[:popover-open]:rotate-180"
                            aria-hidden="true"
                        />
                    </button>
                {/snippet}
            </PopoverMenu>
        </div>
<!-- Icon-only rating button, same height as the status block; opens on hover. -->
        <div
            class="relative shrink-0"
            data-rating-popover
            role="presentation"
            onpointerenter={onRatingOpen}
            onpointerleave={onRatingClose}
        >
            <button
                type="button"
                class={`tap grid h-10 w-10 place-items-center rounded-lg border transition ${
                    scoreValue !== null
                        ? "border-amber-400/40 bg-amber-400/10 text-amber-300"
                        : "border-white/[0.08] bg-[var(--color-panel-line)] text-white/80 hover:bg-[var(--color-panel-raised)] hover:text-white"
                }`}
                onclick={onRatingOpen}
                title={i18n.t.detail.yourRating}
                aria-label={i18n.t.detail.yourRating}
                aria-expanded={ratingOpen}
            >
                {#if scoreValue !== null}
                    <Star
                        size={18}
                        class="text-amber-400"
                        fill="currentColor"
                        aria-hidden="true"
                    />
                {:else}
                    <Star size={18} aria-hidden="true" />
                {/if}
            </button>

            {#if ratingOpen}
                <div
                    class="absolute right-0 top-full z-30 mt-2 w-48 rounded-xl border border-white/[0.12] bg-[var(--color-overlay)] p-3 shadow-2xl shadow-black/90"
                >
                    <div
                        class="mb-2 text-center text-xs font-semibold text-slate-300"
                    >
                        {#if scoreValue !== null}
                            <span class="font-bold tabular-nums text-amber-300"
                                >{scoreValue}</span
                            >
                            {i18n.t.detail.yourRating}
                        {:else}
                            {i18n.t.detail.rateButton}
                        {/if}
                    </div>
                    <div class="grid grid-cols-5 gap-1.5">
                        {#each Array(10) as _, index}
                            {@const val = index + 1}
                            <button
                                type="button"
                                class={`flex h-7 w-7 items-center justify-center rounded-md text-xs font-bold transition cursor-pointer ${
                                    val === scoreValue
                                        ? "bg-[#3b82f6] text-white shadow-md"
                                        : "bg-white/5 text-slate-300 hover:bg-white/15 hover:text-white"
                                }`}
                                onclick={() => {
                                    void onSetScore(val);
                                    onRatingHide();
                                }}
                            >
                                {val}
                            </button>
                        {/each}
                    </div>
                    {#if scoreValue !== null}
                        <div
                            class="mt-2.5 border-t border-white/[0.08] pt-2 text-center"
                        >
                            <button
                                type="button"
                                class="text-xs font-semibold text-rose-400 hover:text-rose-300 transition cursor-pointer"
                                onclick={() => {
                                    onClearScore();
                                    onRatingHide();
                                }}
                            >
                                {i18n.t.detail.clearRating}
                            </button>
                        </div>
                    {/if}
                </div>
            {/if}
        </div>
    </div>
    {#if statusError}<p class="text-xs text-rose-300" role="alert">
            {errorMessage(statusError)}
        </p>{/if}
<!-- Panel 1: Your History -->
    <div>
        <h2
            class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200"
        >
            {i18n.t.detail.historyTitle}
        </h2>
        <div class="panel">
            <!-- Every row gets the same padding so the list reads as one even
                 rhythm; the first/last rows align with the panel's own padding
                 instead of adding 12px on only one side. -->
            <dl class="divide-y divide-white/[0.06] text-sm">
                <!-- Movies are watched as a single sitting: a start date and a raw
                     "current / total" counter say nothing there that the progress stepper
                     does not, so only the completion is kept. Every other type still needs
                     both rows — a series or a manga is started, then tracked over time. -->
                {#if media.type !== "movie"}
                    <div
                        class="flex items-center justify-between gap-3 py-2.5 first:pt-0"
                    >
                        <dt class="text-muted text-xs">
                            {i18n.t.detail.startedLabel}
                        </dt>
                        <dd class="font-medium text-white text-xs">
                            {formatDate(media.startedAt)}
                        </dd>
                    </div>
                {/if}
                <div
                    class="flex items-center justify-between gap-3 py-2.5"
                    class:first:pt-0={media.type === "movie"}
                >
                    <dt class="text-muted text-xs">
                        {i18n.t.detail.endedLabel}
                    </dt>
                    <dd class="font-medium text-white text-xs">
                        {formatDate(media.finishedAt)}
                    </dd>
                </div>
                {#if media.type !== "movie"}
                    <div class="flex items-center justify-between gap-3 py-2.5">
                        <dt class="text-muted text-xs">
                            {i18n.t.detail.progressShort}
                        </dt>
                        <dd class="font-medium tabular-nums text-white text-xs">
                            {historyProgressText()}
                        </dd>
                    </div>
                {/if}
                {#if media.type === "movie" || media.type === "tvshow"}
                    <!-- Pick a known site or type your own; saved on change/blur. -->
                    <div
                        class="flex items-center justify-between gap-3 py-2.5 last:pb-0"
                    >
                        <dt class="text-muted text-xs">
                            {i18n.current === "ru"
                                ? "Где смотрено"
                                : "Watched on"}
                        </dt>
                        <dd class="min-w-0 flex-1 text-right">
                            <input
                                id="watched-on-input"
                                list="watched-on-sites"
                                class="h-8 w-full max-w-[14rem] rounded-lg border border-white/10 bg-elevated px-2 text-right text-xs text-white outline-none focus:border-accent focus:ring-2 focus:ring-accent/30"
                                placeholder={i18n.current === "ru"
                                    ? "Выберите сайт или введите свой"
                                    : "Pick a site or type your own"}
                                value={watchedOnInput}
                                oninput={(e) => {
                                    onWatchedOnInput(e.currentTarget.value);
                                    onWatchedOnDirty();
                                }}
                                onchange={() => void onSaveWatchedOn()}
                                onblur={() => void onSaveWatchedOn()}
                            />
                            <datalist id="watched-on-sites">
                                {#each watchedOnOptions as site (site)}
                                    <option value={site}></option>
                                {/each}
                            </datalist>
                        </dd>
                    </div>
                {/if}
{#if media.type === "game"}
                    <div
                        class="flex items-center justify-between gap-3 py-2.5 last:pb-0"
                    >
                        <dt class="text-muted text-xs">
                            {i18n.current === "ru" ? "Платформа" : "Platform"}
                        </dt>
                        <dd class="relative font-medium text-white text-xs">
                            {#if platformOptions.length > 0}
                                <PopoverMenu
                                    id={`platform-${media.id}`}
                                    options={platformMenuItems}
                                    selected={media.userPlatform ?? ""}
                                    onSelect={(value) =>
                                        onSelectPlatform(String(value))}
                                    label={i18n.t.detailModal.platform}
                                    placement="bottom-end"
                                    class="max-h-56 min-w-[150px] overflow-y-auto"
                                    optionClass="text-xs"
                                    openOnHover
                                    closeDelay={220}
                                >
                                    {#snippet trigger({
                                        popoverTargetId,
                                        anchorName,
                                    })}
                                        <button
                                            type="button"
                                            popovertarget={popoverTargetId}
                                            popovertargetaction="toggle"
                                            style="anchor-name: {anchorName}"
                                            class="tap flex max-w-[155px] items-center justify-between gap-2 rounded-lg border border-white/[0.08] bg-[var(--color-field)] px-2.5 py-1.5 text-xs text-white transition hover:border-[color-mix(in_oklab,var(--color-accent)_50%,transparent)] hover:bg-[var(--color-track-faint)] has-[:popover-open]:ring-1 has-[:popover-open]:ring-[var(--color-accent)]"
                                            aria-haspopup="listbox"
                                        >
                                            <span class="truncate"
                                                >{media.userPlatform ||
                                                (i18n.current === "ru"
                                                    ? "Не выбрана"
                                                    : "Not selected")}</span
                                            >
                                            <ChevronDown
                                                size={13}
                                                class="shrink-0 text-muted transition duration-200 has-[:popover-open]:rotate-180 has-[:popover-open]:text-white"
                                                aria-hidden="true"
                                            />
                                        </button>
                                    {/snippet}
                                </PopoverMenu>
                            {:else}
                                <span class="text-xs text-muted">—</span>
                            {/if}
                        </dd>
                    </div>
                {/if}
            </dl>
        </div>
    </div>
<!-- Panel 2: Actions -->
    <div>
        <h2
            class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200"
        >
            {i18n.t.detail.actionsTitle}
        </h2>
        <div class="panel space-y-2">
            <button
                type="button"
                class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
                disabled={refreshBusy}
                onclick={() => void onRefreshMetadata()}
            >
                <RefreshCw
                    size={15}
                    class={`text-[var(--color-success-line)] ${refreshBusy ? "animate-spin" : ""}`}
                    aria-hidden="true"
                />
                {i18n.t.detail.updateMetadata}
            </button>
            {#if refreshError}<p class="text-xs text-rose-300" role="alert">
                    {errorMessage(refreshError)}
                </p>{/if}

            <!-- Refresh re-reads the id already stored; this is for when that id belongs to the wrong
                 provider's match, so the user can point the row at a better one. -->
            <button
                type="button"
                class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
                onclick={onRelink}
            >
                <Link2
                    size={15}
                    class="text-[var(--color-accent-soft)]"
                    aria-hidden="true"
                />
                {i18n.current === "ru" ? "Сменить источник" : "Change source"}
            </button>

            <button
                type="button"
                class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
                onclick={() => onNavigate("lists")}
            >
                <List
                    size={15}
                    class="text-[var(--color-accent-soft)]"
                    aria-hidden="true"
                />
                {i18n.t.detail.addToLists}
            </button>

            <button
                type="button"
                class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
                onclick={() => onNavigate("calendar")}
            >
                <CalendarDays
                    size={15}
                    class="text-[var(--color-star)]"
                    aria-hidden="true"
                />
                {i18n.t.detail.activity}
            </button>

            <button
                type="button"
                class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[var(--color-ink-dim)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
                onclick={onStartEdit}
            >
                <Pencil
                    size={15}
                    class="text-[var(--color-info-soft)]"
                    aria-hidden="true"
                />
                {i18n.t.detailModal.edit}
            </button>

            <button
                type="button"
                class="tap flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-rose-300 transition hover:bg-[var(--color-panel-raised)] disabled:cursor-not-allowed disabled:opacity-70"
                disabled={deleteBusy}
                onclick={() => void onDelete()}
            >
                <Trash2 size={15} class="text-rose-400" aria-hidden="true" />
                {i18n.t.detailModal.delete}
            </button>
            {#if deleteError}<p class="text-xs text-rose-300" role="alert">
                    {errorMessage(deleteError)}
                </p>{/if}
        </div>
    </div>
<!-- Panel 3: Details -->
    <div>
        <h2
            class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200"
        >
            {i18n.t.detail.detailsTitle}
        </h2>
        <div class="panel">
            <dl class="divide-y divide-white/5 text-sm">
                {#each specRows as row, idx (`${row.label}-${idx}`)}
                    <div
                        class="flex items-start justify-between gap-3 py-3 first:pt-0 last:pb-0"
                    >
                        <dt class="shrink-0 text-xs font-medium text-muted">
                            {row.label}
                        </dt>
                        <dd class="text-right text-xs font-medium text-white">
                            {#if row.href}
                                <a
                                    href={row.href}
                                    target="_blank"
                                    rel="noreferrer"
                                    class="inline-flex items-center gap-1 text-accent-soft hover:underline"
                                >
                                    {row.value}
                                    <ExternalLink size={11} aria-hidden="true" />
                                </a>
                            {:else}
                                {row.value}
                            {/if}
                        </dd>
                    </div>
                {/each}
            </dl>
        </div>
    </div>
</aside>