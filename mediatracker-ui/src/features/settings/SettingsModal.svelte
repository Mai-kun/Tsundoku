<script lang="ts">
    import {
        AlertCircle,
        AlertTriangle,
        ArrowDown,
        BookOpen,
        Check,
        ChevronDown,
        ChevronUp,
        Eye,
        EyeOff,
        FolderInput,
        Key,
        LoaderCircle,
        RefreshCw,
        RotateCcw,
        Search,
        Server,
        Settings,
        ShieldCheck,
        Trash2,
        X,
    } from "$shared/ui/Icons.svelte";
    import { onMount } from "svelte";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import {
        errorMessage,
        exportBackup,
        getCategoryOrder,
        getSources,
        getSourcePriority,
        restoreBackup,
        resetAllData,
        saveCategoryOrder,
        saveSourceKey,
        saveSourcePriority,
        testSourceConnection,
        toggleSourceEnabled,
    } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import ImportPanel from "$features/import-media/ImportPanel.svelte";
    import type { ConnectionTestResult, SourceInfo } from "$shared/types";

    interface Props {
        isOpen: boolean;
        onClose: () => void;
        onImportCompleted: () => void;
        onNavigateToList?: (id: string) => void;
    }

    let { isOpen, onClose, onImportCompleted, onNavigateToList }: Props = $props();

    type Tab = "sources" | "search" | "backup" | "import" | "reading";
    let activeTab = $state<Tab>("sources");

    let readingBookPageMinutes = $state(uiSettings.bookPageMinutes);
    let readingMangaChapterMinutes = $state(uiSettings.mangaChapterMinutes);
    let isSavingReading = $state(false);

    $effect(() => {
        if (isOpen) {
            readingBookPageMinutes = uiSettings.bookPageMinutes;
            readingMangaChapterMinutes = uiSettings.mangaChapterMinutes;
        }
    });

    async function handleSaveReadingSpeed() {
        if (isSavingReading) return;
        const bookMin = Number(readingBookPageMinutes);
        const mangaMin = Number(readingMangaChapterMinutes);

        if (isNaN(bookMin) || bookMin < 0.2 || bookMin > 10.0) {
            showToast("Скорость чтения книг должна быть от 0.2 до 10.0 мин/стр", "error");
            return;
        }
        if (isNaN(mangaMin) || mangaMin < 0.5 || mangaMin > 30.0) {
            showToast("Скорость чтения манги должна быть от 0.5 до 30.0 мин/гл", "error");
            return;
        }

        isSavingReading = true;
        try {
            await uiSettings.setReadingSpeed(bookMin, mangaMin);
            showToast(i18n.t.settingsModal.reading.savedToast, "success");
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
        } finally {
            isSavingReading = false;
        }
    }

    let isExporting = $state(false);
    let isRestoring = $state(false);
    let selectedBackupFile = $state<File | null>(null);
    let showRestoreConfirm = $state(false);
    let showResetConfirm = $state(false);
    let isResetting = $state(false);
    let keepApiKeys = $state(true);
    let resetConfirmationInput = $state("");
    let fileInputRef = $state<HTMLInputElement | null>(null);

    async function handleExportBackup() {
        if (isExporting) return;
        isExporting = true;
        try {
            const blob = await exportBackup();
            const url = URL.createObjectURL(blob);
            const now = new Date();
            const pad = (n: number) => String(n).padStart(2, "0");
            const timestamp = `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
            const fileName = `tsundoku-backup-${timestamp}.zip`;

            const a = document.createElement("a");
            a.href = url;
            a.download = fileName;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
        } finally {
            isExporting = false;
        }
    }

    function handleFileSelected(event: Event) {
        const input = event.target as HTMLInputElement;
        if (input.files && input.files[0]) {
            selectedBackupFile = input.files[0];
            showRestoreConfirm = true;
        }
        input.value = "";
    }

    async function handleConfirmRestore() {
        if (!selectedBackupFile || isRestoring) return;
        isRestoring = true;
        try {
            await restoreBackup(selectedBackupFile);
            showRestoreConfirm = false;
            selectedBackupFile = null;
            showToast(i18n.t.settingsModal.backup.restoreSuccess, "success", 5000);
            setTimeout(() => {
                window.location.reload();
            }, 1500);
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
            isRestoring = false;
        }
    }

    function handleCancelRestore() {
        if (isRestoring) return;
        showRestoreConfirm = false;
        selectedBackupFile = null;
    }

    function handleCancelReset() {
        if (isResetting) return;
        showResetConfirm = false;
        resetConfirmationInput = "";
        keepApiKeys = true;
    }

    async function handleConfirmReset() {
        if (isResetting || resetConfirmationInput.trim() !== i18n.t.settingsModal.backup.confirmationWord) return;
        isResetting = true;
        try {
            await resetAllData(keepApiKeys);
            showResetConfirm = false;
            showToast(i18n.t.settingsModal.backup.resetSuccess, "success", 5000);
            setTimeout(() => {
                window.location.href = "/";
            }, 1000);
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
            isResetting = false;
        }
    }

    let sources = $state<SourceInfo[]>([]);
    let sourcesLoading = $state(false);
    let sourcesError = $state<unknown>(null);

    let selectedTypeFilter = $state<string>("all");
    let filteredSources = $derived(
        (selectedTypeFilter === "all"
            ? sources
            : sources.filter((s) => s.mediaTypes.includes(selectedTypeFilter))
        )
            .slice()
            .sort((a, b) => Number(b.isEnabled) - Number(a.isEnabled)),
    );

    let inputKeys = $state<Record<string, string>>({});
    let showKeys = $state<Record<string, boolean>>({});
    let savingKey = $state("");
    let keySuccess = $state<Record<string, string>>({});
    let keyErrors = $state<Record<string, unknown>>({});
    let togglingSource = $state<string>("");
    let testingSource = $state<string>("");
    let testResults = $state<Record<string, ConnectionTestResult>>({});

    let categoryOrder = $state<string[]>([]);
    let orderLoading = $state(false);
    let orderSaving = $state(false);
    let orderSuccess = $state(false);

    const defaultCategories = [
        "anime",
        "movie",
        "tvshow",
        "manga",
        "game",
        "book",
    ];

    const defaultPriority: Record<string, string[]> = {
        anime: ["anilist", "shikimori", "kitsu", "simkl", "jikan"],
        manga: ["anilist", "shikimori", "mangadex", "mangaupdates", "jikan"],
        movie: ["tmdb", "imdb", "kinopoisk", "simkl", "thetvdb"],
        tvshow: ["tmdb", "imdb", "kinopoisk", "simkl", "thetvdb"],
        game: ["rawg", "steam", "igdb"],
        book: ["openlibrary", "googlebooks"],
    };

    let sourcePriority = $state<Record<string, string[]>>({
        ...defaultPriority,
    });
    let priorityLoading = $state(false);
    let prioritySaving = $state(false);

    $effect(() => {
        if (isOpen) {
            void loadSources();
            void loadOrder();
            void loadPriority();
        }
    });

    async function loadSources() {
        sourcesLoading = true;
        sourcesError = null;
        try {
            sources = await getSources();
        } catch (e) {
            sourcesError = e;
        } finally {
            sourcesLoading = false;
        }
    }

    async function loadOrder() {
        orderLoading = true;
        try {
            categoryOrder = await getCategoryOrder();
        } catch {
            categoryOrder = [...defaultCategories];
        } finally {
            orderLoading = false;
        }
    }

    async function loadPriority() {
        priorityLoading = true;
        try {
            sourcePriority = await getSourcePriority();
        } catch {
            sourcePriority = { ...defaultPriority };
        } finally {
            priorityLoading = false;
        }
    }

    async function handleSaveKey(sourceId: string) {
        const key = inputKeys[sourceId]?.trim() ?? "";
        savingKey = sourceId;
        keyErrors[sourceId] = null;
        keySuccess[sourceId] = "";

        try {
            const res = await saveSourceKey(sourceId, key);
            keySuccess[sourceId] = i18n.t.settingsModal.sources.saved;
            showToast(i18n.t.settingsModal.sources.saved, "success");
            // Update local source record
            const s = sources.find((x) => x.id === sourceId);
            if (s) {
                s.hasKey = res.hasKey;
                s.isConfigured = res.hasKey;
                s.maskedKey = res.maskedKey;
            }
            inputKeys[sourceId] = "";
        } catch (e) {
            keyErrors[sourceId] = e;
            showToast(errorMessage(e), "error");
        } finally {
            savingKey = "";
        }
    }

    async function handleToggleSource(source: SourceInfo) {
        togglingSource = source.id;
        try {
            const nextState = !source.isEnabled;
            const res = await toggleSourceEnabled(source.id, nextState);
            source.isEnabled = res.isEnabled;
            sources = [...sources];
            showToast(
                res.isEnabled
                    ? `${source.name}: ${i18n.t.settingsModal.sources.enabledBadge}`
                    : `${source.name}: ${i18n.t.settingsModal.sources.disabledBadge}`,
                "success",
            );
        } catch (e) {
            showToast(errorMessage(e), "error");
        } finally {
            togglingSource = "";
        }
    }

    async function handleTestSource(sourceId: string) {
        testingSource = sourceId;
        try {
            const res = await testSourceConnection(sourceId);
            testResults[sourceId] = res;
            if (!res.success) {
                showToast(
                    res.message || i18n.t.settingsModal.sources.testFailed,
                    "error",
                );
            }
        } catch (e) {
            testResults[sourceId] = {
                success: false,
                latencyMs: 0,
                message: errorMessage(e),
            };
            showToast(errorMessage(e), "error");
        } finally {
            testingSource = "";
        }
    }

    async function moveCategory(index: number, direction: "up" | "down") {
        const newOrder = [...categoryOrder];
        const targetIndex = direction === "up" ? index - 1 : index + 1;
        if (targetIndex < 0 || targetIndex >= newOrder.length) return;

        const temp = newOrder[index];
        newOrder[index] = newOrder[targetIndex];
        newOrder[targetIndex] = temp;
        categoryOrder = newOrder;

        orderSaving = true;
        orderSuccess = false;
        try {
            await saveCategoryOrder(newOrder);
            orderSuccess = true;
            showToast(i18n.t.settingsModal.search.saved, "success");
            setTimeout(() => (orderSuccess = false), 2000);
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
        } finally {
            orderSaving = false;
        }
    }

    async function moveSourcePriority(
        type: string,
        index: number,
        direction: "up" | "down",
    ) {
        const currentList = [
            ...(sourcePriority[type] || defaultPriority[type] || []),
        ];
        const targetIndex = direction === "up" ? index - 1 : index + 1;
        if (targetIndex < 0 || targetIndex >= currentList.length) return;

        const temp = currentList[index];
        currentList[index] = currentList[targetIndex];
        currentList[targetIndex] = temp;

        sourcePriority = { ...sourcePriority, [type]: currentList };

        prioritySaving = true;
        try {
            await saveSourcePriority(sourcePriority);
            showToast(i18n.t.settingsModal.search.prioritySaved, "success");
        } catch (e) {
            console.error(e);
            showToast(errorMessage(e), "error");
        } finally {
            prioritySaving = false;
        }
    }

    function categoryLabel(cat: string): string {
        if (cat === "anime") return i18n.t.navigation.anime;
        return i18n.t.types[cat as keyof typeof i18n.t.types] || cat;
    }

    function getSourceName(id: string): string {
        const s = sources.find((x) => x.id === id);
        if (s) return s.name;
        if (id === "jikan") return "MyAnimeList (Jikan)";
        if (id === "mangaupdates") return "MangaUpdates";
        if (id === "mangadex") return "MangaDex";
        if (id === "anilist") return "AniList";
        if (id === "tmdb") return "TMDb";
        if (id === "rawg") return "RAWG";
        if (id === "openlibrary") return "OpenLibrary";
        if (id === "shikimori") return "Shikimori";
        if (id === "googlebooks") return "Google Books";
        if (id === "steam") return "Steam";
        if (id === "imdb") return "IMDb";
        if (id === "simkl") return "Simkl";
        if (id === "tvdb") return "TheTVDB";
        if (id === "kinopoisk") return "Кинопоиск";
        if (id === "igdb") return "IGDB";
        return id;
    }

    function isSourceDisabled(id: string): boolean {
        const norm = id.toLowerCase().trim();
        const s = sources.find((x) => {
            const xId = x.id.toLowerCase().trim();
            if (xId === norm) return true;
            if (
                (xId === "thetvdb" || xId === "tvdb") &&
                (norm === "thetvdb" || norm === "tvdb")
            )
                return true;
            if (
                (xId === "jikan" || xId === "myanimelist" || xId === "mal") &&
                (norm === "jikan" || norm === "myanimelist" || norm === "mal")
            )
                return true;
            if (
                (xId === "googlebooks" || xId === "google") &&
                (norm === "googlebooks" || norm === "google")
            )
                return true;
            return false;
        });
        return s ? s.isEnabled === false : false;
    }
</script>

<Modal {isOpen} {onClose} size="xl" labelledBy="settings-title">
    <div class="flex h-full flex-col min-h-0 overflow-hidden">
        <!-- Header -->
        <header
            class="flex shrink-0 items-center justify-between border-b border-white/[0.08] px-6 py-4"
        >
            <div class="flex items-center gap-3">
                <div
                    class="grid h-9 w-9 place-items-center rounded-lg bg-[#5844e0]/15 text-[#a5b4fc]"
                >
                    <Settings size={20} />
                </div>
                <div>
                    <h2
                        id="settings-title"
                        class="text-lg font-bold tracking-tight text-white"
                    >
                        {i18n.t.settingsModal.title}
                    </h2>
                </div>
            </div>
            <button
                type="button"
                class="grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-white/10 hover:text-white cursor-pointer"
                aria-label={i18n.t.common.close}
                onclick={onClose}
            >
                <X size={18} />
            </button>
        </header>

        <!-- Modal Body: 2 columns -->
        <div class="flex-1 flex min-h-0 overflow-hidden">
            <!-- Left sidebar navigation -->
            <nav
                class="w-56 sm:w-64 shrink-0 border-r border-white/[0.08] p-3 space-y-1.5 bg-[#12151c]/60 overflow-y-auto thin-scroll"
                aria-label={i18n.t.settingsModal.title}
            >
                <button
                    type="button"
                    class={`flex items-center gap-3 w-full px-3.5 py-2.5 rounded-lg text-xs text-left transition tap cursor-pointer ${
                        activeTab === "sources"
                            ? "bg-[#5844e0]/15 text-[#a5b4fc] font-semibold border border-[#5844e0]/30 shadow-sm"
                            : "text-muted hover:text-white hover:bg-white/5 font-medium border border-transparent"
                    }`}
                    onclick={() => (activeTab = "sources")}
                >
                    <Server size={16} />
                    <span>{i18n.t.settingsModal.tabs.sources}</span>
                </button>

                <button
                    type="button"
                    class={`flex items-center gap-3 w-full px-3.5 py-2.5 rounded-lg text-xs text-left transition tap cursor-pointer ${
                        activeTab === "search"
                            ? "bg-[#5844e0]/15 text-[#a5b4fc] font-semibold border border-[#5844e0]/30 shadow-sm"
                            : "text-muted hover:text-white hover:bg-white/5 font-medium border border-transparent"
                    }`}
                    onclick={() => (activeTab = "search")}
                >
                    <Search size={16} />
                    <span>{i18n.t.settingsModal.tabs.search}</span>
                </button>

                <button
                    type="button"
                    class={`flex items-center gap-3 w-full px-3.5 py-2.5 rounded-lg text-xs text-left transition tap cursor-pointer ${
                        activeTab === "backup"
                            ? "bg-[#5844e0]/15 text-[#a5b4fc] font-semibold border border-[#5844e0]/30 shadow-sm"
                            : "text-muted hover:text-white hover:bg-white/5 font-medium border border-transparent"
                    }`}
                    onclick={() => (activeTab = "backup")}
                >
                    <RotateCcw size={16} />
                    <span>{i18n.t.settingsModal.tabs.backup}</span>
                </button>

                <button
                    type="button"
                    class={`flex items-center gap-3 w-full px-3.5 py-2.5 rounded-lg text-xs text-left transition tap cursor-pointer ${
                        activeTab === "import"
                            ? "bg-[#5844e0]/15 text-[#a5b4fc] font-semibold border border-[#5844e0]/30 shadow-sm"
                            : "text-muted hover:text-white hover:bg-white/5 font-medium border border-transparent"
                    }`}
                    onclick={() => (activeTab = "import")}
                >
                    <FolderInput size={16} />
                    <span>{i18n.t.settingsModal.tabs.import}</span>
                </button>

                <button
                    type="button"
                    class={`flex items-center gap-3 w-full px-3.5 py-2.5 rounded-lg text-xs text-left transition tap cursor-pointer ${
                        activeTab === "reading"
                            ? "bg-[#5844e0]/15 text-[#a5b4fc] font-semibold border border-[#5844e0]/30 shadow-sm"
                            : "text-muted hover:text-white hover:bg-white/5 font-medium border border-transparent"
                    }`}
                    onclick={() => (activeTab = "reading")}
                >
                    <BookOpen size={16} />
                    <span>{i18n.t.settingsModal.tabs.reading}</span>
                </button>
            </nav>

            <!-- Right content area -->
            <div class="flex-1 min-w-0 p-6 overflow-y-auto thin-scroll bg-[#151a26]/40">
            {#if activeTab === "sources"}
                <div class="space-y-4">
                    <div
                        class="flex flex-wrap items-center justify-between gap-3"
                    >
                        <div>
                            <h3 class="text-sm font-semibold text-ink">
                                {i18n.t.settingsModal.sources.title}
                            </h3>
                            <p class="mt-0.5 text-xs text-muted">
                                {i18n.t.settingsModal.sources.description}
                            </p>
                        </div>

                        <!-- Media Type Filter Dropdown (Item 15) -->
                        <div class="flex items-center gap-2">
                            <label
                                for="source-type-filter"
                                class="text-xs text-muted shrink-0"
                                >{i18n.t.settingsModal.sources
                                    .filterLabel}:</label
                            >
                            <select
                                id="source-type-filter"
                                class="h-8 rounded-md border border-white/10 bg-field px-2.5 text-xs text-ink focus:border-accent-soft focus:outline-none cursor-pointer"
                                value={selectedTypeFilter}
                                onchange={(e) =>
                                    (selectedTypeFilter = (
                                        e.currentTarget as HTMLSelectElement
                                    ).value)}
                            >
                                <option value="all"
                                    >{i18n.t.settingsModal.sources
                                        .filterAll}</option
                                >
                                <option value="anime"
                                    >{i18n.t.navigation.anime}</option
                                >
                                <option value="manga"
                                    >{i18n.t.types.manga}</option
                                >
                                <option value="movie"
                                    >{i18n.t.types.movie}</option
                                >
                                <option value="tvshow"
                                    >{i18n.t.types.tvshow}</option
                                >
                                <option value="game">{i18n.t.types.game}</option
                                >
                                <option value="book">{i18n.t.types.book}</option
                                >
                            </select>
                        </div>
                    </div>

                    {#if sourcesLoading}
                        <div class="space-y-3">
                            {#each Array(4) as _, i (i)}
                                <div
                                    class="h-24 animate-pulse rounded-lg bg-card"
                                ></div>
                            {/each}
                        </div>
                    {:else if sourcesError}
                        <p
                            class="rounded-lg bg-rose-400/10 p-3 text-xs text-rose-300"
                        >
                            {errorMessage(sourcesError)}
                        </p>
                    {:else}
                        <div class="space-y-3">
                            {#each filteredSources as source (source.id)}
                                <div
                                    class="rounded-lg border border-white/10 bg-field p-4 transition {source.isEnabled ===
                                    false
                                        ? 'opacity-65'
                                        : ''}"
                                >
                                    <div
                                        class="flex flex-wrap items-start justify-between gap-3"
                                    >
                                        <div class="flex-1 min-w-[200px]">
                                            <div
                                                class="flex items-center gap-2 flex-wrap"
                                            >
                                                <h4
                                                    class="text-sm font-bold text-ink"
                                                >
                                                    {source.name}
                                                </h4>
                                                {#if !source.isEnabled}
                                                    <span
                                                        class="inline-flex items-center rounded bg-zinc-500/15 px-2 py-0.5 text-[11px] font-semibold text-zinc-400"
                                                    >
                                                        {i18n.t.settingsModal
                                                            .sources
                                                            .disabledBadge}
                                                    </span>
                                                {/if}
                                                {#if source.requiresApiKey}
                                                    {#if source.hasKey}
                                                        <span
                                                            class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 text-[11px] font-semibold text-emerald-400"
                                                        >
                                                            <Check size={12} />
                                                            {i18n.t
                                                                .settingsModal
                                                                .sources
                                                                .keyConfigured}
                                                        </span>
                                                    {:else}
                                                        <span
                                                            class="inline-flex items-center gap-1 rounded bg-amber-500/15 px-2 py-0.5 text-[11px] font-semibold text-amber-400"
                                                        >
                                                            <Key size={12} />
                                                            {i18n.t
                                                                .settingsModal
                                                                .sources
                                                                .keyRequired}
                                                        </span>
                                                    {/if}
                                                {:else}
                                                    <span
                                                        class="inline-flex items-center gap-1 rounded bg-sky-500/15 px-2 py-0.5 text-[11px] font-semibold text-sky-400"
                                                    >
                                                        <ShieldCheck
                                                            size={12}
                                                        />
                                                        {i18n.t.settingsModal
                                                            .sources
                                                            .noKeyRequired}
                                                    </span>
                                                {/if}
                                            </div>
                                            <p class="mt-1 text-xs text-muted">
                                                {source.description}
                                            </p>
                                            <div
                                                class="mt-2 flex flex-wrap gap-1.5"
                                            >
                                                {#each source.mediaTypes as mt}
                                                    <span
                                                        class="rounded bg-canvas px-2 py-0.5 text-[10px] font-medium text-muted"
                                                    >
                                                        {categoryLabel(mt)}
                                                    </span>
                                                {/each}
                                            </div>
                                        </div>

                                        <div
                                            class="flex items-center gap-2.5 shrink-0"
                                        >
                                            <button
                                                type="button"
                                                class="inline-flex h-7 items-center gap-1.5 rounded-md border border-white/10 bg-field px-2.5 text-xs font-medium text-ink transition hover:bg-card hover:border-accent-soft cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                                                disabled={testingSource ===
                                                    source.id}
                                                title={i18n.t.settingsModal
                                                    .sources.testConnection}
                                                onclick={() =>
                                                    void handleTestSource(
                                                        source.id,
                                                    )}
                                            >
                                                <RefreshCw
                                                    size={12}
                                                    class={testingSource ===
                                                    source.id
                                                        ? "animate-spin text-accent-soft"
                                                        : "text-muted"}
                                                />
                                                <span
                                                    >{testingSource ===
                                                    source.id
                                                        ? i18n.t.settingsModal
                                                              .sources.testing
                                                        : i18n.t.settingsModal
                                                              .sources
                                                              .testConnection}</span
                                                >
                                            </button>

                                            <button
                                                type="button"
                                                role="switch"
                                                aria-checked={source.isEnabled}
                                                class={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-accent-soft focus:ring-offset-2 focus:ring-offset-surface disabled:cursor-not-allowed disabled:opacity-50 ${
                                                    source.isEnabled
                                                        ? "bg-accent-soft"
                                                        : "bg-canvas"
                                                }`}
                                                onclick={() =>
                                                    void handleToggleSource(
                                                        source,
                                                    )}
                                                disabled={togglingSource ===
                                                    source.id}
                                                title={source.isEnabled
                                                    ? i18n.t.settingsModal
                                                          .sources.disable
                                                    : i18n.t.settingsModal
                                                          .sources.enable}
                                            >
                                                <span
                                                    aria-hidden="true"
                                                    class={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
                                                        source.isEnabled
                                                            ? "translate-x-5"
                                                            : "translate-x-0"
                                                    }`}
                                                ></span>
                                            </button>
                                        </div>
                                    </div>

                                    {#if testResults[source.id]}
                                        <div
                                            class="mt-2.5 flex items-center gap-1.5 text-xs"
                                        >
                                            {#if testResults[source.id].success}
                                                <span
                                                    class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 font-medium text-emerald-400"
                                                >
                                                    <Check size={12} />
                                                    {i18n.t.settingsModal.sources.testSuccess(
                                                        testResults[source.id]
                                                            .latencyMs,
                                                    )}
                                                </span>
                                            {:else}
                                                <span
                                                    class="inline-flex items-center gap-1 rounded bg-rose-500/15 px-2 py-0.5 font-medium text-rose-400"
                                                    title={testResults[
                                                        source.id
                                                    ].message}
                                                >
                                                    <AlertCircle size={12} />
                                                    {testResults[source.id]
                                                        .message ||
                                                        i18n.t.settingsModal
                                                            .sources.testFailed}
                                                </span>
                                            {/if}
                                        </div>
                                    {/if}

                                    {#if source.requiresApiKey}
                                        <div
                                            class="mt-3 border-t border-white/[0.07]/60 pt-3"
                                        >
                                            {#if source.maskedKey}
                                                <div
                                                    class="mb-2 flex items-center gap-2 text-xs text-muted"
                                                >
                                                    <span
                                                        >{i18n.t.settingsModal
                                                            .sources
                                                            .currentKey}</span
                                                    >
                                                    <code
                                                        class="rounded bg-canvas px-2 py-0.5 font-mono text-[11px] text-ink"
                                                        >{source.maskedKey}</code
                                                    >
                                                </div>
                                            {/if}

                                            <div
                                                class="flex flex-wrap items-center gap-2"
                                            >
                                                <div
                                                    class="relative flex-1 min-w-[200px]"
                                                >
                                                    <input
                                                        type={showKeys[
                                                            source.id
                                                        ]
                                                            ? "text"
                                                            : "password"}
                                                        class="h-9 w-full rounded-md border border-white/10 bg-field px-3 pr-9 text-xs text-ink placeholder:text-muted focus:border-accent-soft focus:outline-none focus:ring-1 focus:ring-accent-soft"
                                                        placeholder={source.hasKey
                                                            ? i18n.t
                                                                  .settingsModal
                                                                  .sources
                                                                  .replaceKeyPlaceholder
                                                            : i18n.t
                                                                  .settingsModal
                                                                  .sources
                                                                  .inputPlaceholder}
                                                        value={inputKeys[
                                                            source.id
                                                        ] ?? ""}
                                                        oninput={(e) =>
                                                            (inputKeys[
                                                                source.id
                                                            ] = (
                                                                e.currentTarget as HTMLInputElement
                                                            ).value)}
                                                    />
                                                    <button
                                                        type="button"
                                                        class="absolute right-2 top-1/2 -translate-y-1/2 text-muted hover:text-ink cursor-pointer"
                                                        aria-label="Toggle key visibility"
                                                        onclick={() =>
                                                            (showKeys[
                                                                source.id
                                                            ] =
                                                                !showKeys[
                                                                    source.id
                                                                ])}
                                                    >
                                                        {#if showKeys[source.id]}
                                                            <EyeOff size={14} />
                                                        {:else}
                                                            <Eye size={14} />
                                                        {/if}
                                                    </button>
                                                </div>

                                                <!-- Save key button: Item 14 pointer cursor when active, not-allowed when disabled, no cursor-wait -->
                                                <button
                                                    type="button"
                                                    class="inline-flex h-9 items-center gap-1.5 rounded-md border border-white/10 bg-field px-3 text-xs font-semibold text-ink transition hover:bg-card hover:border-accent-soft cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                                                    class:cursor-wait={savingKey ===
                                                        source.id}
                                                    disabled={savingKey ===
                                                        source.id ||
                                                        !inputKeys[
                                                            source.id
                                                        ]?.trim()}
                                                    onclick={() =>
                                                        void handleSaveKey(
                                                            source.id,
                                                        )}
                                                >
                                                    <ShieldCheck size={14} />
                                                    {savingKey === source.id
                                                        ? i18n.t.common.saving
                                                        : i18n.t.settingsModal
                                                              .sources.saveKey}
                                                </button>
                                            </div>

                                            {#if keySuccess[source.id]}
                                                <p
                                                    class="mt-2 text-xs font-medium text-emerald-400"
                                                >
                                                    {keySuccess[source.id]}
                                                </p>
                                            {/if}
                                            {#if keyErrors[source.id]}
                                                <p
                                                    class="mt-2 text-xs text-rose-300"
                                                >
                                                    {errorMessage(
                                                        keyErrors[source.id],
                                                    )}
                                                </p>
                                            {/if}
                                        </div>
                                    {/if}
                                </div>
                            {/each}
                        </div>
                    {/if}
                </div>
            {:else if activeTab === "import"}
                <ImportPanel
                    {onImportCompleted}
                    onNavigateToList={(id) => {
                        onClose();
                        onNavigateToList?.(id);
                    }}
                />
            {:else if activeTab === "search"}
                <div class="space-y-6">
                    <!-- Category order in All search -->
                    <div class="space-y-4">
                        <div>
                            <h3 class="text-sm font-semibold text-ink">
                                {i18n.t.settingsModal.search.orderTitle}
                            </h3>
                            <p class="mt-0.5 text-xs text-muted">
                                {i18n.t.settingsModal.search.orderHint}
                            </p>
                        </div>

                        {#if orderLoading}
                            <div
                                class="h-32 animate-pulse rounded-lg bg-card"
                            ></div>
                        {:else}
                            <div class="space-y-2">
                                {#each categoryOrder as cat, idx (cat)}
                                    <div
                                        class="flex items-center justify-between rounded-lg border border-white/10 bg-field px-4 py-2.5"
                                    >
                                        <div class="flex items-center gap-3">
                                            <span
                                                class="grid h-6 w-6 place-items-center rounded bg-canvas text-xs font-bold text-muted"
                                            >
                                                {idx + 1}
                                            </span>
                                            <span
                                                class="text-sm font-medium text-ink"
                                                >{categoryLabel(cat)}</span
                                            >
                                        </div>

                                        <div class="flex items-center gap-1">
                                            <button
                                                type="button"
                                                class="grid h-7 w-7 place-items-center rounded-md text-muted transition hover:bg-elevated hover:text-ink cursor-pointer disabled:cursor-not-allowed disabled:opacity-30"
                                                disabled={idx === 0 ||
                                                    orderSaving}
                                                aria-label={i18n.t.settingsModal
                                                    .search.moveUp}
                                                onclick={() =>
                                                    void moveCategory(
                                                        idx,
                                                        "up",
                                                    )}
                                            >
                                                <ChevronUp size={16} />
                                            </button>
                                            <button
                                                type="button"
                                                class="grid h-7 w-7 place-items-center rounded-md text-muted transition hover:bg-elevated hover:text-ink cursor-pointer disabled:cursor-not-allowed disabled:opacity-30"
                                                disabled={idx ===
                                                    categoryOrder.length - 1 ||
                                                    orderSaving}
                                                aria-label={i18n.t.settingsModal
                                                    .search.moveDown}
                                                onclick={() =>
                                                    void moveCategory(
                                                        idx,
                                                        "down",
                                                    )}
                                            >
                                                <ChevronDown size={16} />
                                            </button>
                                        </div>
                                    </div>
                                {/each}
                            </div>

                            {#if orderSuccess}
                                <p class="text-xs font-medium text-emerald-400">
                                    {i18n.t.settingsModal.search.saved}
                                </p>
                            {/if}
                        {/if}
                    </div>

                    <!-- Source search priority with fallback (Item 16) -->
                    <div class="border-t border-white/[0.07] pt-6 space-y-4">
                        <div>
                            <h3 class="text-sm font-semibold text-ink">
                                {i18n.t.settingsModal.search
                                    .sourcePriorityTitle}
                            </h3>
                            <p class="mt-0.5 text-xs text-muted">
                                {i18n.t.settingsModal.search.sourcePriorityHint}
                            </p>
                        </div>

                        {#if priorityLoading}
                            <div
                                class="h-28 animate-pulse rounded-lg bg-card"
                            ></div>
                        {:else}
                            <div class="space-y-4">
                                {#each Object.entries(sourcePriority) as [mediaType, providers] (mediaType)}
                                    {#if providers && providers.length > 1}
                                        <div
                                            class="rounded-lg border border-white/10 bg-field/60 p-3.5 space-y-2"
                                        >
                                            <div
                                                class="flex items-center justify-between"
                                            >
                                                <h4
                                                    class="text-xs font-bold uppercase tracking-wider text-accent-soft"
                                                >
                                                    {categoryLabel(mediaType)}
                                                </h4>
                                                <span
                                                    class="text-[11px] text-muted"
                                                    >{i18n.t.settingsModal.sources.providersCount(
                                                        providers.length,
                                                    )}</span
                                                >
                                            </div>
                                            <div class="space-y-1.5">
                                                {#each providers as provId, pIdx (provId)}
                                                    <div
                                                        class="flex items-center justify-between rounded-md border border-border/70 bg-surface px-3 py-2 {isSourceDisabled(
                                                            provId,
                                                        )
                                                            ? 'opacity-60 bg-surface/50'
                                                            : ''}"
                                                    >
                                                        <div
                                                            class="flex items-center gap-2.5"
                                                        >
                                                            <span
                                                                class="grid h-5 w-5 place-items-center rounded bg-canvas text-[11px] font-bold text-muted"
                                                            >
                                                                {pIdx + 1}
                                                            </span>
                                                            <span
                                                                class="text-xs font-medium text-ink"
                                                                >{getSourceName(
                                                                    provId,
                                                                )}</span
                                                            >
                                                            {#if isSourceDisabled(provId)}
                                                                <span
                                                                    class="rounded bg-zinc-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-zinc-400"
                                                                >
                                                                    {i18n.t
                                                                        .settingsModal
                                                                        .sources
                                                                        .disabledBadge}
                                                                </span>
                                                            {/if}
                                                            {#if pIdx === 0}
                                                                <span
                                                                    class="rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-400"
                                                                    >{i18n.t
                                                                        .settingsModal
                                                                        .search
                                                                        .primary}</span
                                                                >
                                                            {:else}
                                                                <span
                                                                    class="rounded bg-canvas px-1.5 py-0.5 text-[10px] text-muted"
                                                                    >{i18n.t.settingsModal.search.fallback(
                                                                        pIdx +
                                                                            1,
                                                                    )}</span
                                                                >
                                                            {/if}
                                                        </div>
                                                        <div
                                                            class="flex items-center gap-1"
                                                        >
                                                            <button
                                                                type="button"
                                                                class="grid h-6 w-6 place-items-center rounded text-muted transition hover:bg-elevated hover:text-ink cursor-pointer disabled:cursor-not-allowed disabled:opacity-30"
                                                                disabled={pIdx ===
                                                                    0 ||
                                                                    prioritySaving}
                                                                aria-label={i18n
                                                                    .t
                                                                    .settingsModal
                                                                    .search
                                                                    .moveUp}
                                                                onclick={() =>
                                                                    void moveSourcePriority(
                                                                        mediaType,
                                                                        pIdx,
                                                                        "up",
                                                                    )}
                                                            >
                                                                <ChevronUp
                                                                    size={14}
                                                                />
                                                            </button>
                                                            <button
                                                                type="button"
                                                                class="grid h-6 w-6 place-items-center rounded text-muted transition hover:bg-elevated hover:text-ink cursor-pointer disabled:cursor-not-allowed disabled:opacity-30"
                                                                disabled={pIdx ===
                                                                    providers.length -
                                                                        1 ||
                                                                    prioritySaving}
                                                                aria-label={i18n
                                                                    .t
                                                                    .settingsModal
                                                                    .search
                                                                    .moveDown}
                                                                onclick={() =>
                                                                    void moveSourcePriority(
                                                                        mediaType,
                                                                        pIdx,
                                                                        "down",
                                                                    )}
                                                            >
                                                                <ChevronDown
                                                                    size={14}
                                                                />
                                                            </button>
                                                        </div>
                                                    </div>
                                                {/each}
                                            </div>
                                        </div>
                                    {/if}
                                {/each}
                            </div>
                        {/if}
                    </div>
                </div>
            {:else if activeTab === "backup"}
                <div class="space-y-6">
                    <!-- Export Section -->
                    <div class="rounded-lg border border-white/[0.08] bg-card p-5">
                        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                            <div class="max-w-xl">
                                <h3 class="text-sm font-semibold text-ink">
                                    {i18n.t.settingsModal.backup.exportTitle}
                                </h3>
                                <p class="mt-1 text-xs leading-relaxed text-muted">
                                    {i18n.t.settingsModal.backup.exportDescription}
                                </p>
                            </div>
                            <div class="shrink-0">
                                <button
                                    type="button"
                                    class="inline-flex h-9 items-center gap-2 rounded-md bg-accent-soft px-4 text-xs font-semibold text-ink transition hover:bg-accent cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                                    class:cursor-wait={isExporting}
                                    disabled={isExporting}
                                    onclick={handleExportBackup}
                                >
                                    {#if isExporting}
                                        <LoaderCircle size={14} class="animate-spin" />
                                        {i18n.t.settingsModal.backup.exporting}
                                    {:else}
                                        <ArrowDown size={14} />
                                        {i18n.t.settingsModal.backup.exportButton}
                                    {/if}
                                </button>
                            </div>
                        </div>
                    </div>

                    <!-- Restore Section (Danger Zone) -->
                    <div class="rounded-lg border border-rose-500/20 bg-rose-950/10 p-5">
                        <div class="flex items-center gap-2 text-rose-400">
                            <AlertTriangle size={16} />
                            <h3 class="text-xs font-semibold tracking-wide uppercase">
                                {i18n.t.settingsModal.backup.dangerZone}: {i18n.t.settingsModal.backup.restoreTitle}
                            </h3>
                        </div>
                        <p class="mt-2 text-xs leading-relaxed text-muted">
                            {i18n.t.settingsModal.backup.restoreDescription}
                        </p>
                        <div class="mt-4">
                            <input
                                bind:this={fileInputRef}
                                type="file"
                                accept=".zip"
                                class="hidden"
                                onchange={handleFileSelected}
                            />
                            <button
                                type="button"
                                class="inline-flex h-9 items-center gap-2 rounded-md border border-rose-500/30 bg-field px-4 text-xs font-semibold text-rose-300 transition hover:bg-rose-500/15 hover:border-rose-500/50 cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                                disabled={isRestoring}
                                onclick={() => fileInputRef?.click()}
                            >
                                <RotateCcw size={14} />
                                {i18n.t.settingsModal.backup.selectFileButton}
                            </button>
                        </div>
                    </div>

                    <div class="rounded-lg border border-rose-500/30 bg-rose-950/15 p-5">
                        <div class="flex items-center gap-2 text-rose-400">
                            <AlertTriangle size={16} />
                            <h3 class="text-xs font-semibold tracking-wide uppercase">
                                {i18n.t.settingsModal.backup.dangerZone}: {i18n.t.settingsModal.backup.resetTitle}
                            </h3>
                        </div>
                        <p class="mt-2 text-xs leading-relaxed text-muted">
                            {i18n.t.settingsModal.backup.resetDescription}
                        </p>
                        <button
                            type="button"
                            class="mt-4 inline-flex h-9 items-center gap-2 rounded-md bg-rose-700 px-4 text-xs font-semibold text-white transition hover:bg-rose-600 cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                            disabled={isResetting}
                            onclick={() => (showResetConfirm = true)}
                        >
                            <Trash2 size={14} />
                            {i18n.t.settingsModal.backup.resetButton}
                        </button>
                    </div>
                </div>
            {:else if activeTab === "reading"}
                <section class="space-y-6">
                    <div>
                        <h3 class="text-sm font-semibold text-ink">
                            {i18n.t.settingsModal.reading.title}
                        </h3>
                        <p class="mt-1 text-xs text-muted">
                            {i18n.t.settingsModal.reading.description}
                        </p>
                    </div>

                    <div class="space-y-5 max-w-md">
                        <div class="space-y-1.5">
                            <label for="book-page-speed" class="block text-xs font-semibold text-slate-300">
                                {i18n.t.settingsModal.reading.bookPageMinutes}
                            </label>
                            <input
                                id="book-page-speed"
                                type="number"
                                min="0.2"
                                max="10.0"
                                step="0.1"
                                class="w-full rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                                bind:value={readingBookPageMinutes}
                            />
                            <p class="text-[11px] text-muted">По умолчанию: 1.5 мин/стр. Диапазон: 0.2 – 10.0</p>
                        </div>

                        <div class="space-y-1.5">
                            <label for="manga-chapter-speed" class="block text-xs font-semibold text-slate-300">
                                {i18n.t.settingsModal.reading.mangaChapterMinutes}
                            </label>
                            <input
                                id="manga-chapter-speed"
                                type="number"
                                min="0.5"
                                max="30.0"
                                step="0.5"
                                class="w-full rounded-lg border border-white/10 bg-field px-3 py-2 text-sm text-ink outline-none transition focus:border-accent-soft focus:ring-1 focus:ring-accent-soft"
                                bind:value={readingMangaChapterMinutes}
                            />
                            <p class="text-[11px] text-muted">По умолчанию: 6.0 мин/гл. Диапазон: 0.5 – 30.0</p>
                        </div>

                        <div class="pt-2">
                            <button
                                type="button"
                                disabled={isSavingReading}
                                class="inline-flex items-center gap-2 rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:bg-accent-hover disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
                                onclick={handleSaveReadingSpeed}
                            >
                                {#if isSavingReading}
                                    <LoaderCircle size={15} class="animate-spin" />
                                {/if}
                                {i18n.t.settingsModal.reading.saveButton}
                            </button>
                        </div>
                    </div>
                </section>
            {/if}
        </div>
    </div>
</div>
</Modal>

<!-- Double confirmation for full library reset -->
<Modal isOpen={showResetConfirm} onClose={handleCancelReset} labelledBy="reset-confirm-title">
    <div class="p-6">
        <div class="flex items-start gap-4">
            <div class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-rose-500/15 text-rose-400">
                <AlertTriangle size={20} />
            </div>
            <div class="min-w-0 flex-1">
                <h3 id="reset-confirm-title" class="text-base font-bold text-ink">
                    {i18n.t.settingsModal.backup.resetConfirmTitle}
                </h3>
                <p class="mt-2 text-xs leading-relaxed text-muted">
                    {i18n.t.settingsModal.backup.resetWarning}
                </p>
                <label class="mt-4 flex items-center gap-2 text-xs text-ink">
                    <input type="checkbox" bind:checked={keepApiKeys} disabled={isResetting} class="accent-rose-500" />
                    {i18n.t.settingsModal.backup.keepApiKeys}
                </label>
                <label for="reset-confirmation-input" class="mt-4 block text-xs text-muted">
                    {i18n.t.settingsModal.backup.typeToConfirm}
                    <span class="ml-1 font-mono font-semibold text-rose-300">{i18n.t.settingsModal.backup.confirmationWord}</span>
                </label>
                <input
                    id="reset-confirmation-input"
                    type="text"
                    bind:value={resetConfirmationInput}
                    disabled={isResetting}
                    autocomplete="off"
                    spellcheck="false"
                    class="mt-2 h-9 w-full rounded-md border border-white/10 bg-field px-3 text-sm text-ink outline-none focus:border-rose-500/60"
                />
            </div>
        </div>
        <div class="mt-6 flex items-center justify-end gap-3 border-t border-white/[0.07] pt-4">
            <button
                type="button"
                class="inline-flex h-9 items-center rounded-md border border-white/10 bg-field px-4 text-xs font-semibold text-ink transition hover:bg-card cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                disabled={isResetting}
                onclick={handleCancelReset}
            >
                {i18n.t.settingsModal.backup.cancelButton}
            </button>
            <button
                type="button"
                class="inline-flex h-9 items-center gap-2 rounded-md bg-rose-700 px-4 text-xs font-semibold text-white transition hover:bg-rose-600 cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                class:cursor-wait={isResetting}
                disabled={isResetting || resetConfirmationInput.trim() !== i18n.t.settingsModal.backup.confirmationWord}
                onclick={handleConfirmReset}
            >
                {#if isResetting}
                    <LoaderCircle size={14} class="animate-spin" />
                    {i18n.t.settingsModal.backup.resetting}
                {:else}
                    <Trash2 size={14} />
                    {i18n.t.settingsModal.backup.resetConfirmButton}
                {/if}
            </button>
        </div>
    </div>
</Modal>

<!-- Confirmation Modal for Restore -->
<Modal isOpen={showRestoreConfirm} onClose={handleCancelRestore} labelledBy="restore-confirm-title">
    <div class="p-6">
        <div class="flex items-start gap-4">
            <div class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-rose-500/15 text-rose-400">
                <AlertTriangle size={20} />
            </div>
            <div>
                <h3 id="restore-confirm-title" class="text-base font-bold text-ink">
                    {i18n.t.settingsModal.backup.confirmModalTitle}
                </h3>
                <p class="mt-2 text-xs leading-relaxed text-muted">
                    {i18n.t.settingsModal.backup.confirmModalWarning}
                </p>
                {#if selectedBackupFile}
                    <div class="mt-3 rounded-md bg-field px-3 py-2 text-xs text-ink font-mono border border-white/10">
                        <span class="text-muted font-sans mr-1">{i18n.t.settingsModal.backup.selectedFileLabel}</span>
                        {selectedBackupFile.name} ({(selectedBackupFile.size / (1024 * 1024)).toFixed(2)} MB)
                    </div>
                {/if}
            </div>
        </div>

        <div class="mt-6 flex items-center justify-end gap-3 border-t border-white/[0.07] pt-4">
            <button
                type="button"
                class="inline-flex h-9 items-center rounded-md border border-white/10 bg-field px-4 text-xs font-semibold text-ink transition hover:bg-card cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                disabled={isRestoring}
                onclick={handleCancelRestore}
            >
                {i18n.t.settingsModal.backup.cancelButton}
            </button>
            <button
                type="button"
                class="inline-flex h-9 items-center gap-2 rounded-md bg-rose-600 px-4 text-xs font-semibold text-white transition hover:bg-rose-500 cursor-pointer disabled:cursor-not-allowed disabled:opacity-60"
                class:cursor-wait={isRestoring}
                disabled={isRestoring}
                onclick={handleConfirmRestore}
            >
                {#if isRestoring}
                    <LoaderCircle size={14} class="animate-spin" />
                    {i18n.t.settingsModal.backup.restoring}
                {:else}
                    <AlertTriangle size={14} />
                    {i18n.t.settingsModal.backup.confirmButton}
                {/if}
            </button>
        </div>
    </div>
</Modal>
