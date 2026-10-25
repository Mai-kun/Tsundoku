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
    import { jobsClient } from "$shared/api/jobsClient.svelte";
    import Modal from "$shared/ui/Modal.svelte";
    import PopoverMenu, { type PopoverOption } from "$shared/ui/PopoverMenu.svelte";
    import {
        Check,
        CheckCircle2,
        ChevronDown,
        ChevronUp,
        Copy,
        Download,
        ExternalLink,
        FileText,
        FolderInput,
        LoaderCircle,
        Sparkles,
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

    // MangaLib (SocialLib) ecosystem
    let mangalibMode = $state<"collector" | "file">("collector");
    let mangalibSites = $state<number[]>([1, 5, 3, 2, 4]);
    let scriptCopied = $state(false);
    let showSkippedDuplicates = $state(false);

    // MangaLib folder options: standard 5 + custom folders
    interface MangaLibFolderOption {
        id: number | "custom";
        label: string;
    }

    const mangalibFolderOptions: MangaLibFolderOption[] = [
        { id: 1, label: "Читаю" },
        { id: 2, label: "В планах" },
        { id: 4, label: "Прочитано" },
        { id: 5, label: "Любимые" },
        { id: 3, label: "Брошено" },
        { id: "custom", label: "Пользовательские папки" },
    ];

    let mangalibSelectedFolders = $state<(number | "custom")[]>([
        1,
        2,
        4,
        5,
        "custom",
    ]);

    function toggleMangaLibFolder(id: number | "custom") {
        if (mangalibSelectedFolders.includes(id)) {
            if (mangalibSelectedFolders.length > 1) {
                mangalibSelectedFolders = mangalibSelectedFolders.filter(
                    (s) => s !== id,
                );
            }
        } else {
            mangalibSelectedFolders = [...mangalibSelectedFolders, id];
        }
    }

    let mangalibSelectedStatuses = $derived(
        mangalibSelectedFolders.filter(
            (x): x is number => typeof x === "number",
        ),
    );
    let mangalibIncludeCustomFolders = $derived(
        mangalibSelectedFolders.includes("custom"),
    );

    // Custom folder modal setup
    export type CustomFolderStatus =
        | "Planned"
        | "OnHold"
        | "InProgress"
        | "Dropped"
        | "skip";

    export interface CustomFolderItem {
        name: string;
        count: number;
        status: CustomFolderStatus;
        createList: boolean;
    }

    let showCustomFolderModal = $state(false);
    let pendingCustomFolders = $state<CustomFolderItem[]>([]);

    let customFolderStatusOptions = $derived<
        PopoverOption<CustomFolderStatus>[]
    >([
        { value: "Planned", label: i18n.t.importModal.statusPlanned },
        { value: "OnHold", label: i18n.t.importModal.statusOnHold },
        { value: "InProgress", label: i18n.t.importModal.statusInProgress },
        { value: "Dropped", label: i18n.t.importModal.statusDropped },
        { value: "skip", label: i18n.t.importModal.statusSkip },
    ]);

    type PendingImport =
        | { type: "clipboard"; data: any[] }
        | { type: "file"; file: File; data?: any[] };

    let pendingImport = $state<PendingImport | null>(null);

    function cancelCustomFolderModal() {
        showCustomFolderModal = false;
        pendingImport = null;
        pendingCustomFolders = [];
        busy = false;
    }

    function getDefaultStatusForFolder(name: string): CustomFolderStatus {
        const s = name.trim().toLowerCase();
        if (
            s.includes("жду") ||
            s.includes("ожида") ||
            s.includes("hold") ||
            s.includes("пауз")
        ) {
            return "OnHold";
        }
        if (s.includes("удален") || s.includes("дроп") || s.includes("drop")) {
            return "Dropped";
        }
        return "Planned";
    }

    function isStandardStatusName(name: string): boolean {
        const s = name.toLowerCase().trim();
        return (
            s.includes("читаю") ||
            s.includes("смотрю") ||
            s.includes("пересматрива") ||
            s === "reading" ||
            s === "watching" ||
            s === "rewatching" ||
            s === "in_progress" ||
            s === "in progress" ||
            s.includes("план") ||
            s.includes("запланировано") ||
            s.includes("буду") ||
            s === "planned" ||
            s === "plan_to_watch" ||
            s.includes("прочитано") ||
            s.includes("просмотрено") ||
            s === "completed" ||
            s === "finished" ||
            s === "watched" ||
            s.includes("любим") ||
            s.includes("favorite") ||
            s.includes("отложен") ||
            s.includes("hold") ||
            s.includes("pause") ||
            s.includes("брошен") ||
            s === "dropped"
        );
    }

    function isCustomMangaLibFolder(item: any): boolean {
        if (!item || typeof item !== "object") return false;

        const name = String(
            item.folder_name ??
                item.folder?.name ??
                item.status ??
                item.status_name ??
                "",
        ).trim();

        // Standard AnimeLib & MangaLib statuses are NEVER custom folders:
        if (name && isStandardStatusName(name)) {
            return false;
        }

        if (item.is_custom_folder === true) return true;
        if (item.is_custom_folder === false) return false;

        const rawCode =
            item.status_id ??
            item.folder_id ??
            (typeof item.status === "number" ? item.status : null);
        if (rawCode !== null && rawCode !== undefined) {
            const num = Number(rawCode);
            if (!Number.isNaN(num) && ![1, 2, 3, 4, 5, 6].includes(num)) {
                return true;
            }
        }

        if (name) {
            return !isStandardStatusName(name);
        }

        return false;
    }

    function getCustomFolderName(item: any): string {
        return (
            String(
                item.folder_name ??
                    item.folder?.name ??
                    item.status ??
                    item.status_name ??
                    "",
            ).trim() || "Пользовательская папка"
        );
    }

    function extractCustomFolders(items: any[]): CustomFolderItem[] {
        const counts = new Map<string, number>();
        for (const item of items) {
            if (isCustomMangaLibFolder(item)) {
                const name = getCustomFolderName(item);
                counts.set(name, (counts.get(name) || 0) + 1);
            }
        }

        return Array.from(counts.entries()).map(([name, count]) => ({
            name,
            count,
            status: getDefaultStatusForFolder(name),
            createList: true,
        }));
    }

    function filterMangaLibItems(items: any[]): any[] {
        const standardCodes = mangalibSelectedStatuses;
        const includeCustom = mangalibIncludeCustomFolders;

        return items.filter((item) => {
            if (isCustomMangaLibFolder(item)) {
                return includeCustom;
            }
            const code = getItemStatusCode(item);
            return standardCodes.includes(code);
        });
    }

    async function continueImportWithCustomFolders() {
        if (!pendingImport) return;
        const currentPending = pendingImport;
        const folderConfigs = pendingCustomFolders;
        showCustomFolderModal = false;
        pendingImport = null;
        pendingCustomFolders = [];
        busy = true;
        error = "";

        try {
            const configMap: Record<
                string,
                { status?: string; createList: boolean; skip: boolean }
            > = {};
            for (const f of folderConfigs) {
                configMap[f.name] = {
                    status: f.status === "skip" ? undefined : f.status,
                    createList: f.status === "skip" ? false : f.createList,
                    skip: f.status === "skip",
                };
            }

            let uploadFile: File;
            if (currentPending.type === "clipboard") {
                const filtered = currentPending.data.filter((item) => {
                    if (isCustomMangaLibFolder(item)) {
                        const name = getCustomFolderName(item);
                        const cfg = configMap[name];
                        if (cfg?.skip) return false;
                    }
                    return true;
                });

                uploadFile = new File(
                    [JSON.stringify(filtered)],
                    "tsundoku-sociallib.json",
                    { type: "application/json" },
                );
            } else if (
                currentPending.data &&
                Array.isArray(currentPending.data)
            ) {
                const filtered = currentPending.data.filter((item) => {
                    if (isCustomMangaLibFolder(item)) {
                        const name = getCustomFolderName(item);
                        const cfg = configMap[name];
                        if (cfg?.skip) return false;
                    }
                    return true;
                });

                uploadFile = new File(
                    [JSON.stringify(filtered)],
                    currentPending.file.name,
                    { type: currentPending.file.type || "application/json" },
                );
            } else {
                uploadFile = currentPending.file;
            }

            const form = new FormData();
            form.append("file", uploadFile);
            form.append("provider", "mangalib");
            form.append("skipDuplicates", String(skipDuplicates));
            form.append("customFolderConfigs", JSON.stringify(configMap));

            if (addToList && listMode === "existing" && targetListId) {
                form.append("targetListId", targetListId);
            }
            if (addToList && listMode === "new" && newListName.trim()) {
                form.append("newListName", newListName.trim());
            }

            result = await importFile(form);
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

    // Folder status filtering
    interface FolderFilterOption {
        id: number;
        label: string;
    }

    const folderFilterOptions: FolderFilterOption[] = [
        { id: 1, label: "Читаю / Смотрю" },
        { id: 2, label: "В планах" },
        { id: 4, label: "Прочитано" },
        { id: 6, label: "Отложено / Жду" },
        { id: 3, label: "Брошено / Удалено" },
        { id: 5, label: "Любимые" },
    ];

    let selectedStatuses = $state<number[]>([1, 2, 4, 6, 5]); // 3 is disabled by default

    function toggleStatus(id: number) {
        if (selectedStatuses.includes(id)) {
            if (selectedStatuses.length > 1) {
                selectedStatuses = selectedStatuses.filter((s) => s !== id);
            }
        } else {
            selectedStatuses = [...selectedStatuses, id];
        }
    }

    function getItemStatusCode(item: Record<string, any>): number {
        const rawStatus = item.status_id ?? item.folder_id;
        const name = String(
            item.status ??
                item.folder_name ??
                item.folder?.name ??
                item.status_name ??
                "",
        ).toLowerCase();
        if (
            name.includes("удален") ||
            name.includes("брошен") ||
            name.includes("dropped")
        ) {
            return 3;
        }
        if (
            name.includes("читаю") ||
            name.includes("смотрю") ||
            name.includes("reading") ||
            name.includes("watching")
        ) {
            return 1;
        }
        if (name.includes("план") || name.includes("planned")) {
            return 2;
        }
        if (
            name.includes("прочитано") ||
            name.includes("просмотрено") ||
            name.includes("completed")
        ) {
            return 4;
        }
        if (name.includes("любим") || name.includes("favorite")) {
            return 5;
        }
        if (
            name.includes("отложен") ||
            name.includes("жду") ||
            name.includes("hold") ||
            name.includes("pause")
        ) {
            return 6;
        }
        if (
            typeof rawStatus === "number" ||
            (typeof rawStatus === "string" && /^\d+$/.test(rawStatus))
        ) {
            const num = Number(rawStatus);
            if (num >= 1 && num <= 5) return num;
            return 6;
        }
        return 2;
    }

    const socialLibSites: {
        id: number;
        name: string;
        tag: string;
        type: string;
    }[] = [
        { id: 1, name: "MangaLib", tag: "Манга", type: "manga" },
        { id: 5, name: "AnimeLib", tag: "Аниме", type: "anime" },
        { id: 3, name: "RanobeLib", tag: "Ранобэ / Книги", type: "book" },
        { id: 2, name: "SlashLib / YaoiLib", tag: "Слэш", type: "manga" },
        { id: 4, name: "HentaiLib", tag: "18+", type: "manga" },
    ];

    function toggleSite(id: number) {
        if (mangalibSites.includes(id)) {
            if (mangalibSites.length > 1) {
                mangalibSites = mangalibSites.filter((s) => s !== id);
            }
        } else {
            mangalibSites = [...mangalibSites, id];
        }
    }

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
            accent: "#ea580c",
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
        providers.find((p) => p.id === provider) ?? providers[0],
    );

    const fileAccept = $derived(
        provider === "mal" || provider === "shikimori"
            ? ".xml,.json"
            : provider === "letterboxd" || provider === "goodreads"
              ? ".csv"
              : provider === "steam" || provider === "anilist"
                ? ".json"
                : ".json,.csv",
    );

    const allowedExtensions = $derived(
        provider === "mal" || provider === "shikimori"
            ? ["xml", "json"]
            : provider === "letterboxd" || provider === "goodreads"
              ? ["csv"]
              : provider === "steam" || provider === "anilist"
                ? ["json"]
                : ["json", "csv"],
    );

    const helpText = $derived(
        {
            mal: i18n.t.importModal.helpMal,
            shikimori: i18n.t.importModal.helpShikimori,
            letterboxd: i18n.t.importModal.helpLetterboxd,
            goodreads: i18n.t.importModal.helpGoodreads,
            steam: i18n.t.importModal.helpSteam,
            anilist: i18n.t.importModal.helpAnilist,
            mangalib: i18n.t.importModal.helpMangalib,
            custom: i18n.t.importModal.helpCustom,
        }[provider],
    );

    const defaultListName = $derived(
        i18n.t.importModal.defaultList(selectedProviderInfo.title),
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
                (s) => s.id === "steam" && s.hasKey,
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
            newListName = i18n.t.importModal.defaultList(nextInfo?.title ?? id);
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
        } else if (provider === "mangalib" && mangalibMode === "collector") {
            if (!file) {
                void importFromClipboard();
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
                let uploadFile = file!;
                if (
                    file &&
                    (file.name.endsWith(".json") || provider === "mangalib")
                ) {
                    try {
                        const raw = await file.text();
                        let parsedData = JSON.parse(raw);
                        let modified = false;
                        if (provider === "mangalib") {
                            let items = Array.isArray(parsedData)
                                ? parsedData
                                : (parsedData && Array.isArray(parsedData.data)
                                      ? parsedData.data
                                      : []);
                            items = filterMangaLibItems(items);
                            const customFolders = extractCustomFolders(items);
                            if (customFolders.length > 0) {
                                uploadFile = new File(
                                    [JSON.stringify(items)],
                                    file.name,
                                    {
                                        type:
                                            file.type || "application/json",
                                    },
                                );
                                pendingImport = {
                                    type: "file",
                                    file: uploadFile,
                                    data: items,
                                };
                                pendingCustomFolders = customFolders;
                                showCustomFolderModal = true;
                                busy = false;
                                return;
                            }
                            if (Array.isArray(parsedData)) {
                                parsedData = items;
                            } else if (
                                parsedData &&
                                Array.isArray(parsedData.data)
                            ) {
                                parsedData.data = items;
                            }
                            modified = true;
                        } else {
                            if (Array.isArray(parsedData)) {
                                parsedData = parsedData.filter((item) =>
                                    selectedStatuses.includes(
                                        getItemStatusCode(item),
                                    ),
                                );
                                modified = true;
                            } else if (
                                parsedData &&
                                Array.isArray(parsedData.data)
                            ) {
                                parsedData.data = parsedData.data.filter(
                                    (item: any) =>
                                        selectedStatuses.includes(
                                            getItemStatusCode(item),
                                        ),
                                );
                                modified = true;
                            }
                        }
                        if (modified) {
                            uploadFile = new File(
                                [JSON.stringify(parsedData)],
                                file.name,
                                {
                                    type: file.type || "application/json",
                                },
                            );
                        }
                    } catch {
                        // ignore if not valid JSON
                    }
                }
                const form = new FormData();
                form.append("file", uploadFile);
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

    function generateSocialLibScript(
        siteIds: number[],
        statusCodes: number[] = mangalibSelectedStatuses,
        includeCustom: boolean = mangalibIncludeCustomFolders,
    ): string {
        const idsJson = JSON.stringify(siteIds);
        const statusJson = JSON.stringify(statusCodes);
        const includeCustomJson = JSON.stringify(includeCustom);
        return `(async () => {
  console.clear();
  let userId = null;
  const urlMatch = window.location.pathname.match(/\\/(?:ru\\/)?user[s]?\\/(\\d+)/i) || window.location.pathname.match(/\\/user\\/(\\d+)/);
  if (urlMatch) userId = urlMatch[1];

  if (!userId) {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      const val = localStorage.getItem(key);
      if (!val) continue;
      try {
        const parsed = JSON.parse(val);
        if (parsed?.id && typeof parsed.id === "number") { userId = String(parsed.id); break; }
        if (parsed?.user?.id) { userId = String(parsed.user.id); break; }
        if (parsed?.userId) { userId = String(parsed.userId); break; }
        if (parsed?.auth?.user?.id) { userId = String(parsed.auth.user.id); break; }
      } catch {}
    }
  }
  if (!userId && window.__DATA__?.user?.id) userId = String(window.__DATA__.user.id);
  if (!userId && window.__INITIAL_STATE__?.user?.id) userId = String(window.__INITIAL_STATE__.user.id);

  if (!userId) {
    userId = prompt("Tsundoku: Введите числовой ID пользователя Lib (например: 123456):");
    if (!userId) { console.error("Сбор отменен: не указан User ID."); return; }
    userId = userId.trim().replace(/\\D+/g, "");
  }

  console.log("%c[Tsundoku SocialLib Collector]%c Запуск сбора закладок для User ID:", "color:#ff6740;font-weight:bold", "", userId);

  // Токен у SocialLib хранится в localStorage.auth как JSON: { token: { access_token } }
  const getAuthToken = () => {
    // 1. localStorage.auth
    try {
      if (localStorage.auth) {
        const auth = JSON.parse(localStorage.auth);
        const token = auth?.token?.access_token || auth?.access_token || auth?.token;
        if (token && typeof token === "string" && token.startsWith("eyJ")) return token;
      }
    } catch {}

    // 2. localStorage.token
    try {
      if (localStorage.token) {
        const t = JSON.parse(localStorage.token);
        const token = t?.access_token || t?.token || t;
        if (token && typeof token === "string" && token.startsWith("eyJ")) return token;
      }
    } catch {
      if (typeof localStorage.token === "string" && localStorage.token.startsWith("eyJ")) return localStorage.token;
    }

    // 3. Сканируем все ключи localStorage на валидный JWT (eyJ...)
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        const val = localStorage.getItem(key);
        if (!val) continue;
        if (val.startsWith("eyJ") && val.includes(".")) return val.trim();
        try {
          const parsed = JSON.parse(val);
          const match = JSON.stringify(parsed).match(/eyJ[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+/);
          if (match) return match[0];
        } catch {}
      }
    } catch {}

    return null;
  };
  const token = getAuthToken();
  console.log("Токен авторизации:", token ? \`✅ найден (\${token.slice(0, 15)}...)\` : "❌ не найден (гостевой режим, лимит 100 тайтлов)");

  const allSites = [
    { id: 1, name: "MangaLib", type: "manga" },
    { id: 5, name: "AnimeLib", type: "anime" },
    { id: 3, name: "RanobeLib", type: "book" },
    { id: 2, name: "SlashLib", type: "manga" },
    { id: 4, name: "HentaiLib", type: "manga" }
  ];
  const targetSiteIds = ${idsJson};
  const selectedSites = allSites.filter(s => targetSiteIds.includes(s.id));
  const standardIds = [1, 2, 3, 4, 5, 6];
  const allowedStandardStatuses = ${statusJson};
  const includeCustomFolders = ${includeCustomJson};

  const isStandardName = (name) => {
    if (!name) return false;
    const s = String(name).toLowerCase().trim();
    return s.includes("читаю") || s.includes("смотрю") || s.includes("пересматрива") ||
      s === "reading" || s === "watching" || s === "rewatching" || s === "in_progress" || s === "in progress" ||
      s.includes("план") || s.includes("запланировано") || s.includes("буду") || s === "planned" || s === "plan_to_watch" ||
      s.includes("прочитано") || s.includes("просмотрено") || s === "completed" || s === "watched" ||
      s.includes("любим") || s.includes("favorite") ||
      s.includes("отложен") || s.includes("hold") || s.includes("pause") ||
      s.includes("брошен") || s === "dropped";
  };

  const statusToCode = (statusId, statusName) => {
    const s = String(statusName || "").toLowerCase();
    if (s.includes("удален") || s.includes("брошен") || s === "dropped") return 3;
    if (s.includes("читаю") || s.includes("смотрю") || s.includes("пересматрива") || s === "reading" || s === "watching" || s === "rewatching") return 1;
    if (s.includes("план") || s.includes("запланировано") || s === "planned") return 2;
    if (s.includes("прочитано") || s.includes("просмотрено") || s === "completed" || s === "watched") return 4;
    if (s.includes("любим") || s.includes("favorite")) return 5;
    if (s.includes("отложен") || s.includes("hold")) return 6;
    if (typeof statusId === "number") {
      if (statusId >= 1 && statusId <= 6) return statusId;
      return 6;
    }
    return 2;
  };

  const allItems = [];
  const counts = { 1: 0, 5: 0, 3: 0, 2: 0, 4: 0, 6: 0 };
  const statusMap = { 1: "Читаю", 2: "В планах", 3: "Брошено", 4: "Прочитано", 5: "Любимые", 6: "Отложено" };

  const processBookmark = (b, site, folderId, folderName, isCustomFolder) => {
    const m = b.media || {};
    const prog = b.item || b.progress || {};
    const itemStatus = (b.status !== undefined && b.status !== null) ? b.status : (b.status_id || b.folder_id || folderId || 2);
    const statusText = folderName || statusMap[itemStatus] || (typeof itemStatus === "string" ? itemStatus : null) || b.folder?.name || b.status_name;

    let coverUrl = null;
    if (typeof m.cover === "string") coverUrl = m.cover;
    else if (m.cover?.default) coverUrl = m.cover.default;
    else if (m.cover?.md) coverUrl = m.cover.md;
    else if (b.cover) coverUrl = typeof b.cover === "string" ? b.cover : (b.cover?.default || b.cover?.md);

    const genresList = Array.isArray(m.genres) ? m.genres.map(g => g?.name || g).filter(Boolean).join(", ") : (m.genres ?? null);
    const authorList = Array.isArray(m.authors) ? m.authors.map(a => a?.name || a).filter(Boolean).join(", ") : (m.authors ?? m.author ?? null);

    const totalChapters = m.chap_count ?? m.chapters_count ?? b.total_chapters ?? null;
    const volumes = prog.volume !== undefined ? Number(prog.volume) : (m.volumes_count ?? b.volumes ?? null);
    const userRating = prog.rating ?? prog.score ?? prog.user_rating ?? b.user_rating ?? b.score ?? b.rating ?? null;
    const summary = m.summary ?? m.description ?? b.summary ?? null;

    const rusName = m.rus_name || m.name || b.rus_name || b.name || "";
    const engName = m.eng_name || (m.name && m.name !== rusName ? m.name : null) || m.slug_url || b.eng_name || null;

    const itemObj = {
      rus_name: rusName,
      eng_name: engName,
      type: site.type,
      site_id: site.id,
      status: statusText || itemStatus || "В планах",
      status_id: typeof itemStatus === "number" ? itemStatus : folderId,
      user_chapters: prog.number !== undefined ? Number(prog.number) : (b.user_chapters ?? 0),
      total_chapters: totalChapters,
      volumes: volumes,
      user_rating: userRating,
      cover: coverUrl,
      summary: summary,
      genres: genresList,
      author: authorList
    };

    if (isCustomFolder) {
      itemObj.folder_name = folderName;
      itemObj.is_custom_folder = true;
    }

    allItems.push(itemObj);
    counts[site.id] = (counts[site.id] || 0) + 1;
  };

  const totalSites = selectedSites.length;
  for (let sIdx = 0; sIdx < selectedSites.length; sIdx++) {
    const site = selectedSites[sIdx];
    const siteName = site.name;
    const siteIdx = sIdx + 1;
    const siteStartCount = counts[site.id] || 0;

    console.log(\`%c[\${siteIdx}/\${totalSites}] \${site.name}%c: опрос папок...\`, "color:#ff6740;font-weight:bold", "");

    const headers = {
      "Accept": "application/json",
      "Site-Id": String(site.id)
    };
    if (token) headers["Authorization"] = "Bearer " + token;

    let folders = [];
    try {
      const foldersUrl = "https://api.cdnlibs.org/api/bookmarks/folder/" + encodeURIComponent(userId) + "?site_id=" + site.id;
      const foldersRes = await fetch(foldersUrl, { headers });
      if (foldersRes.ok) {
        const foldersJson = await foldersRes.json();
        const list = Array.isArray(foldersJson?.data) ? foldersJson.data : (Array.isArray(foldersJson) ? foldersJson : []);
        if (list.length > 0) {
          folders = list.map(f => ({
            id: f.id,
            name: f.name || f.slug || ("Папка " + f.id),
            count: f.count ?? f.total ?? undefined
          }));
          for (const f of folders) {
            statusMap[f.id] = f.name;
          }
        }
      }
    } catch (err) {
      console.warn(\`Не удалось получить папки для \${site.name}:\`, err.message);
    }

    if (folders.length === 0) {
      if (site.id === 5) {
        folders = [
          { id: 1, name: "Смотрю" },
          { id: 2, name: "Запланировано" },
          { id: 4, name: "Просмотрено" },
          { id: 5, name: "Любимые" },
          { id: 6, name: "Отложено" },
          { id: 3, name: "Брошено" }
        ];
      } else {
        folders = [
          { id: 1, name: "Читаю" },
          { id: 2, name: "В планах" },
          { id: 4, name: "Прочитано" },
          { id: 5, name: "Любимые" },
          { id: 3, name: "Брошено" }
        ];
      }
    }

    // Кастомные папки («Жду», «Удалено» и др.) — сканируем DOM бокового меню
    // закладок на открытой странице и объединяем со списком API по уникальному id
    try {
      const domSeen = new Set(folders.map(f => f.id));
      for (const el of document.querySelectorAll('a[href*="status="], a[href*="folder="], a[href*="bookmarks"]')) {
        const href = el.getAttribute("href") || "";
        const idMatch = href.match(/[?&](?:status|folder)=(\\d+)/);
        const rawName = (el.textContent || "").trim();
        if (!idMatch || !rawName) continue;
        const id = Number(idMatch[1]);
        if (domSeen.has(id)) continue;
        domSeen.add(id);
        const folder = { id: id, name: rawName.replace(/\\s*\\d+$/, "").trim() || ("Папка " + id) };
        folders.push(folder);
        statusMap[folder.id] = folder.name;
      }
    } catch {}

    // Deduplicate folders by folder.id
    const seenFolderIds = new Set();
    folders = folders.filter(f => {
      if (seenFolderIds.has(f.id)) return false;
      seenFolderIds.add(f.id);
      return true;
    });

    const activeFolders = folders.filter(f => f.count > 0);
    console.log(\`📁 [\${site.name}] Папки: \${activeFolders.map(f => \`\${f.name} (\${f.count})\`).join(', ')}\`);

    for (const folder of folders) {
      const isCustom = !standardIds.includes(folder.id) && !isStandardName(folder.name);
      if (isCustom) {
        if (!includeCustomFolders) continue;
      } else {
        if (!allowedStandardStatuses.includes(folder.id) && !isStandardName(folder.name)) continue;
      }

      let page = 1;
      let folderCount = 0;
      let totalExpected = null;
      let maxPage = null;
      let folderErrorRetries = 0;

      // Честная бесконечная пагинация: у API SocialLib поля пагинации
      // (last_page / total / per_page) приходят на верхнем уровне ответа, не в meta
      while (true) {
        const url = "https://api.cdnlibs.org/api/bookmarks?user_id=" + encodeURIComponent(userId) +
          "&site_id=" + site.id +
          "&status=" + folder.id +
          "&page=" + page +
          "&fields[]=summary&fields[]=genres&fields[]=authors&fields[]=chap_count&fields[]=rate";

        let res;
        try {
          res = await fetch(url, { headers });
        } catch (fetchErr) {
          console.error(\`Ошибка сети при запросе папки «\${folder.name}» (стр. \${page}):\`, fetchErr);
          if (++folderErrorRetries <= 3) {
            await new Promise(r => setTimeout(r, 1500));
            continue;
          }
          break;
        }

        if (res.status === 429) {
          console.warn(\`[\${siteName}] ⚠️ Лимит запросов (429), пауза 6 сек...\`);
          await new Promise(r => setTimeout(r, 6000));
          continue;
        }

        folderErrorRetries = 0;

        if (!res.ok) {
          if (res.status === 401 || res.status === 403) {
            console.warn(\`\${site.name}: доступ ограничен (\${res.status})\`);
          } else if (res.status === 422) {
            const errDetail = await res.text();
            console.warn(\`\${site.name} (папка «\${folder.name}» id:\${folder.id}): 422 detail:\`, errDetail);
          }
          break;
        }

        let json;
        try {
          json = await res.json();
        } catch {
          break;
        }

        const items = Array.isArray(json?.data) ? json.data : (Array.isArray(json) ? json : []);
        if (items.length === 0) {
          break;
        }

        // Пагинация может прийти в корне ответа ЛИБО внутри meta — проверяем оба места;
        // если last_page нигде нет — считаем страницы из total и фактического размера страницы
        totalExpected = json.total ?? json.meta?.total ?? json.meta?.pagination?.total ?? totalExpected;
        maxPage = json.last_page ?? json.meta?.last_page ?? json.meta?.pagination?.total_pages ?? (totalExpected ? Math.ceil(totalExpected / items.length) : maxPage);

        for (const b of items) {
          processBookmark(b, site, folder.id, folder.name, isCustom);
        }
        folderCount += items.length;

        console.log(\`  ↳ Папка «\${folder.name}» (всего \${totalExpected ?? "?"}): стр. \${page}/\${maxPage ?? "?"} ✓ (+\${items.length} тайтлов, накоплено: \${folderCount})\`);

        if (maxPage && page >= maxPage) {
          break;
        }

        page++;
        await new Promise(r => setTimeout(r, 650 + Math.floor(Math.random() * 150)));
      }

      await new Promise(r => setTimeout(r, 200));
    }

    const siteTotal = (counts[site.id] || 0) - siteStartCount;
    console.log(\`✔ \${site.name}: успешно собрано \${siteTotal} тайтлов.\`);
    await new Promise(r => setTimeout(r, 1200));
  }

  if (allItems.length === 0) {
    console.log("Попытка fallback-сбора из DOM открытой страницы...");
    const cardSelectors = [
      'a[href*="/manga/"]',
      'a[href*="/anime/"]',
      'a[href*="/book/"]',
      'a[href*="/ranobe/"]',
      '[data-media-id]',
      '.media-card',
      '.bookmark-item',
      '.hot-item'
    ];
    const elements = Array.from(document.querySelectorAll(cardSelectors.join(",")));
    const seen = new Set();
    for (const card of elements) {
      const titleEl = card.querySelector('h3, h4, .media-card__title, [class*="title"], [class*="name"]') || (card.matches('h3, h4, a') ? card : null);
      const title = titleEl ? titleEl.textContent.trim() : "";
      if (!title || title.length < 2 || seen.has(title.toLowerCase())) continue;
      seen.add(title.toLowerCase());

      const img = card.querySelector('img') || (card.tagName === 'IMG' ? card : null);
      const cover = img ? (img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-lazy')) : null;

      let progress = 0;
      const text = card.textContent || "";
      const progMatch = text.match(/(?:глава|серия|том|гл\\.|сер\\.)\\s*(\\d+)/i) || text.match(/\\b(\\d+)\\s*\\/\\s*\\d+/);
      if (progMatch) progress = parseInt(progMatch[1], 10) || 0;

      let siteId = 1;
      let type = "manga";
      const href = card.getAttribute('href') || (card.closest('a')?.getAttribute('href')) || window.location.href;
      if (href.includes("/anime") || window.location.hostname.includes("animelib")) { siteId = 5; type = "anime"; }
      else if (href.includes("/book") || href.includes("/ranobe") || window.location.hostname.includes("ranobelib")) { siteId = 3; type = "book"; }
      else if (window.location.hostname.includes("slashlib") || window.location.hostname.includes("yaoi")) { siteId = 2; type = "manga"; }
      else if (window.location.hostname.includes("hentai")) { siteId = 4; type = "manga"; }

      allItems.push({
        rus_name: title,
        type: type,
        site_id: siteId,
        status: "В планах",
        user_chapters: progress,
        cover: cover
      });
      counts[siteId] = (counts[siteId] || 0) + 1;
    }
  }

  if (allItems.length === 0) {
    console.warn("Закладки не найдены. Убедитесь, что вы авторизованы и открыли верный профиль.");
    return;
  }

  const jsonStr = JSON.stringify(allItems, null, 2);
  try {
    if (typeof copy === "function") copy(jsonStr);
    else if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(jsonStr);
  } catch {}

  try {
    const blob = new Blob([jsonStr], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "tsundoku-sociallib.json";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(a.href);
  } catch {}

  let directUploaded = false;
  try {
    const blob = new Blob([jsonStr], { type: "application/json" });
    const formData = new FormData();
    formData.append("file", blob, "tsundoku-sociallib.json");
    formData.append("provider", "mangalib");
    formData.append("skipDuplicates", "true");
    const resp = await fetch("http://localhost:5000/api/media/import/file", {
      method: "POST",
      body: formData
    });
    if (resp.ok) {
      directUploaded = true;
    }
  } catch {}

  console.log("%c==================================================", "color:#10b981");
  console.log(\`%c🎉 УСПЕШНО СОБРАНО: \${allItems.length} тайтлов!\`, "color:#10b981;font-weight:bold;font-size:13px;");
  console.log(\`MangaLib: \${counts[1] || 0}, AnimeLib: \${counts[5] || 0}, RanobeLib: \${counts[3] || 0}, SlashLib: \${counts[2] || 0}, HentaiLib: \${counts[4] || 0}\`);
  console.log("Данные скопированы в буфер обмена и скачан файл tsundoku-sociallib.json.");
  console.log("👉 Вернитесь в Tsundoku и нажмите «Вставить из буфера и импортировать»!");
  console.log("%c==================================================", "color:#10b981");

  if (directUploaded) {
    alert("🎉 Успешно! Собрано " + allItems.length + " закладок и напрямую отправлено в Tsundoku! Проверьте библиотеку.");
  } else {
    alert("✅ Собрано " + allItems.length + " закладок! Скопировано в буфер обмена — откройте Tsundoku и нажмите «Вставить из буфера и импортировать»!");
  }
})();`;
    }

    function toBookmarkletUrl(script: string): string {
        const cleaned = script
            .replace(/^\s*\/\/[^\n\r]*/gm, "")
            .replace(/[\n\r\t]+/g, " ")
            .replace(/\s{2,}/g, " ")
            .trim();
        return `javascript:void ${cleaned}`;
    }

    let bookmarkletUrl = $derived(
        toBookmarkletUrl(
            generateSocialLibScript(
                mangalibSites,
                mangalibSelectedStatuses,
                mangalibIncludeCustomFolders,
            ),
        ),
    );
    let bookmarkletCopied = $state(false);

    async function copyBookmarkletUrl() {
        try {
            await navigator.clipboard.writeText(bookmarkletUrl);
            bookmarkletCopied = true;
            setTimeout(() => (bookmarkletCopied = false), 2500);
        } catch {
            error = "Не удалось скопировать букмарклет в буфер обмена";
        }
    }

    async function copySocialLibScript() {
        const script = generateSocialLibScript(
            mangalibSites,
            mangalibSelectedStatuses,
            mangalibIncludeCustomFolders,
        );
        try {
            await navigator.clipboard.writeText(script);
            scriptCopied = true;
            setTimeout(() => (scriptCopied = false), 2500);
        } catch {
            error = "Не удалось скопировать скрипт в буфер обмена";
        }
    }

    async function importFromClipboard() {
        if (busy) return;
        error = "";
        try {
            if (!navigator.clipboard?.readText) {
                error =
                    "Буфер обмена недоступен в вашем браузере. Выберите способ «Файл» и загрузите сохраненный tsundoku-sociallib.json.";
                return;
            }
            const text = await navigator.clipboard.readText();
            if (!text || !text.trim()) {
                error =
                    "Буфер обмена пуст. Сначала скопируйте скрипт, выполните его в консоли любого Lib-сайта, а затем нажмите эту кнопку.";
                return;
            }
            let data: any;
            try {
                data = JSON.parse(text);
            } catch {
                error =
                    "В буфере обмена нет JSON данных закладок. Убедитесь, что скрипт в консоли завершил сбор.";
                return;
            }

            let items: any[] = Array.isArray(data)
                ? data
                : (data && Array.isArray(data.data) ? data.data : []);
            items = filterMangaLibItems(items);

            const customFolders = extractCustomFolders(items);
            if (customFolders.length > 0) {
                pendingImport = { type: "clipboard", data: items };
                pendingCustomFolders = customFolders;
                showCustomFolderModal = true;
                busy = false;
                return;
            }

            busy = true;
            const clipboardFile = new File(
                [JSON.stringify(items)],
                "tsundoku-sociallib.json",
                {
                    type: "application/json",
                },
            );
            const form = new FormData();
            form.append("file", clipboardFile);
            form.append("provider", "mangalib");
            form.append("skipDuplicates", String(skipDuplicates));
            if (addToList && listMode === "existing" && targetListId)
                form.append("targetListId", targetListId);
            if (addToList && listMode === "new" && newListName.trim())
                form.append("newListName", newListName.trim());

            result = await importFile(form);
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
                <div
                    class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-emerald-400/20 text-emerald-300"
                >
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
                    <span class="block text-xs text-muted"
                        >{i18n.t.importModal.total}</span
                    >
                    <span class="mt-1 block text-xl font-bold text-ink"
                        >{result.totalFound}</span
                    >
                </div>
                <div
                    class="rounded-lg border border-emerald-400/20 bg-emerald-400/5 p-3.5"
                >
                    <span class="block text-xs text-emerald-300/80"
                        >{i18n.t.importModal.imported}</span
                    >
                    <span class="mt-1 block text-xl font-bold text-emerald-200"
                        >{result.importedCount}</span
                    >
                </div>
                <div class="rounded-lg border border-white/10 bg-card/60 p-3.5">
                    <span class="block text-xs text-muted"
                        >{i18n.t.importModal.skipped}</span
                    >
                    <span class="mt-1 block text-xl font-bold text-ink"
                        >{result.skippedDuplicates}</span
                    >
                </div>
            </div>

            {#if result.skippedTitles && result.skippedTitles.length > 0}
                <div
                    class="mt-3 rounded-lg border border-white/10 bg-card/40 p-3"
                >
                    <button
                        type="button"
                        class="flex w-full items-center justify-between text-xs font-medium text-muted hover:text-ink transition cursor-pointer"
                        onclick={() =>
                            (showSkippedDuplicates = !showSkippedDuplicates)}
                    >
                        <span
                            >Пропущено дубликатов: {result.skippedTitles
                                .length}</span
                        >
                        {#if showSkippedDuplicates}
                            <ChevronUp size={14} />
                        {:else}
                            <ChevronDown size={14} />
                        {/if}
                    </button>
                    {#if showSkippedDuplicates}
                        <p
                            class="text-xs text-muted mt-1 leading-relaxed break-words"
                        >
                            Дубликаты: {result.skippedTitles
                                .map((t) => `«${t}»`)
                                .join(", ")}
                        </p>
                    {/if}
                </div>
            {/if}

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
                    class="cursor-pointer rounded-lg border border-[#5844e0]/40 bg-[#5844e0]/15 px-4 py-2 text-sm font-semibold text-[#8f7fff] transition hover:bg-[#5844e0]/25 hover:text-white"
                    onclick={() => jobsClient.openModal("jobs")}
                >
                    {i18n.t.backgroundJobs.openProcesses}
                </button>
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
            <h3
                class="text-xs font-semibold uppercase tracking-wider text-muted"
            >
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
                            <span
                                class="block truncate text-sm font-semibold text-ink group-hover:text-white"
                            >
                                {item.title}
                            </span>
                            <span
                                class="mt-0.5 block truncate text-xs text-muted"
                            >
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
                <h3
                    class="text-xs font-semibold uppercase tracking-wider text-muted"
                >
                    {i18n.t.importModal.fileLabel}
                </h3>
                <span
                    class="text-xs font-medium"
                    style={`color: ${selectedProviderInfo.accent};`}
                >
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
                        <div
                            class="rounded-xl border border-white/[0.08] bg-card/50 p-4 space-y-2"
                        >
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
                                    placeholder={i18n.t.importModal
                                        .anilistUsernamePlaceholder}
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
                                        <LoaderCircle
                                            size={16}
                                            class="animate-spin"
                                        />
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
                                if (e.key === "Enter" || e.key === " ")
                                    fileInputRef?.click();
                            }}
                        >
                            <input
                                bind:this={fileInputRef}
                                class="hidden"
                                type="file"
                                accept={fileAccept}
                                onchange={(e) =>
                                    pickFile(e.currentTarget.files?.[0])}
                            />
                            {#if file}
                                <div class="flex flex-col items-center gap-2">
                                    <div
                                        class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                                    >
                                        <FileText size={24} />
                                    </div>
                                    <div>
                                        <p
                                            class="text-sm font-semibold text-ink"
                                        >
                                            {file.name}
                                        </p>
                                        <p class="text-xs text-muted">
                                            {(file.size / 1024).toFixed(1)} KB
                                        </p>
                                    </div>
                                    <button
                                        type="button"
                                        class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                        onclick={(e) => {
                                            e.stopPropagation();
                                            file = null;
                                            if (fileInputRef)
                                                fileInputRef.value = "";
                                        }}
                                    >
                                        {i18n.t.importModal.changeFile}
                                    </button>
                                </div>
                            {:else}
                                <div
                                    class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2"
                                >
                                    <Upload size={20} />
                                </div>
                                <span
                                    class="block text-sm font-medium text-ink"
                                >
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
                        <div
                            class="rounded-xl border border-white/[0.08] bg-card/50 p-4 space-y-3.5"
                        >
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
                                                    val,
                                                );
                                            error = profileChecked
                                                ? ""
                                                : i18n.t.importModal
                                                      .steamRequired;
                                        }}
                                    >
                                        {i18n.t.importModal.checkProfile}
                                    </button>
                                </div>
                                {#if profileChecked}
                                    <p
                                        class="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-300"
                                    >
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
                                    <p
                                        class="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-300"
                                    >
                                        <Check size={14} />
                                        {i18n.t.importModal.steamKeyConfigured}
                                    </p>
                                {/if}
                            </div>

                            <label
                                class="flex items-center gap-2 text-xs text-ink cursor-pointer select-none"
                            >
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
                                if (e.key === "Enter" || e.key === " ")
                                    fileInputRef?.click();
                            }}
                        >
                            <input
                                bind:this={fileInputRef}
                                class="hidden"
                                type="file"
                                accept={fileAccept}
                                onchange={(e) =>
                                    pickFile(e.currentTarget.files?.[0])}
                            />
                            {#if file}
                                <div class="flex flex-col items-center gap-2">
                                    <div
                                        class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                                    >
                                        <FileText size={24} />
                                    </div>
                                    <div>
                                        <p
                                            class="text-sm font-semibold text-ink"
                                        >
                                            {file.name}
                                        </p>
                                        <p class="text-xs text-muted">
                                            {(file.size / 1024).toFixed(1)} KB
                                        </p>
                                    </div>
                                    <button
                                        type="button"
                                        class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                        onclick={(e) => {
                                            e.stopPropagation();
                                            file = null;
                                            if (fileInputRef)
                                                fileInputRef.value = "";
                                        }}
                                    >
                                        {i18n.t.importModal.changeFile}
                                    </button>
                                </div>
                            {:else}
                                <div
                                    class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2"
                                >
                                    <Upload size={20} />
                                </div>
                                <span
                                    class="block text-sm font-medium text-ink"
                                >
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

                <!-- MangaLib / SocialLib Ecosystem -->
            {:else if provider === "mangalib"}
                <div class="space-y-4">
                    <!-- Site Selection Checkboxes -->
                    <div
                        class="rounded-xl border border-white/[0.08] bg-card/50 p-3.5 space-y-2.5"
                    >
                        <div class="flex items-center justify-between">
                            <span
                                class="text-xs font-semibold uppercase tracking-wider text-muted"
                            >
                                Сайты экосистемы SocialLib
                            </span>
                            <span
                                class="text-[11px] text-orange-300/80 font-medium"
                            >
                                Выбрано: {mangalibSites.length} из {socialLibSites.length}
                            </span>
                        </div>
                        <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                            {#each socialLibSites as s (s.id)}
                                {@const checked = mangalibSites.includes(s.id)}
                                <button
                                    type="button"
                                    class={`flex items-center gap-2.5 transition rounded-xl p-2.5 text-left cursor-pointer ${
                                        checked
                                            ? "border border-orange-500/20 bg-orange-500/5 text-orange-200/90 ring-1 ring-orange-500/10"
                                            : "border border-white/5 bg-white/[0.015] text-slate-400 hover:border-white/10 hover:text-slate-300"
                                    }`}
                                    onclick={() => toggleSite(s.id)}
                                >
                                    <span
                                        class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                                            checked
                                                ? "border-orange-500/40 bg-orange-500/30 text-orange-200/90"
                                                : "border-white/20 bg-black/20"
                                        }`}
                                    >
                                        {#if checked}
                                            <Check size={12} strokeWidth={3} />
                                        {/if}
                                    </span>
                                    <div class="min-w-0 flex-1">
                                        <div
                                            class="truncate text-xs font-medium"
                                        >
                                            {s.name}
                                        </div>
                                        <div
                                            class="truncate text-[10px] text-muted"
                                        >
                                            {s.tag}
                                        </div>
                                    </div>
                                </button>
                            {/each}
                        </div>
                    </div>

                    <!-- Folder Status Selection Checkboxes -->
                    <div
                        class="rounded-xl border border-white/[0.08] bg-card/50 p-3.5 space-y-2.5"
                    >
                        <div class="flex items-center justify-between">
                            <span
                                class="text-xs font-semibold uppercase tracking-wider text-muted"
                            >
                                Какие списки импортировать:
                            </span>
                            <span
                                class="text-[11px] text-orange-300/80 font-medium"
                            >
                                Выбрано: {mangalibSelectedFolders.length} из {mangalibFolderOptions.length}
                            </span>
                        </div>
                        <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                            {#each mangalibFolderOptions as opt (opt.id)}
                                {@const checked = mangalibSelectedFolders.includes(opt.id)}
                                <button
                                    type="button"
                                    class={`flex items-center gap-2.5 transition rounded-xl p-2.5 text-left cursor-pointer ${
                                        checked
                                            ? "border border-orange-500/20 bg-orange-500/5 text-orange-200/90 ring-1 ring-orange-500/10"
                                            : "border border-white/5 bg-white/[0.015] text-slate-400 hover:border-white/10 hover:text-slate-300"
                                    }`}
                                    onclick={() => toggleMangaLibFolder(opt.id)}
                                >
                                    <span
                                        class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                                            checked
                                                ? "border-orange-500/40 bg-orange-500/30 text-orange-200/90"
                                                : "border-white/20 bg-black/20"
                                        }`}
                                    >
                                        {#if checked}
                                            <Check size={12} strokeWidth={3} />
                                        {/if}
                                    </span>
                                    <span class="truncate text-xs font-medium">
                                        {opt.label}
                                    </span>
                                </button>
                            {/each}
                        </div>
                    </div>

                    <!-- Mode Switcher Tabs -->
                    <div class="flex gap-2" role="tablist">
                        <button
                            type="button"
                            role="tab"
                            aria-selected={mangalibMode === "collector"}
                            class={`flex-1 rounded-lg border px-3 py-2 text-xs font-medium transition cursor-pointer flex items-center justify-center gap-1.5 ${
                                mangalibMode === "collector"
                                    ? "border border-orange-500/20 bg-orange-500/5 text-orange-200/80 font-semibold ring-1 ring-orange-500/10"
                                    : "border-white/10 bg-card/60 text-muted hover:text-ink hover:bg-card"
                            }`}
                            onclick={() => {
                                mangalibMode = "collector";
                                error = "";
                            }}
                        >
                            <Sparkles size={14} class="text-orange-300/80" />
                            <span>Мгновенный сборщик</span>
                        </button>
                        <button
                            type="button"
                            role="tab"
                            aria-selected={mangalibMode === "file"}
                            class={`flex-1 rounded-lg border px-3 py-2 text-xs font-medium transition cursor-pointer ${
                                mangalibMode === "file"
                                    ? "border border-orange-500/20 bg-orange-500/5 text-orange-200/80 font-semibold ring-1 ring-orange-500/10"
                                    : "border-white/10 bg-card/60 text-muted hover:text-ink hover:bg-card"
                            }`}
                            onclick={() => {
                                mangalibMode = "file";
                                error = "";
                            }}
                        >
                            Файл .json / .csv
                        </button>
                    </div>

                    <!-- Mode 1: Instant Collector Script + Clipboard 1-Click Import -->
                    {#if mangalibMode === "collector"}
                        <div
                            class="rounded-xl border border-white/[0.08] bg-card/50 p-4 space-y-4"
                        >
                            <div class="space-y-1.5">
                                <div class="flex items-center gap-2">
                                    <span
                                        class="inline-flex items-center rounded-md border border-orange-500/20 bg-orange-500/10 px-2 py-0.5 text-[11px] font-medium text-orange-300/80"
                                    >
                                        Рекомендуется
                                    </span>
                                    <h4
                                        class="text-sm font-semibold text-white"
                                    >
                                        Сбор закладок за 1 секунду прямо из
                                        браузера
                                    </h4>
                                </div>
                                <p
                                    class="text-sm text-slate-300 leading-relaxed mt-2"
                                >
                                    Обходит ограничения Cloudflare, моментально
                                    извлекая закладки со всех выбранных сайтов
                                    Lib с прогрессом, оценками и статусами.
                                </p>
                            </div>

                            <!-- Bookmarklet Banner: 1-Click Import without F12 -->
                            <div
                                class="rounded-xl border border-orange-500/20 bg-gradient-to-r from-orange-500/10 via-orange-500/5 to-transparent p-4 space-y-3"
                            >
                                <div
                                    class="flex flex-wrap items-center justify-between gap-2"
                                >
                                    <div class="flex items-center gap-2">
                                        <span
                                            class="inline-flex items-center rounded-md border border-orange-500/20 bg-orange-500/10 px-2 py-0.5 text-[11px] font-medium text-orange-300/80"
                                        >
                                            1 клик без F12
                                        </span>
                                        <h4
                                            class="text-sm font-bold text-white"
                                        >
                                            Кнопка-букмарклет для браузера
                                        </h4>
                                    </div>
                                    <button
                                        type="button"
                                        class="text-xs text-orange-300/80 hover:text-white underline cursor-pointer"
                                        onclick={() =>
                                            void copyBookmarkletUrl()}
                                    >
                                        {#if bookmarkletCopied}
                                            <span
                                                class="text-emerald-400 font-medium"
                                                >Ссылка скопирована!</span
                                            >
                                        {:else}
                                            Скопировать ссылку букмарклета
                                        {/if}
                                    </button>
                                </div>
                                <p
                                    class="text-sm text-slate-300 leading-relaxed"
                                >
                                    Перетащите эту кнопку на панель закладок
                                    вашего браузера (<kbd
                                        class="rounded border border-white/10 bg-canvas px-1.5 py-0.5 text-xs font-mono text-slate-300"
                                        >Ctrl+Shift+B</kbd
                                    >). Затем откройте любую страницу MangaLib,
                                    AnimeLib или RanobeLib и
                                    <strong>просто кликните по закладке</strong
                                    >!
                                </p>
                                <div
                                    class="flex flex-wrap items-center gap-3 pt-1"
                                >
                                    <a
                                        href={bookmarkletUrl}
                                        draggable="true"
                                        class="inline-flex cursor-grab active:cursor-grabbing items-center gap-2 rounded-lg border-2 border-dashed border-orange-500/30 bg-orange-500/10 hover:bg-orange-500/15 px-4 py-2.5 text-xs font-bold text-orange-200/90 shadow-md transition hover:scale-[1.01] active:scale-95 select-none"
                                        title="Зажмите и перетащите на панель закладок браузера (Ctrl+Shift+B)"
                                        onclick={(e) => {
                                            e.preventDefault();
                                            alert(
                                                "📌 Перетащите эту кнопку мышкой на панель закладок браузера (Ctrl+Shift+B)!\n\nИли нажмите «Скопировать ссылку букмарклета» справа и создайте закладку вручную.",
                                            );
                                        }}
                                    >
                                        <span
                                            >📥 Tsundoku Импорт (перетащите в
                                            закладки)</span
                                        >
                                    </a>
                                    <span class="text-xs text-muted">
                                        ← зажмите и потяните на панель закладок
                                    </span>
                                </div>
                            </div>

                            <!-- Instructions -->
                            <ol
                                class="space-y-3 rounded-lg border border-white/5 bg-black/30 p-3.5 text-sm text-slate-200 leading-normal"
                            >
                                <li class="flex items-start gap-2.5">
                                    <span
                                        class="size-6 shrink-0 grid place-items-center rounded-full bg-orange-500/15 text-orange-300/80 font-bold text-xs"
                                        >1</span
                                    >
                                    <span
                                        >Откройте страницу своего профиля или
                                        закладок на любом сайте Lib (<a
                                            href="https://mangalib.me"
                                            target="_blank"
                                            rel="noreferrer"
                                            class="text-orange-300/80 hover:text-orange-200 hover:underline font-medium"
                                            >MangaLib</a
                                        >,
                                        <a
                                            href="https://animelib.org"
                                            target="_blank"
                                            rel="noreferrer"
                                            class="text-orange-300/80 hover:text-orange-200 hover:underline font-medium"
                                            >AnimeLib</a
                                        >,
                                        <a
                                            href="https://ranobelib.me"
                                            target="_blank"
                                            rel="noreferrer"
                                            class="text-orange-300/80 hover:text-orange-200 hover:underline font-medium"
                                            >RanobeLib</a
                                        >).</span
                                    >
                                </li>
                                <li class="flex items-start gap-2.5">
                                    <span
                                        class="size-6 shrink-0 grid place-items-center rounded-full bg-orange-500/15 text-orange-300/80 font-bold text-xs"
                                        >2</span
                                    >
                                    <span
                                        >Нажмите на закладку в браузере (или
                                        откройте консоль <kbd
                                            class="rounded border border-white/10 bg-canvas px-1.5 py-0.5 text-xs font-mono text-slate-300"
                                            >F12</kbd
                                        >, вставьте скрипт и нажмите
                                        <kbd
                                            class="rounded border border-white/10 bg-canvas px-1.5 py-0.5 text-xs font-mono text-slate-300"
                                            >Enter</kbd
                                        >). Букмарклет моментально выгрузит
                                        закладки.</span
                                    >
                                </li>
                                <li class="flex items-start gap-2.5">
                                    <span
                                        class="size-6 shrink-0 grid place-items-center rounded-full bg-orange-500/15 text-orange-300/80 font-bold text-xs"
                                        >3</span
                                    >
                                    <span
                                        >Если прямое сохранение заблокировано
                                        браузером — данные уже скопированы в
                                        буфер обмена: просто нажмите <strong
                                            >«Вставить из буфера и
                                            импортировать»</strong
                                        > ниже.</span
                                    >
                                </li>
                            </ol>

                            <!-- Actions -->
                            <div
                                class="grid grid-cols-1 sm:grid-cols-2 gap-2.5 pt-1"
                            >
                                <button
                                    type="button"
                                    class="inline-flex items-center justify-center gap-2 rounded-lg border border-white/10 bg-field px-4 py-2.5 text-sm font-medium text-slate-200 hover:border-orange-500/20 hover:bg-orange-500/5 hover:text-orange-200/90 transition cursor-pointer"
                                    onclick={() => void copySocialLibScript()}
                                >
                                    {#if scriptCopied}
                                        <Check
                                            size={16}
                                            class="text-emerald-400"
                                        />
                                        <span class="text-emerald-300"
                                            >Скрипт скопирован!</span
                                        >
                                    {:else}
                                        <Copy size={16} />
                                        <span>Скопировать скрипт сбора</span>
                                    {/if}
                                </button>

                                <button
                                    type="button"
                                    disabled={busy}
                                    class="inline-flex items-center justify-center gap-2 rounded-lg bg-orange-700/60 hover:bg-orange-600/70 border border-orange-500/25 px-4 py-2.5 text-sm font-semibold text-white/90 shadow-sm transition cursor-pointer disabled:cursor-wait disabled:opacity-60"
                                    onclick={() => void importFromClipboard()}
                                >
                                    {#if busy}
                                        <LoaderCircle
                                            size={16}
                                            class="animate-spin"
                                        />
                                        <span>Импортируем...</span>
                                    {:else}
                                        <Download size={16} />
                                        <span
                                            >Вставить из буфера и импортировать</span
                                        >
                                    {/if}
                                </button>
                            </div>
                        </div>

                        <!-- Mode 2: File Upload (.json / .csv) -->
                    {:else}
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
                                if (e.key === "Enter" || e.key === " ")
                                    fileInputRef?.click();
                            }}
                        >
                            <input
                                bind:this={fileInputRef}
                                class="hidden"
                                type="file"
                                accept={fileAccept}
                                onchange={(e) =>
                                    pickFile(e.currentTarget.files?.[0])}
                            />
                            {#if file}
                                <div class="flex flex-col items-center gap-2">
                                    <div
                                        class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                                    >
                                        <FileText size={24} />
                                    </div>
                                    <div>
                                        <p
                                            class="text-sm font-semibold text-ink"
                                        >
                                            {file.name}
                                        </p>
                                        <p class="text-xs text-muted">
                                            {(file.size / 1024).toFixed(1)} KB
                                        </p>
                                    </div>
                                    <button
                                        type="button"
                                        class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                        onclick={(e) => {
                                            e.stopPropagation();
                                            file = null;
                                            if (fileInputRef)
                                                fileInputRef.value = "";
                                        }}
                                    >
                                        {i18n.t.importModal.changeFile}
                                    </button>
                                </div>
                            {:else}
                                <div
                                    class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2"
                                >
                                    <Upload size={20} />
                                </div>
                                <span
                                    class="block text-sm font-medium text-ink"
                                >
                                    {i18n.t.importModal.dropFile}
                                </span>
                                <span class="mt-1 block text-xs text-muted">
                                    {i18n.t.importModal.supportsMangaLibFiles}
                                </span>
                            {/if}
                        </div>
                    {/if}
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
                            if (e.key === "Enter" || e.key === " ")
                                fileInputRef?.click();
                        }}
                    >
                        <input
                            bind:this={fileInputRef}
                            class="hidden"
                            type="file"
                            accept={fileAccept}
                            onchange={(e) =>
                                pickFile(e.currentTarget.files?.[0])}
                        />
                        {#if file}
                            <div class="flex flex-col items-center gap-2">
                                <div
                                    class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                                >
                                    <FileText size={24} />
                                </div>
                                <div>
                                    <p class="text-sm font-semibold text-ink">
                                        {file.name}
                                    </p>
                                    <p class="text-xs text-muted">
                                        {(file.size / 1024).toFixed(1)} KB
                                    </p>
                                </div>
                                <button
                                    type="button"
                                    class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                    onclick={(e) => {
                                        e.stopPropagation();
                                        file = null;
                                        if (fileInputRef)
                                            fileInputRef.value = "";
                                    }}
                                >
                                    {i18n.t.importModal.changeFile}
                                </button>
                            </div>
                        {:else}
                            <div
                                class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2"
                            >
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
                    <div
                        class="rounded-xl border border-white/[0.08] bg-card/60"
                    >
                        <button
                            type="button"
                            aria-expanded={showTemplate}
                            class="flex w-full items-center justify-between p-3.5 text-left text-xs font-medium text-ink transition hover:bg-white/5 cursor-pointer"
                            onclick={() => (showTemplate = !showTemplate)}
                        >
                            <span class="flex items-center gap-2">
                                <FileText size={16} class="text-[#a78bfa]" />
                                <span
                                    >{showTemplate
                                        ? i18n.t.importModal.hideTemplate
                                        : i18n.t.importModal.showTemplate}</span
                                >
                            </span>
                            {#if showTemplate}
                                <ChevronUp size={16} class="text-muted" />
                            {:else}
                                <ChevronDown size={16} class="text-muted" />
                            {/if}
                        </button>

                        {#if showTemplate}
                            <div
                                class="border-t border-white/[0.08] p-4 space-y-3 bg-black/20"
                            >
                                <div>
                                    <div
                                        class="mb-1.5 flex items-center justify-between"
                                    >
                                        <span
                                            class="text-xs font-semibold uppercase tracking-wider text-muted"
                                        >
                                            {i18n.t.importModal
                                                .templateJsonLabel}
                                        </span>
                                        <button
                                            type="button"
                                            class="inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 bg-field px-2.5 py-1 text-xs text-ink transition hover:bg-elevated hover:text-white"
                                            onclick={() =>
                                                void copyJsonTemplate()}
                                        >
                                            {#if templateCopied}
                                                <Check
                                                    size={12}
                                                    class="text-emerald-400"
                                                />
                                                <span class="text-emerald-300"
                                                    >{i18n.t.importModal
                                                        .templateCopied}</span
                                                >
                                            {:else}
                                                <Copy size={12} />
                                                <span
                                                    >{i18n.t.importModal
                                                        .copyTemplate}</span
                                                >
                                            {/if}
                                        </button>
                                    </div>
                                    <pre
                                        class="max-h-44 overflow-auto rounded-lg border border-white/10 bg-black/40 p-3 text-[11px] leading-relaxed text-emerald-300 thin-scroll font-mono">{templateJson}</pre>
                                </div>

                                <div>
                                    <div
                                        class="mb-1.5 flex items-center justify-between"
                                    >
                                        <span
                                            class="text-xs font-semibold uppercase tracking-wider text-muted"
                                        >
                                            {i18n.t.importModal
                                                .templateCsvLabel}
                                        </span>
                                        <button
                                            type="button"
                                            class="inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 bg-field px-2.5 py-1 text-xs text-ink transition hover:bg-elevated hover:text-white"
                                            onclick={() =>
                                                void copyCsvTemplate()}
                                        >
                                            {#if csvCopied}
                                                <Check
                                                    size={12}
                                                    class="text-emerald-400"
                                                />
                                                <span class="text-emerald-300"
                                                    >{i18n.t.importModal
                                                        .templateCopied}</span
                                                >
                                            {:else}
                                                <Copy size={12} />
                                                <span
                                                    >{i18n.t.importModal
                                                        .copyTemplate}</span
                                                >
                                            {/if}
                                        </button>
                                    </div>
                                    <pre
                                        class="overflow-auto rounded-lg border border-white/10 bg-black/40 p-2.5 text-[11px] text-emerald-300 thin-scroll font-mono">{templateCsv}</pre>
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
                            if (e.key === "Enter" || e.key === " ")
                                fileInputRef?.click();
                        }}
                    >
                        <input
                            bind:this={fileInputRef}
                            class="hidden"
                            type="file"
                            accept={fileAccept}
                            onchange={(e) =>
                                pickFile(e.currentTarget.files?.[0])}
                        />
                        {#if file}
                            <div class="flex flex-col items-center gap-2">
                                <div
                                    class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                                >
                                    <FileText size={24} />
                                </div>
                                <div>
                                    <p class="text-sm font-semibold text-ink">
                                        {file.name}
                                    </p>
                                    <p class="text-xs text-muted">
                                        {(file.size / 1024).toFixed(1)} KB
                                    </p>
                                </div>
                                <button
                                    type="button"
                                    class="mt-1 cursor-pointer rounded-md border border-white/10 bg-field px-3 py-1 text-xs font-medium text-muted hover:bg-elevated hover:text-white"
                                    onclick={(e) => {
                                        e.stopPropagation();
                                        file = null;
                                        if (fileInputRef)
                                            fileInputRef.value = "";
                                    }}
                                >
                                    {i18n.t.importModal.changeFile}
                                </button>
                            </div>
                        {:else}
                            <div
                                class="grid h-11 w-11 place-items-center rounded-full bg-field text-muted mb-2"
                            >
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
        <section
            class="rounded-xl border border-white/[0.08] bg-card/60 p-4 space-y-3.5"
        >
            <h3
                class="text-xs font-semibold uppercase tracking-wider text-muted"
            >
                {i18n.t.importModal.optionsTitle}
            </h3>

            <div class="space-y-2.5">
                <label
                    class="flex items-center gap-2.5 text-sm text-ink cursor-pointer select-none"
                >
                    <input
                        type="checkbox"
                        bind:checked={skipDuplicates}
                        class="rounded border-white/20 bg-field accent-accent"
                    />
                    <span>{i18n.t.importModal.skipDuplicates}</span>
                </label>

                <label
                    class="flex items-center gap-2.5 text-sm text-ink cursor-pointer select-none"
                >
                    <input
                        type="checkbox"
                        bind:checked={addToList}
                        class="rounded border-white/20 bg-field accent-accent"
                    />
                    <span>{i18n.t.importModal.addToList}</span>
                </label>
            </div>

            {#if addToList}
                <div
                    class="ml-6 space-y-3 border-l-2 border-white/10 pl-4 pt-1"
                >
                    <div class="flex flex-wrap gap-4 text-xs">
                        <label
                            class="flex items-center gap-2 text-ink cursor-pointer"
                        >
                            <input
                                type="radio"
                                bind:group={listMode}
                                value="new"
                                class="accent-accent"
                            />
                            <span>{i18n.t.importModal.newList}</span>
                        </label>
                        <label
                            class="flex items-center gap-2 text-ink cursor-pointer"
                        >
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
                                <option value=""
                                    >{i18n.t.importModal.selectList}</option
                                >
                                {#each lists as list (list.id)}
                                    <option value={list.id}>{list.name}</option>
                                {/each}
                            </select>
                        </div>
                    {/if}
                </div>
            {/if}

            <!-- Folder Selection Filter (Common Options) -->
            {#if provider !== "mangalib"}
                <div class="space-y-2 pt-2 border-t border-white/5">
                    <div class="flex items-center justify-between">
                        <span
                            class="text-xs font-semibold uppercase tracking-wider text-muted"
                        >
                            Какие списки импортировать:
                        </span>
                        <span class="text-[11px] text-accent-soft font-medium">
                            Выбрано: {selectedStatuses.length} из {folderFilterOptions.length}
                        </span>
                    </div>
                    <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                        {#each folderFilterOptions as opt (opt.id)}
                            {@const checked = selectedStatuses.includes(opt.id)}
                            <button
                                type="button"
                                class={`flex items-center gap-2.5 transition rounded-xl p-2.5 text-left cursor-pointer ${
                                    checked
                                        ? "border border-accent/40 bg-accent/15 text-accent-soft ring-1 ring-accent/20"
                                        : "border border-white/10 bg-white/[0.02] text-slate-400 hover:border-white/20 hover:text-white"
                                }`}
                                onclick={() => toggleStatus(opt.id)}
                            >
                                <span
                                    class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                                        checked
                                            ? "border-accent bg-accent text-white"
                                            : "border-white/30 bg-black/20"
                                    }`}
                                >
                                    {#if checked}
                                        <Check size={12} strokeWidth={3} />
                                    {/if}
                                </span>
                                <span class="truncate text-xs font-medium">
                                    {opt.label}
                                </span>
                            </button>
                        {/each}
                    </div>
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

    <!-- Custom Folder Setup Modal -->
    <Modal
        isOpen={showCustomFolderModal}
        onClose={cancelCustomFolderModal}
        labelledBy="custom-folder-setup-title"
        size="md"
    >
        <div class="p-6 space-y-5">
            <div class="flex items-start gap-3.5">
                <div
                    class="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-orange-500/20 bg-orange-500/10 text-orange-300/80"
                >
                    <FolderInput size={20} />
                </div>
                <div class="min-w-0 flex-1">
                    <h3
                        id="custom-folder-setup-title"
                        class="text-base font-semibold text-white"
                    >
                        {i18n.t.importModal.customFoldersTitle}
                    </h3>
                    <p class="mt-1 text-xs text-slate-300 leading-relaxed">
                        {i18n.t.importModal.customFoldersExplanation}
                    </p>
                </div>
            </div>

            <!-- List of custom folders -->
            <div class="space-y-3 max-h-[60vh] overflow-y-auto pr-1">
                {#each pendingCustomFolders as folder, idx (folder.name)}
                    <div
                        class="p-3.5 rounded-xl border border-white/5 bg-white/[0.02] space-y-3"
                    >
                        <div
                            class="flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                        >
                            <div class="flex items-center gap-2 min-w-0">
                                <span class="font-bold text-white text-sm truncate">
                                    «{folder.name}»
                                </span>
                                <span class="text-xs text-muted shrink-0">
                                    ({i18n.t.importModal.customFolderCountLabel(folder.count)})
                                </span>
                            </div>

                            <div class="shrink-0">
                                <PopoverMenu
                                    id="custom-folder-status-{idx}"
                                    options={customFolderStatusOptions}
                                    selected={folder.status}
                                    onSelect={(val) => {
                                        folder.status = val as CustomFolderStatus;
                                    }}
                                    label={i18n.t.importModal.customFoldersStatusLabel}
                                    placement="bottom-end"
                                >
                                    {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
                                        <button
                                            type="button"
                                            popovertarget={popoverTargetId}
                                            popovertargetaction="toggle"
                                            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                                            class="tap flex h-9 items-center justify-between gap-2 rounded-lg border border-white/10 bg-field px-3 text-xs font-semibold text-white transition hover:border-white/20 min-w-[140px]"
                                        >
                                            <span class="truncate">
                                                {customFolderStatusOptions.find((o) => o.value === folder.status)?.label ?? folder.status}
                                            </span>
                                            <ChevronDown size={14} class="shrink-0 text-muted" aria-hidden="true" />
                                        </button>
                                    {/snippet}
                                </PopoverMenu>
                            </div>
                        </div>

                        <label class="flex items-center gap-2.5 cursor-pointer select-none">
                            <input
                                type="checkbox"
                                bind:checked={folder.createList}
                                disabled={folder.status === "skip"}
                                class="rounded border-white/20 bg-field accent-orange-500/60 disabled:opacity-40"
                            />
                            <span
                                class="text-sm text-slate-200 font-medium leading-snug {folder.status === 'skip' ? 'opacity-40' : ''}"
                            >
                                {i18n.t.importModal.customFoldersCreateListFor(folder.name)}
                            </span>
                        </label>
                    </div>
                {/each}
            </div>

            <div
                class="flex items-center justify-end gap-2.5 border-t border-white/[0.07] pt-4"
            >
                <button
                    type="button"
                    disabled={busy}
                    class="inline-flex h-9 items-center rounded-lg border border-white/10 bg-field px-4 text-xs font-semibold text-slate-300 transition hover:bg-card hover:text-white cursor-pointer disabled:opacity-50"
                    onclick={cancelCustomFolderModal}
                >
                    {i18n.t.common.cancel}
                </button>
                <button
                    type="button"
                    disabled={busy}
                    class="inline-flex h-9 items-center justify-center gap-2 rounded-lg bg-orange-700/60 hover:bg-orange-600/70 border border-orange-500/25 px-5 text-xs font-semibold text-white/90 shadow-sm transition cursor-pointer disabled:opacity-50"
                    onclick={() => void continueImportWithCustomFolders()}
                >
                    {#if busy}
                        <LoaderCircle size={14} class="animate-spin" />
                        <span>{i18n.t.common.loading}</span>
                    {:else}
                        <span>{i18n.t.importModal.continueImport}</span>
                    {/if}
                </button>
            </div>
        </div>
    </Modal>
</div>
