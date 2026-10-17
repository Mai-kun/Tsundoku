<script lang="ts">
    import { onMount } from "svelte";
    import {
        getLists,
        getSources,
        importAniListProfile,
        importFile,
        importSteamProfile,
        saveSourceKey,
    } from "$shared/api/api";
    import type { CustomListSummary, ImportResultDto } from "$shared/types";
    import { i18n } from "$shared/i18n/index.svelte";
    import {
        Check,
        CheckCircle2,
        ChevronDown,
        ChevronUp,
        Copy,
        ExternalLink,
        FileText,
        LoaderCircle,
        Upload,
        X,
    } from "$shared/ui/Icons.svelte";

    interface Props {
        onImportCompleted?: () => void;
        onNavigateToList?: (id: string) => void;
        onClose?: () => void;
        showCloseButton?: boolean;
    }

    let {
        onImportCompleted,
        onNavigateToList,
        onClose,
        showCloseButton = false,
    }: Props = $props();

    type Provider =
        | "anilist"
        | "mangalib"
        | "mal"
        | "shikimori"
        | "letterboxd"
        | "goodreads"
        | "steam"
        | "custom";

    let provider = $state<Provider>("anilist");
    let file = $state<File | null>(null);
    let steamMode = $state<"profile" | "file">("profile");
    let steamProfile = $state("");
    let steamApiKey = $state("");
    let steamKeyConfigured = $state(false);
    let saveSteamKey = $state(false);
    let anilistMode = $state<"profile" | "file">("profile");
    let anilistUsername = $state("");
    let showTemplate = $state(false);
    let templateCopied = $state(false);
    let csvCopied = $state(false);
    let skipDuplicates = $state(true);
    let addToList = $state(false);
    let listMode = $state<"new" | "existing">("new");
    let lists = $state<CustomListSummary[]>([]);
    let targetListId = $state("");
    let newListName = $state("");
    let busy = $state(false);
    let error = $state("");
    let result = $state<ImportResultDto | null>(null);
    let dragging = $state(false);
    let profileChecked = $state(false);
    let fileInputRef = $state<HTMLInputElement | null>(null);

    const providers = $derived<
        {
            id: Provider;
            icon: string;
            title: string;
            subtitle: string;
            accent: string;
        }[]
    >([
        {
            id: "anilist",
            icon: "AL",
            title: "AniList",
            subtitle: i18n.t.importModal.subtitleAnilist,
            accent: "#02a9ff",
        },
        {
            id: "mangalib",
            icon: "ML",
            title: "MangaLib",
            subtitle: i18n.t.importModal.subtitleMangalib,
            accent: "#ff6740",
        },
        {
            id: "mal",
            icon: "MAL",
            title: "MyAnimeList",
            subtitle: "XML / JSON",
            accent: "#2e51a2",
        },
        {
            id: "shikimori",
            icon: "Ш",
            title: "Shikimori",
            subtitle: "XML / JSON",
            accent: "#e53935",
        },
        {
            id: "letterboxd",
            icon: "L",
            title: "Letterboxd",
            subtitle: "Movie CSV",
            accent: "#00e054",
        },
        {
            id: "goodreads",
            icon: "G",
            title: "Goodreads",
            subtitle: "Book CSV",
            accent: "#e9a825",
        },
        {
            id: "steam",
            icon: "S",
            title: "Steam",
            subtitle: "Games / Profile",
            accent: "#66c0f4",
        },
        {
            id: "custom",
            icon: "{ }",
            title: i18n.t.importModal.customTitle,
            subtitle: i18n.t.importModal.subtitleCustom,
            accent: "#a78bfa",
        },
    ]);

    const selectedProviderInfo = $derived(
        providers.find((p) => p.id === provider) ?? providers[0]
    );

    const fileAccept = $derived(
        provider === "mal" || provider === "shikimori"
            ? ".xml,.json"
            : provider === "letterboxd" || provider === "goodreads"
              ? ".csv"
              : provider === "steam" || provider === "anilist"
                ? ".json"
                : ".json,.csv"
    );

    const allowedExtensions = $derived(
        provider === "mal" || provider === "shikimori"
            ? ["xml", "json"]
            : provider === "letterboxd" || provider === "goodreads"
              ? ["csv"]
              : provider === "steam" || provider === "anilist"
                ? ["json"]
                : ["json", "csv"]
    );

    const helpText = $derived(
        ({
            mal: i18n.t.importModal.helpMal,
            shikimori: i18n.t.importModal.helpShikimori,
            letterboxd: i18n.t.importModal.helpLetterboxd,
            goodreads: i18n.t.importModal.helpGoodreads,
            steam: i18n.t.importModal.helpSteam,
            anilist: i18n.t.importModal.helpAnilist,
            mangalib: i18n.t.importModal.helpMangalib,
            custom: i18n.t.importModal.helpCustom,
        })[provider]
    );

    const defaultListName = $derived(
        i18n.t.importModal.defaultList(selectedProviderInfo.title)
    );

    onMount(() => {
        void loadListsAndSources();
    });

    async function loadListsAndSources() {
        try {
            const [fetchedLists, sources] = await Promise.all([
                getLists().catch(() => []),
                getSources().catch(() => []),
            ]);
            lists = fetchedLists;
            steamKeyConfigured = sources.some(
                (s) => s.id === "steam" && s.hasKey
            );
        } catch {
            // fallback
        }
    }

    $effect(() => {
        if (addToList && listMode === "new" && !newListName) {
            newListName = defaultListName;
        }
    });

    function selectProvider(id: Provider) {
        if (provider === id) return;
        provider = id;
        file = null;
        error = "";
        profileChecked = false;
        if (addToList && listMode === "new") {
            const nextInfo = providers.find((p) => p.id === id);
            newListName = i18n.t.importModal.defaultList(
                nextInfo?.title ?? id
            );
        }
    }

    function pickFile(value?: File) {
        if (!value) return;
        file = value;
        error = "";
    }

    function handleDrop(event: DragEvent) {
        event.preventDefault();
        dragging = false;
        pickFile(event.dataTransfer?.files[0]);
    }

    async function runImport() {
        if (busy) return;
        const anilistProfileMode =
            provider === "anilist" && anilistMode === "profile";
        const steamProfileMode =
            provider === "steam" && steamMode === "profile";

        if (anilistProfileMode) {
            if (!anilistUsername.trim()) {
                error = i18n.t.importModal.anilistUsernameError;
                return;
            }
        } else if (steamProfileMode) {
            if (!steamProfile.trim()) {
                error = i18n.t.importModal.steamRequired;
                return;
            }
        } else {
            if (!file) {
                error = i18n.t.importModal.selectFileError;
                return;
            }
            const ext = file.name.split(".").pop()?.toLowerCase();
            if (!ext || !allowedExtensions.includes(ext)) {
                error = i18n.t.importModal.invalidFile;
                return;
            }
        }

        if (addToList && listMode === "existing" && !targetListId) {
            error = i18n.t.importModal.chooseListError;
            return;
        }
        if (addToList && listMode === "new" && !newListName.trim()) {
            error = i18n.t.importModal.listNameError;
            return;
        }

        busy = true;
        error = "";
        try {
            const listFields = addToList
                ? listMode === "existing"
                    ? { targetListId }
                    : { newListName: newListName.trim() }
                : {};

            let importTask: Promise<ImportResultDto>;

            if (anilistProfileMode) {
                importTask = importAniListProfile({
                    username: anilistUsername.trim(),
                    skipDuplicates,
                    ...listFields,
                });
            } else if (steamProfileMode) {
                const value = steamProfile.trim();
                importTask = importSteamProfile({
                    ...(/^\d{17}$/.test(value)
                        ? { steamId: value }
                        : { profileUrl: value }),
                    steamApiKey: steamApiKey.trim() || undefined,
                    skipDuplicates,
                    ...listFields,
                });
            } else {
                const form = new FormData();
                form.append("file", file!);
                form.append("provider", provider);
                form.append("skipDuplicates", String(skipDuplicates));
                if (addToList && listMode === "existing")
                    form.append("targetListId", targetListId);
                if (addToList && listMode === "new")
                    form.append("newListName", newListName.trim());
                importTask = importFile(form);
            }

            const saveKeyTask =
                provider === "steam" &&
                steamProfileMode &&
                saveSteamKey &&
                steamApiKey.trim()
                    ? saveSourceKey("steam", steamApiKey.trim())
                    : Promise.resolve();

            [result] = await Promise.all([importTask, saveKeyTask]);
            onImportCompleted?.();
            void loadListsAndSources();
        } catch (caught) {
            error =
                caught instanceof Error
                    ? caught.message
                    : i18n.t.importModal.failed;
        } finally {
            busy = false;
        }
    }

    function resetImport() {
        result = null;
        file = null;
        error = "";
    }

    const templateJson = `[
  {
    "title": "Fullmetal Alchemist: Brotherhood",
    "type": "anime",
    "status": "completed",
    "score": 9,
    "progress": 64,
    "totalCount": 64,
    "studio": "Bones",
    "releaseYear": 2009
  },
  {
    "title": "Берсерк",
    "type": "манга",
    "status": "читаю",
    "score": 10,
    "progress": 350,
    "totalCount": 374,
    "author": "Кэнтаро Миура",
    "year": 1989
  }
]`;

    const templateCsv =
        "title,type,status,score,progress,totalCount,author,releaseYear";

    async function copyJsonTemplate() {
        try {
            await navigator.clipboard.writeText(templateJson);
            templateCopied = true;
            setTimeout(() => (templateCopied = false), 2000);
        } catch {
            error = i18n.t.importModal.templateCopyFailed;
        }
    }

    async function copyCsvTemplate() {
        try {
            await navigator.clipboard.writeText(templateCsv);
            csvCopied = true;
            setTimeout(() => (csvCopied = false), 2000);
        } catch {
            error = i18n.t.importModal.templateCopyFailed;
        }
    }
</script>

<div class="space-y-6">
    <!-- Section Header -->
    <div class="flex items-start justify-between gap-4">
        <div>
            <h2 class="text-base font-semibold text-ink sm:text-lg">
                {i18n.t.importModal.title}
            </h2>
            <p class="mt-1 text-xs text-muted sm:text-sm">
                {i18n.t.importModal.description}
            </p>
        </div>
        {#if showCloseButton && onClose}
            <button
                type="button"
                class="grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-white/10 hover:text-white"
                aria-label={i18n.t.common.close}
                onclick={onClose}
            >
                <X size={18} />
            </button>
        {/if}
    </div>

    <!-- Block 4 (Result State): displayed when an import completes successfully -->
    {#if result}
        <section
            class="rounded-xl border border-emerald-400/25 bg-emerald-500/10 p-6 shadow-lg shadow-black/20"
            aria-live="polite"
        >
            <div class="flex items-center gap-3">
                <div class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-emerald-400/20 text-emerald-300">
                    <CheckCircle2 size={24} />
                </div>
                <div>
                    <h3 class="text-base font-semibold text-emerald-200">
                        {i18n.t.importModal.success}
                    </h3>
                    <p class="text-xs text-emerald-300/80">
                        {selectedProviderInfo.title}
                    </p>
                </div>
            </div>

            <div class="mt-5 grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div class="rounded-lg border border-white/10 bg-card/60 p-3.5">
                    <span class="block text-xs text-muted">{i18n.t.importModal.total}</span>
                    <span class="mt-1 block text-xl font-bold text-ink">{result.totalFound}</span>
                </div>
                <div class="rounded-lg border border-emerald-400/20 bg-emerald-400/5 p-3.5">
                    <span class="block text-xs text-emerald-300/80">{i18n.t.importModal.imported}</span>
                    <span class="mt-1 block text-xl font-bold text-emerald-200">{result.importedCount}</span>
                </div>
                <div class="rounded-lg border border-white/10 bg-card/60 p-3.5">
                    <span class="block text-xs text-muted">{i18n.t.importModal.skipped}</span>
                    <span class="mt-1 block text-xl font-bold text-ink">{result.skippedDuplicates}</span>
                </div>
            </div>

            <div class="mt-6 flex flex-wrap items-center gap-3">
                {#if result.targetListId}
                    <button
                        type="button"
                        class="cursor-pointer rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:bg-accent-hover"
                        onclick={() => {
                            if (result?.targetListId) {
                                onNavigateToList?.(result.targetListId);
                            }
                        }}
                    >
                        {i18n.t.importModal.openList}
                    </button>
                {/if}
                <button
                    type="button"
                    class="cursor-pointer rounded-lg border border-white/10 bg-field px-4 py-2 text-sm font-medium text-ink transition hover:bg-elevated hover:text-white"
                    onclick={resetImport}
                >
                    {i18n.t.importModal.importAnother}
                </button>
                {#if showCloseButton && onClose}
                    <button
                        type="button"
                        class="cursor-pointer rounded-lg border border-white/10 px-4 py-2 text-sm text-muted transition hover:bg-white/5 hover:text-ink"
                        onclick={onClose}
                    >
                        {i18n.t.common.close}
                    </button>
                {/if}
            </div>
        </section>
    {:else}
        <!-- Block 1: Source Selection -->
        <section class="space-y-3">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-muted">
                {i18n.t.importModal.source}
            </h3>
            <div class="grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-4">
                {#each providers as item (item.id)}
                    {@const isSelected = provider === item.id}
                    <button
                        type="button"
                        class={`group relative flex items-center gap-3 rounded-xl border p-3 text-left transition cursor-pointer ${
                            isSelected
                                ? "shadow-md ring-1 ring-inset"
                                : "border-white/10 bg-card/80 hover:border-white/20 hover:bg-card"
                        }`}
                        style={isSelected
                            ? `border-color: ${item.accent}; --tw-ring-color: ${item.accent}40; background-color: ${item.accent}12;`
                            : undefined}
                        onclick={() => selectProvider(item.id)}
                    >
                        <span
                            class="grid h-10 w-10 shrink-0 place-items-center rounded-lg font-bold text-sm transition"
                            style={`background-color: ${item.accent}20; color: ${item.accent};`}
                        >
                            {item.icon}
                        </span>
                        <div class="min-w-0 flex-1">
                            <span class="block truncate text-sm font-semibold text-ink group-hover:text-white">
                                {item.title}
                            </span>
                            <span class="mt-0.5 block truncate text-xs text-muted">
                                {item.subtitle}
                            </span>
                        </div>
                        {#if isSelected}
                            <span
                                class="shrink-0 rounded-full p-0.5"
                                style={`color: ${item.accent};`}
                            >
                                <Check size={16} />
                            </span>
                        {/if}
                    </button>
                {/each}
            </div>
        </section>

        <!-- Block 2: Context fields for selected source -->
        <section class="space-y-3">
            <div class="flex items-center justify-between">
                <h3 class="text-xs font-semibold uppercase tracking-wider text-muted">
                    {i18n.t.importModal.fileLabel}
                </h3>
                <span class="text-xs font-medium" style={`color: ${selectedProviderInfo.accent};`}>
                    {selectedProviderInfo.title}
                </span>
            </div>

            <!-- AniList: Toggle between Profile and File -->
            {#if provider === "anilist"}
                <div class="space-y-3">
                    <div class="flex gap-2" role="tablist">
                        <button
                            type="button"
                            role="tab"
                            aria-selected={anilistMode === "profile"}
                            class={`flex-1 rounded-lg border px-3.5 py-2 text-xs font-medium transition cursor-pointer ${
                                anilistMode === "profile"
                                    ? "border-[#02a9ff] bg-[#02a9ff]/15 text-white font-semibold"
                                    : "border-white/10 bg-card/60 text-muted hover:text-ink hover:bg-card"
                            }`}
                            onclick={() => {
                                anilistMode = "profile";
                                file = null;
                                error = "";
                            }}
                        >
                            {i18n.t.importModal.anilistProfileTab}
                        </button>
                        <button
                            type="button"
                            role="tab"
                            aria-selected={anilistMode === "file"}
                            class={`flex-1 rounded-lg border px-3.5 py-2 text-xs font-medium transition cursor-pointer ${
                                anilistMode === "file"
                                    ? "border-[#02a9ff] bg-[#02a9ff]/15 text-white font-semibold"
                                    : "border-white/10 bg-card/60 text-muted hover:text-ink hover:bg-card"
                            }`}
                            onclick={() => {
                                anilistMode = "file";
                                error = "";
                            }}
                        >
                            {i18n.t.importModal.anilistFileTab}
                        </button>
                    </div>

                    {#if anilistMode === "profile"}
                        <div class="rounded-xl border border-white/[0.08] bg-card/50 p-4 space-y-2">
                            <label
                                class="block text-xs font-medium text-muted"
                                for="anilist-username"
                            >
                                {i18n.t.importModal.anilistUsername}
                            </label>
                            <div class="flex gap-2">
                                <input
                                    id="anilist-username"
                                    bind:value={anilistUsername}
                                    placeholder={i18n.t.importModal.anilistUsernamePlaceholder}
                                    class="min-w-0 flex-1 rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                                    onkeydown={(e) => {
                                        if (e.key === "Enter") void runImport();
                                    }}
                                />
                                <button
                                    type="button"
                                    class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-[#02a9ff] px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:cursor-wait disabled:opacity-60"
                                    disabled={busy}
                                    onclick={() => void runImport()}
                                >
                                    {#if busy}
                                        <LoaderCircle size={16} class="animate-spin" />
                                    {/if}
                                    {i18n.t.importModal.import}
                                </button>
                            </div>
                        </div>
                    {:else}
                        <!-- AniList JSON File Drag & Drop -->
                        <div
                            class={`relative flex flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition cursor-pointer ${
                                dragging
                                    ? "border-[#02a9ff] bg-[#02a9ff]/10"
                                    : file
                                      ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                                      : "border-white/15 bg-card/60 hover:border-white/30 hover:bg-card"
                            }`}
                            ondragover={(e) => {
                                e.preventDefault();
                                dragging = true;
                            }}
                            ondragleave={() => (dragging = false)}
                            ondrop={handleDrop}
                            onclick={() => fileInputRef?.click()}
                            role="button"
                            tabindex="0"
                            onkeydown={(e) => {
                                if (e.key === "Enter" || e.key === " ") fileInputRef?.click();
                            }}
                        >
                            <input
                                bind:this={fileInputRef}
                                class="hidden"
                                type="file"
                                accept={fileAccept}
                                onchange={(e) => pickFile(e.currentTarget.files?.[0])}
                            />
                            {#if file}
                                <div class="flex flex-col items-center gap-2">
                                    <div class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400">
                                        <FileText size={24} />
                                    </div>
                                    <div>
                                        <p class="text-sm font-semibold text-ink">{file.name}</p>
                                        <p class="text-xs text-muted">{(file.size / 1024).toFixed(1)} KB</p>
                                    </div>
                                    <button
                                        type="button"
                                        class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                        onclick={(e) => {
                                            e.stopPropagation();
                                            file = null;
                                            if (fileInputRef) fileInputRef.value = "";
                                        }}
                                    >
                                        {i18n.t.importModal.changeFile}
                                    </button>
                                </div>
                            {:else}
                                <div class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2">
                                    <Upload size={20} />
                                </div>
                                <span class="block text-sm font-medium text-ink">
                                    {i18n.t.importModal.dropFile}
                                </span>
                                <span class="mt-1 block text-xs text-muted">
                                    {i18n.t.importModal.formats(fileAccept)}
                                </span>
                            {/if}
                        </div>
                    {/if}

                    <p class="text-xs leading-relaxed text-muted">
                        {helpText}
                    </p>
                </div>

            <!-- Steam: Toggle between Profile and File -->
            {:else if provider === "steam"}
                <div class="space-y-3">
                    <div class="flex gap-2" role="tablist">
                        <button
                            type="button"
                            role="tab"
                            aria-selected={steamMode === "profile"}
                            class={`flex-1 rounded-lg border px-3.5 py-2 text-xs font-medium transition cursor-pointer ${
                                steamMode === "profile"
                                    ? "border-[#66c0f4] bg-[#66c0f4]/15 text-white font-semibold"
                                    : "border-white/10 bg-card/60 text-muted hover:text-ink hover:bg-card"
                            }`}
                            onclick={() => {
                                steamMode = "profile";
                                file = null;
                                error = "";
                            }}
                        >
                            {i18n.t.importModal.steamProfileTab}
                        </button>
                        <button
                            type="button"
                            role="tab"
                            aria-selected={steamMode === "file"}
                            class={`flex-1 rounded-lg border px-3.5 py-2 text-xs font-medium transition cursor-pointer ${
                                steamMode === "file"
                                    ? "border-[#66c0f4] bg-[#66c0f4]/15 text-white font-semibold"
                                    : "border-white/10 bg-card/60 text-muted hover:text-ink hover:bg-card"
                            }`}
                            onclick={() => {
                                steamMode = "file";
                                error = "";
                            }}
                        >
                            {i18n.t.importModal.steamFileTab}
                        </button>
                    </div>

                    {#if steamMode === "profile"}
                        <div class="rounded-xl border border-white/[0.08] bg-card/50 p-4 space-y-3.5">
                            <div>
                                <label
                                    class="mb-1 block text-xs font-medium text-muted"
                                    for="steam-profile"
                                >
                                    {i18n.t.importModal.steamProfile}
                                </label>
                                <div class="flex gap-2">
                                    <input
                                        id="steam-profile"
                                        bind:value={steamProfile}
                                        oninput={() => (profileChecked = false)}
                                        placeholder="https://steamcommunity.com/id/... or 76561198..."
                                        class="min-w-0 flex-1 rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                                    />
                                    <button
                                        type="button"
                                        class="cursor-pointer rounded-lg border border-white/10 bg-field px-3.5 text-xs font-medium text-ink transition hover:bg-elevated hover:text-white"
                                        onclick={() => {
                                            const val = steamProfile.trim();
                                            profileChecked =
                                                /^\d{17}$/.test(val) ||
                                                /^https?:\/\/(www\.)?steamcommunity\.com\/(id|profiles)\/[^/]+\/?$/i.test(
                                                    val
                                                );
                                            error = profileChecked
                                                ? ""
                                                : i18n.t.importModal.steamRequired;
                                        }}
                                    >
                                        {i18n.t.importModal.checkProfile}
                                    </button>
                                </div>
                                {#if profileChecked}
                                    <p class="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-300">
                                        <Check size={14} />
                                        {i18n.t.importModal.profileValid}
                                    </p>
                                {/if}
                            </div>

                            <div>
                                <label
                                    class="mb-1 block text-xs font-medium text-muted"
                                    for="steam-api-key"
                                >
                                    {i18n.t.importModal.steamApiKey}
                                </label>
                                <input
                                    id="steam-api-key"
                                    type="password"
                                    bind:value={steamApiKey}
                                    autocomplete="off"
                                    placeholder="••••••••••••••••••••••••••••••••"
                                    class="w-full rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                                />
                                {#if steamKeyConfigured}
                                    <p class="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-300">
                                        <Check size={14} />
                                        {i18n.t.importModal.steamKeyConfigured}
                                    </p>
                                {/if}
                            </div>

                            <label class="flex items-center gap-2 text-xs text-ink cursor-pointer select-none">
                                <input
                                    type="checkbox"
                                    bind:checked={saveSteamKey}
                                    class="rounded border-white/20 bg-field accent-accent"
                                />
                                <span>{i18n.t.importModal.saveSteamKey}</span>
                            </label>
                        </div>
                    {:else}
                        <!-- Steam JSON File Drag & Drop -->
                        <div
                            class={`relative flex flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition cursor-pointer ${
                                dragging
                                    ? "border-[#66c0f4] bg-[#66c0f4]/10"
                                    : file
                                      ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                                      : "border-white/15 bg-card/60 hover:border-white/30 hover:bg-card"
                            }`}
                            ondragover={(e) => {
                                e.preventDefault();
                                dragging = true;
                            }}
                            ondragleave={() => (dragging = false)}
                            ondrop={handleDrop}
                            onclick={() => fileInputRef?.click()}
                            role="button"
                            tabindex="0"
                            onkeydown={(e) => {
                                if (e.key === "Enter" || e.key === " ") fileInputRef?.click();
                            }}
                        >
                            <input
                                bind:this={fileInputRef}
                                class="hidden"
                                type="file"
                                accept={fileAccept}
                                onchange={(e) => pickFile(e.currentTarget.files?.[0])}
                            />
                            {#if file}
                                <div class="flex flex-col items-center gap-2">
                                    <div class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400">
                                        <FileText size={24} />
                                    </div>
                                    <div>
                                        <p class="text-sm font-semibold text-ink">{file.name}</p>
                                        <p class="text-xs text-muted">{(file.size / 1024).toFixed(1)} KB</p>
                                    </div>
                                    <button
                                        type="button"
                                        class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                        onclick={(e) => {
                                            e.stopPropagation();
                                            file = null;
                                            if (fileInputRef) fileInputRef.value = "";
                                        }}
                                    >
                                        {i18n.t.importModal.changeFile}
                                    </button>
                                </div>
                            {:else}
                                <div class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2">
                                    <Upload size={20} />
                                </div>
                                <span class="block text-sm font-medium text-ink">
                                    {i18n.t.importModal.dropFile}
                                </span>
                                <span class="mt-1 block text-xs text-muted">
                                    {i18n.t.importModal.formats(fileAccept)}
                                </span>
                            {/if}
                        </div>
                    {/if}

                    <p class="text-xs leading-relaxed text-muted">
                        {helpText}
                        <a
                            href="https://steamcommunity.com/dev/apikey"
                            target="_blank"
                            rel="noreferrer"
                            class="inline-flex items-center gap-1 text-accent-soft underline hover:text-white"
                        >
                            steamcommunity.com/dev/apikey
                            <ExternalLink size={12} />
                        </a>
                    </p>
                </div>

            <!-- Custom File: Drag & Drop + Template Accordion -->
            {:else if provider === "custom"}
                <div class="space-y-3">
                    <div
                        class={`relative flex flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition cursor-pointer ${
                            dragging
                                ? "border-[#a78bfa] bg-[#a78bfa]/10"
                                : file
                                  ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                                  : "border-white/15 bg-card/60 hover:border-white/30 hover:bg-card"
                        }`}
                        ondragover={(e) => {
                            e.preventDefault();
                            dragging = true;
                        }}
                        ondragleave={() => (dragging = false)}
                        ondrop={handleDrop}
                        onclick={() => fileInputRef?.click()}
                        role="button"
                        tabindex="0"
                        onkeydown={(e) => {
                            if (e.key === "Enter" || e.key === " ") fileInputRef?.click();
                        }}
                    >
                        <input
                            bind:this={fileInputRef}
                            class="hidden"
                            type="file"
                            accept={fileAccept}
                            onchange={(e) => pickFile(e.currentTarget.files?.[0])}
                        />
                        {#if file}
                            <div class="flex flex-col items-center gap-2">
                                <div class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400">
                                    <FileText size={24} />
                                </div>
                                <div>
                                    <p class="text-sm font-semibold text-ink">{file.name}</p>
                                    <p class="text-xs text-muted">{(file.size / 1024).toFixed(1)} KB</p>
                                </div>
                                <button
                                    type="button"
                                    class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                    onclick={(e) => {
                                        e.stopPropagation();
                                        file = null;
                                        if (fileInputRef) fileInputRef.value = "";
                                    }}
                                >
                                    {i18n.t.importModal.changeFile}
                                </button>
                            </div>
                        {:else}
                            <div class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2">
                                <Upload size={20} />
                            </div>
                            <span class="block text-sm font-medium text-ink">
                                {i18n.t.importModal.dropFile}
                            </span>
                            <span class="mt-1 block text-xs text-muted">
                                {i18n.t.importModal.formats(fileAccept)}
                            </span>
                        {/if}
                    </div>

                    <p class="text-xs leading-relaxed text-muted">
                        {helpText}
                    </p>

                    <!-- Template Accordion -->
                    <div class="rounded-xl border border-white/[0.08] bg-card/60">
                        <button
                            type="button"
                            aria-expanded={showTemplate}
                            class="flex w-full items-center justify-between p-3.5 text-left text-xs font-medium text-ink transition hover:bg-white/5 cursor-pointer"
                            onclick={() => (showTemplate = !showTemplate)}
                        >
                            <span class="flex items-center gap-2">
                                <FileText size={16} class="text-[#a78bfa]" />
                                <span>{showTemplate ? i18n.t.importModal.hideTemplate : i18n.t.importModal.showTemplate}</span>
                            </span>
                            {#if showTemplate}
                                <ChevronUp size={16} class="text-muted" />
                            {:else}
                                <ChevronDown size={16} class="text-muted" />
                            {/if}
                        </button>

                        {#if showTemplate}
                            <div class="border-t border-white/[0.08] p-4 space-y-3 bg-black/20">
                                <div>
                                    <div class="mb-1.5 flex items-center justify-between">
                                        <span class="text-xs font-semibold uppercase tracking-wider text-muted">
                                            {i18n.t.importModal.templateJsonLabel}
                                        </span>
                                        <button
                                            type="button"
                                            class="inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 bg-field px-2.5 py-1 text-xs text-ink transition hover:bg-elevated hover:text-white"
                                            onclick={() => void copyJsonTemplate()}
                                        >
                                            {#if templateCopied}
                                                <Check size={12} class="text-emerald-400" />
                                                <span class="text-emerald-300">{i18n.t.importModal.templateCopied}</span>
                                            {:else}
                                                <Copy size={12} />
                                                <span>{i18n.t.importModal.copyTemplate}</span>
                                            {/if}
                                        </button>
                                    </div>
                                    <pre class="max-h-44 overflow-auto rounded-lg border border-white/10 bg-black/40 p-3 text-[11px] leading-relaxed text-emerald-300 thin-scroll font-mono">{templateJson}</pre>
                                </div>

                                <div>
                                    <div class="mb-1.5 flex items-center justify-between">
                                        <span class="text-xs font-semibold uppercase tracking-wider text-muted">
                                            {i18n.t.importModal.templateCsvLabel}
                                        </span>
                                        <button
                                            type="button"
                                            class="inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 bg-field px-2.5 py-1 text-xs text-ink transition hover:bg-elevated hover:text-white"
                                            onclick={() => void copyCsvTemplate()}
                                        >
                                            {#if csvCopied}
                                                <Check size={12} class="text-emerald-400" />
                                                <span class="text-emerald-300">{i18n.t.importModal.templateCopied}</span>
                                            {:else}
                                                <Copy size={12} />
                                                <span>{i18n.t.importModal.copyTemplate}</span>
                                            {/if}
                                        </button>
                                    </div>
                                    <pre class="overflow-auto rounded-lg border border-white/10 bg-black/40 p-2.5 text-[11px] text-emerald-300 thin-scroll font-mono">{templateCsv}</pre>
                                </div>
                            </div>
                        {/if}
                    </div>
                </div>

            <!-- Standard Providers (MAL, Shikimori, Letterboxd, Goodreads, MangaLib) -->
            {:else}
                <div class="space-y-3">
                    <div
                        class={`relative flex flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition cursor-pointer ${
                            dragging
                                ? "border-accent bg-accent/10"
                                : file
                                  ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                                  : "border-white/15 bg-card/60 hover:border-white/30 hover:bg-card"
                        }`}
                        ondragover={(e) => {
                            e.preventDefault();
                            dragging = true;
                        }}
                        ondragleave={() => (dragging = false)}
                        ondrop={handleDrop}
                        onclick={() => fileInputRef?.click()}
                        role="button"
                        tabindex="0"
                        onkeydown={(e) => {
                            if (e.key === "Enter" || e.key === " ") fileInputRef?.click();
                        }}
                    >
                        <input
                            bind:this={fileInputRef}
                            class="hidden"
                            type="file"
                            accept={fileAccept}
                            onchange={(e) => pickFile(e.currentTarget.files?.[0])}
                        />
                        {#if file}
                            <div class="flex flex-col items-center gap-2">
                                <div class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400">
                                    <FileText size={24} />
                                </div>
                                <div>
                                    <p class="text-sm font-semibold text-ink">{file.name}</p>
                                    <p class="text-xs text-muted">{(file.size / 1024).toFixed(1)} KB</p>
                                </div>
                                <button
                                    type="button"
                                    class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                    onclick={(e) => {
                                        e.stopPropagation();
                                        file = null;
                                        if (fileInputRef) fileInputRef.value = "";
                                    }}
                                >
                                    {i18n.t.importModal.changeFile}
                                </button>
                            </div>
                        {:else}
                            <div class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2">
                                <Upload size={20} />
                            </div>
                            <span class="block text-sm font-medium text-ink">
                                {i18n.t.importModal.dropFile}
                            </span>
                            <span class="mt-1 block text-xs text-muted">
                                {i18n.t.importModal.formats(fileAccept)}
                            </span>
                        {/if}
                    </div>

                    <p class="text-xs leading-relaxed text-muted">
                        {helpText}
                    </p>
                </div>
            {/if}
        </section>

        <!-- Block 3: Import Options -->
        <section class="rounded-xl border border-white/[0.08] bg-card/60 p-4 space-y-3.5">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-muted">
                {i18n.t.importModal.optionsTitle}
            </h3>

            <div class="space-y-2.5">
                <label class="flex items-center gap-2.5 text-sm text-ink cursor-pointer select-none">
                    <input
                        type="checkbox"
                        bind:checked={skipDuplicates}
                        class="rounded border-white/20 bg-field accent-accent"
                    />
                    <span>{i18n.t.importModal.skipDuplicates}</span>
                </label>

                <label class="flex items-center gap-2.5 text-sm text-ink cursor-pointer select-none">
                    <input
                        type="checkbox"
                        bind:checked={addToList}
                        class="rounded border-white/20 bg-field accent-accent"
                    />
                    <span>{i18n.t.importModal.addToList}</span>
                </label>
            </div>

            {#if addToList}
                <div class="ml-6 space-y-3 border-l-2 border-white/10 pl-4 pt-1">
                    <div class="flex flex-wrap gap-4 text-xs">
                        <label class="flex items-center gap-2 text-ink cursor-pointer">
                            <input
                                type="radio"
                                bind:group={listMode}
                                value="new"
                                class="accent-accent"
                            />
                            <span>{i18n.t.importModal.newList}</span>
                        </label>
                        <label class="flex items-center gap-2 text-ink cursor-pointer">
                            <input
                                type="radio"
                                bind:group={listMode}
                                value="existing"
                                class="accent-accent"
                            />
                            <span>{i18n.t.importModal.existingList}</span>
                        </label>
                    </div>

                    {#if listMode === "new"}
                        <div>
                            <input
                                bind:value={newListName}
                                placeholder={defaultListName}
                                maxlength="100"
                                class="w-full rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                            />
                        </div>
                    {:else}
                        <div>
                            <select
                                bind:value={targetListId}
                                class="w-full rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft cursor-pointer"
                            >
                                <option value="">{i18n.t.importModal.selectList}</option>
                                {#each lists as list (list.id)}
                                    <option value={list.id}>{list.name}</option>
                                {/each}
                            </select>
                        </div>
                    {/if}
                </div>
            {/if}
        </section>

        <!-- Error alert -->
        {#if error}
            <div
                class="flex items-center gap-2.5 rounded-lg border border-rose-400/25 bg-rose-400/10 p-3.5 text-xs text-rose-200"
                role="alert"
            >
                <span class="shrink-0 font-bold">!</span>
                <span>{error}</span>
            </div>
        {/if}

        <!-- Block 4: Launch button -->
        <div class="flex justify-end pt-2">
            <button
                type="button"
                disabled={busy}
                class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-accent px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-accent-hover disabled:cursor-wait disabled:opacity-60 shadow-md shadow-accent/20"
                onclick={() => void runImport()}
            >
                {#if busy}
                    <LoaderCircle size={16} class="animate-spin" />
                    <span>{i18n.t.importModal.importing}</span>
                {:else}
                    <span>{i18n.t.importModal.start}</span>
                {/if}
            </button>
        </div>
    {/if}
</div>
