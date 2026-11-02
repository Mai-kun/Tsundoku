<script module lang="ts">
  // Matching patterns using unicode escapes to avoid raw Cyrillic literals
  const ON_HOLD_RE =
    /(?:\u0436\u0434\u0443|\u043e\u0436\u0438\u0434|\u043f\u0430\u0443\u0437|\u043e\u0442\u043b\u043e\u0436|hold|wait|pause)/i;
  const DROPPED_RE =
    /(?:\u0443\u0434\u0430\u043b\u0435\u043d|\u0434\u0440\u043e\u043f|\u0431\u0440\u043e\u0448|drop)/i;
  const READING_RE =
    /(?:\u0447\u0438\u0442\u0430\u044e|\u0441\u043c\u043e\u0442\u0440\u0443|\u043f\u0435\u0440\u0435\u0441\u043c\u0430\u0442\u0440|reading|watching|rewatching|in_progress|in progress)/i;
  const PLANNED_RE =
    /(?:\u043f\u043b\u0430\u043d|\u0437\u0430\u043f\u043b\u0430\u043d\u0438\u0440\u043e\u0432\u0430\u043d\u043e|\u0431\u0443\u0434\u0443|planned|plan_to_watch)/i;
  const COMPLETED_RE =
    /(?:\u043f\u0440\u043e\u0447\u0438\u0442\u0430\u043d\u043e|\u043f\u0440\u043e\u0441\u043c\u043e\u0442\u0440\u0435\u043d\u043e|completed|finished|watched)/i;
  const FAVORITE_RE = /(?:\u043b\u044e\u0431\u0438\u043c|favorite)/i;
  const NUMERIC_ID_RE = /^\d+$/;
  const STEAM_ID_RE = /^\d{17}$/;
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import {
    detectMangalibBrowserSession,
    getLists,
    getSources,
    importAniListProfile,
    importFile,
    importMangaLibProfile,
    importSteamProfile,
    openMangalibLoginPage,
    saveSourceKey,
  } from "$shared/api/api";
  import type { CustomListSummary, ImportResultDto } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import Select from "$shared/ui/Select.svelte";
  import PopoverMenu, { type PopoverOption } from "$shared/ui/PopoverMenu.svelte";
  import {
    adoptBrowserSession,
    disconnectMangalib,
    mangalibAuth,
    refreshMangalibAuth,
    saveMangalibToken,
  } from "./mangalibAuth.svelte";
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
    Key,
    LoaderCircle,
    Sparkles,
    Upload,
    X,
  } from "$shared/ui/Icons";

  interface Props {
    onImportCompleted?: () => void;
    onNavigateToList?: (id: string) => void;
    onClose?: () => void;
    showCloseButton?: boolean;
  }

  let { onImportCompleted, onNavigateToList, onClose, showCloseButton = false }: Props = $props();

  type Provider =
    | "anilist"
    | "mangalib"
    | "mal"
    | "shikimori"
    | "letterboxd"
    | "goodreads"
    | "steam"
    | "anixart"
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
  let lists = $state.raw<CustomListSummary[]>([]);
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
  let showSkippedDuplicates = $state(false);
  // One-click profile import (native auth): User ID is remembered by the
  // mangalibAuth store once the token has been captured.
  let mangalibProfileInput = $state("");
  let mangalibOneClickBusy = $state(false);
  // Manual token fallback (browser mode or when the native window is unavailable).
  let showManualTokenInput = $state(false);
  let manualTokenInput = $state("");
  let manualTokenBusy = $state(false);
  // Automatic browser-session pickup (server reads Zen/Firefox/Chromium profiles).
  let mangalibDetectBusy = $state(false);
  let mangalibDetectFailed = $state(false);

  // MangaLib folder options: standard 5 + custom folders
  interface MangaLibFolderOption {
    id: number | "custom";
    label: string;
  }

  const mangalibFolderOptions = $derived<MangaLibFolderOption[]>([
    { id: 1, label: i18n.t.importModal.reading },
    { id: 2, label: i18n.t.importModal.planned },
    { id: 4, label: i18n.t.importModal.completed },
    { id: 5, label: i18n.t.importModal.favorites },
    { id: 3, label: i18n.t.importModal.dropped },
    { id: "custom", label: i18n.t.importModal.customFolders },
  ]);

  let mangalibSelectedFolders = $state<(number | "custom")[]>([1, 2, 4, 5, "custom"]);

  function toggleMangaLibFolder(id: number | "custom") {
    if (mangalibSelectedFolders.includes(id)) {
      if (mangalibSelectedFolders.length > 1) {
        mangalibSelectedFolders = mangalibSelectedFolders.filter((s) => s !== id);
      }
    } else {
      mangalibSelectedFolders = [...mangalibSelectedFolders, id];
    }
  }

  let mangalibSelectedStatuses = $derived(
    mangalibSelectedFolders.filter((x): x is number => typeof x === "number"),
  );
  let mangalibIncludeCustomFolders = $derived(mangalibSelectedFolders.includes("custom"));

  // Custom folder modal setup
  export type CustomFolderStatus = "Planned" | "OnHold" | "InProgress" | "Dropped" | "skip";

  export interface CustomFolderItem {
    name: string;
    count: number;
    status: CustomFolderStatus;
    createList: boolean;
  }

  let showCustomFolderModal = $state(false);
  let pendingCustomFolders = $state.raw<CustomFolderItem[]>([]);

  let customFolderStatusOptions = $derived<PopoverOption<CustomFolderStatus>[]>([
    { value: "Planned", label: i18n.t.importModal.statusPlanned },
    { value: "OnHold", label: i18n.t.importModal.statusOnHold },
    { value: "InProgress", label: i18n.t.importModal.statusInProgress },
    { value: "Dropped", label: i18n.t.importModal.statusDropped },
    { value: "skip", label: i18n.t.importModal.statusSkip },
  ]);

  let anixartCreateFavoritesList = $state(true);
  let anixartUnwatchingStatus = $state<
    "Planned" | "Completed" | "InProgress" | "OnHold" | "Dropped" | "skip"
  >("Planned");

  const anixartUnwatchingStatusOptions = $derived<
    PopoverOption<"Planned" | "Completed" | "InProgress" | "OnHold" | "Dropped" | "skip">[]
  >([
    { value: "Planned", label: i18n.t.importModal.statusPlanned },
    { value: "Completed", label: i18n.t.importModal.statusCompleted },
    { value: "InProgress", label: i18n.t.importModal.statusInProgress },
    { value: "OnHold", label: i18n.t.importModal.statusOnHold },
    { value: "Dropped", label: i18n.t.importModal.statusDropped },
    { value: "skip", label: i18n.t.importModal.statusSkip },
  ]);

  type PendingImport =
    { type: "clipboard"; data: any[] } | { type: "file"; file: File; data?: any[] };

  let pendingImport = $state<PendingImport | null>(null);

  function cancelCustomFolderModal() {
    showCustomFolderModal = false;
    pendingImport = null;
    pendingCustomFolders = [];
    busy = false;
  }

  function getDefaultStatusForFolder(name: string): CustomFolderStatus {
    const s = name.trim().toLowerCase();
    if (ON_HOLD_RE.test(s)) {
      return "OnHold";
    }
    if (DROPPED_RE.test(s)) {
      return "Dropped";
    }
    return "Planned";
  }

  function isStandardStatusName(name: string): boolean {
    const s = name.toLowerCase().trim();
    return (
      READING_RE.test(s) ||
      PLANNED_RE.test(s) ||
      COMPLETED_RE.test(s) ||
      FAVORITE_RE.test(s) ||
      ON_HOLD_RE.test(s) ||
      DROPPED_RE.test(s)
    );
  }

  function isCustomMangaLibFolder(item: any): boolean {
    if (!item || typeof item !== "object") return false;

    const name = String(
      item.folder_name ?? item.folder?.name ?? item.status ?? item.status_name ?? "",
    ).trim();

    // Standard AnimeLib & MangaLib statuses are NEVER custom folders:
    if (name && isStandardStatusName(name)) {
      return false;
    }

    if (item.is_custom_folder === true) return true;
    if (item.is_custom_folder === false) return false;

    const rawCode =
      item.status_id ?? item.folder_id ?? (typeof item.status === "number" ? item.status : null);
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
        item.folder_name ?? item.folder?.name ?? item.status ?? item.status_name ?? "",
      ).trim() ||
      i18n.t.importModal.customFolderDefaultName ||
      "Custom folder"
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
      const configMap: Record<string, { status?: string; createList: boolean; skip: boolean }> = {};
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

        uploadFile = new File([JSON.stringify(filtered)], "tsundoku-sociallib.json", {
          type: "application/json",
        });
      } else if (currentPending.data && Array.isArray(currentPending.data)) {
        const filtered = currentPending.data.filter((item) => {
          if (isCustomMangaLibFolder(item)) {
            const name = getCustomFolderName(item);
            const cfg = configMap[name];
            if (cfg?.skip) return false;
          }
          return true;
        });

        uploadFile = new File([JSON.stringify(filtered)], currentPending.file.name, {
          type: currentPending.file.type || "application/json",
        });
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
      error = caught instanceof Error ? caught.message : i18n.t.importModal.failed;
    } finally {
      busy = false;
    }
  }

  // Folder status filtering
  interface FolderFilterOption {
    id: number;
    label: string;
  }

  const folderFilterOptions = $derived<FolderFilterOption[]>([
    { id: 1, label: i18n.t.importModal.readingWatching },
    { id: 2, label: i18n.t.importModal.planned },
    { id: 4, label: i18n.t.importModal.completed },
    { id: 6, label: i18n.t.importModal.onHoldWaiting },
    { id: 3, label: i18n.t.importModal.droppedRemoved },
    { id: 5, label: i18n.t.importModal.favorites },
  ]);

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
      item.status ?? item.folder_name ?? item.folder?.name ?? item.status_name ?? "",
    ).toLowerCase();
    if (DROPPED_RE.test(name)) return 3;
    if (READING_RE.test(name)) return 1;
    if (PLANNED_RE.test(name)) return 2;
    if (COMPLETED_RE.test(name)) return 4;
    if (FAVORITE_RE.test(name)) return 5;
    if (ON_HOLD_RE.test(name)) return 6;
    if (
      typeof rawStatus === "number" ||
      (typeof rawStatus === "string" && NUMERIC_ID_RE.test(rawStatus))
    ) {
      const num = Number(rawStatus);
      if (num >= 1 && num <= 5) return num;
      return 6;
    }
    return 2;
  }

  const socialLibSites = $derived<
    {
      id: number;
      name: string;
      tag: string;
      type: string;
    }[]
  >([
    { id: 1, name: "MangaLib", tag: i18n.t.importModal.mangaLibSub, type: "manga" },
    { id: 5, name: "AnimeLib", tag: i18n.t.importModal.animeLibSub, type: "anime" },
    { id: 3, name: "RanobeLib", tag: i18n.t.importModal.ranobeLibSub, type: "book" },
    { id: 2, name: "SlashLib / YaoiLib", tag: i18n.t.importModal.slashLibSub, type: "manga" },
    { id: 4, name: "HentaiLib", tag: i18n.t.importModal.hentaiLibSub, type: "manga" },
  ]);

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
      border: string;
      surface: string;
      text: string;
    }[]
  >([
    {
      id: "anilist",
      icon: "AL",
      title: "AniList",
      subtitle: i18n.t.importModal.subtitleAnilist,
      accent: "var(--color-import-anilist-accent)",
      border: "var(--color-import-anilist-border)",
      surface: "var(--color-import-anilist-surface)",
      text: "var(--color-import-anilist-text)",
    },
    {
      id: "mangalib",
      icon: "ML",
      title: "MangaLib",
      subtitle: i18n.t.importModal.subtitleMangalib,
      accent: "var(--color-import-mangalib-accent)",
      border: "var(--color-import-mangalib-border)",
      surface: "var(--color-import-mangalib-surface)",
      text: "var(--color-import-mangalib-text)",
    },
    {
      id: "mal",
      icon: "MAL",
      title: "MyAnimeList",
      subtitle: "XML / JSON",
      accent: "var(--color-import-shikimori-accent)",
      border: "var(--color-import-shikimori-border)",
      surface: "var(--color-import-shikimori-surface)",
      text: "var(--color-import-shikimori-text)",
    },
    {
      id: "shikimori",
      icon: "SH",
      title: "Shikimori",
      subtitle: "XML / JSON",
      accent: "var(--color-import-shikimori-accent)",
      border: "var(--color-import-shikimori-border)",
      surface: "var(--color-import-shikimori-surface)",
      text: "var(--color-import-shikimori-text)",
    },
    {
      id: "letterboxd",
      icon: "L",
      title: "Letterboxd",
      subtitle: "Movie CSV",
      accent: "var(--color-import-letterboxd-accent)",
      border: "var(--color-import-letterboxd-border)",
      surface: "var(--color-import-letterboxd-surface)",
      text: "var(--color-import-letterboxd-text)",
    },
    {
      id: "goodreads",
      icon: "G",
      title: "Goodreads",
      subtitle: "Book CSV",
      accent: "var(--color-import-goodreads-accent)",
      border: "var(--color-import-goodreads-border)",
      surface: "var(--color-import-goodreads-surface)",
      text: "var(--color-import-goodreads-text)",
    },
    {
      id: "steam",
      icon: "S",
      title: "Steam",
      subtitle: "Games / Profile",
      accent: "var(--color-import-steam-accent)",
      border: "var(--color-import-steam-border)",
      surface: "var(--color-import-steam-surface)",
      text: "var(--color-import-steam-text)",
    },
    {
      id: "anixart",
      icon: "AX",
      title: "Anixart",
      subtitle: i18n.t.importModal.subtitleAnixart,
      accent: "var(--color-import-anixart-accent)",
      border: "var(--color-import-anixart-border)",
      surface: "var(--color-import-anixart-surface)",
      text: "var(--color-import-anixart-text)",
    },
    {
      id: "custom",
      icon: "{ }",
      title: i18n.t.importModal.customTitle,
      subtitle: i18n.t.importModal.subtitleCustom,
      accent: "var(--color-import-custom-accent)",
      border: "var(--color-import-custom-border)",
      surface: "var(--color-import-custom-surface)",
      text: "var(--color-import-custom-text)",
    },
  ]);

  const selectedProviderInfo = $derived(providers.find((p) => p.id === provider) ?? providers[0]);

  const fileAccept = $derived(
    provider === "mal" || provider === "shikimori"
      ? ".xml,.json"
      : provider === "letterboxd" || provider === "goodreads" || provider === "anixart"
        ? ".csv"
        : provider === "steam" || provider === "anilist"
          ? ".json"
          : ".json,.csv",
  );

  const allowedExtensions = $derived(
    provider === "mal" || provider === "shikimori"
      ? ["xml", "json"]
      : provider === "letterboxd" || provider === "goodreads" || provider === "anixart"
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
      anixart: i18n.t.importModal.helpAnixart,
      custom: i18n.t.importModal.helpCustom,
    }[provider],
  );

  const defaultListName = $derived(i18n.t.importModal.defaultList(selectedProviderInfo.title));

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
      steamKeyConfigured = sources.some((s) => s.id === "steam" && s.hasKey);
    } catch {
      // fallback
    }
    void refreshMangalibAuth();
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
    const anilistProfileMode = provider === "anilist" && anilistMode === "profile";
    const steamProfileMode = provider === "steam" && steamMode === "profile";

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
      // The collector tab is auth-driven: the footer button mirrors the card's
      // primary action instead of reading a clipboard payload.
      void importMangaLibOneClick();
      return;
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
          ...(STEAM_ID_RE.test(value) ? { steamId: value } : { profileUrl: value }),
          steamApiKey: steamApiKey.trim() || undefined,
          skipDuplicates,
          ...listFields,
        });
      } else {
        let uploadFile = file!;
        if (file && (file.name.endsWith(".json") || provider === "mangalib")) {
          try {
            const raw = await file.text();
            let parsedData = JSON.parse(raw);
            let modified = false;
            if (provider === "mangalib") {
              let items = Array.isArray(parsedData)
                ? parsedData
                : parsedData && Array.isArray(parsedData.data)
                  ? parsedData.data
                  : [];
              items = filterMangaLibItems(items);
              const customFolders = extractCustomFolders(items);
              if (customFolders.length > 0) {
                uploadFile = new File([JSON.stringify(items)], file.name, {
                  type: file.type || "application/json",
                });
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
              } else if (parsedData && Array.isArray(parsedData.data)) {
                parsedData.data = items;
              }
              modified = true;
            } else {
              if (Array.isArray(parsedData)) {
                parsedData = parsedData.filter((item) =>
                  selectedStatuses.includes(getItemStatusCode(item)),
                );
                modified = true;
              } else if (parsedData && Array.isArray(parsedData.data)) {
                parsedData.data = parsedData.data.filter((item: any) =>
                  selectedStatuses.includes(getItemStatusCode(item)),
                );
                modified = true;
              }
            }
            if (modified) {
              uploadFile = new File([JSON.stringify(parsedData)], file.name, {
                type: file.type || "application/json",
              });
            }
          } catch {
            // ignore if not valid JSON
          }
        }
        const form = new FormData();
        form.append("file", uploadFile);
        form.append("provider", provider);
        form.append("skipDuplicates", String(skipDuplicates));
        if (addToList && listMode === "existing") form.append("targetListId", targetListId);
        if (addToList && listMode === "new") form.append("newListName", newListName.trim());
        if (provider === "anixart") {
          form.append("createCustomLists", String(anixartCreateFavoritesList));
          if (anixartUnwatchingStatus !== "skip") {
            form.append("customFolderStatus", anixartUnwatchingStatus);
          }
        }
        importTask = importFile(form);
      }

      const saveKeyTask =
        provider === "steam" && steamProfileMode && saveSteamKey && steamApiKey.trim()
          ? saveSourceKey("steam", steamApiKey.trim())
          : Promise.resolve();

      [result] = await Promise.all([importTask, saveKeyTask]);
      onImportCompleted?.();
      void loadListsAndSources();
    } catch (caught) {
      error = caught instanceof Error ? caught.message : i18n.t.importModal.failed;
    } finally {
      busy = false;
    }
  }

  function resetImport() {
    result = null;
    file = null;
    error = "";
  }

  /** Direct API import using the token captured by the native auth window. */
  async function importMangaLibOneClick() {
    if (mangalibOneClickBusy) return;
    // The remembered User ID makes this a true 1-click import; the field is
    // only needed to override or when nothing was remembered yet.
    const idOrUrl = mangalibProfileInput.trim() || mangalibAuth.userId;
    if (!idOrUrl) {
      error = i18n.t.importModal.mangalibAuth.userIdRequired;
      return;
    }

    mangalibOneClickBusy = true;
    error = "";
    try {
      const listFields = addToList
        ? listMode === "existing"
          ? { targetListId }
          : { newListName: newListName.trim() }
        : {};
      // bearerToken stays unset on purpose: the server falls back to the
      // encrypted source key saved by the native auth flow.
      result = await importMangaLibProfile({
        profileUrlOrId: idOrUrl,
        siteIds: mangalibSites,
        statusIds: mangalibSelectedStatuses,
        skipDuplicates,
        ...listFields,
      });
      onImportCompleted?.();
      void loadListsAndSources();
    } catch (caught) {
      error = caught instanceof Error ? caught.message : i18n.t.importModal.failed;
    } finally {
      mangalibOneClickBusy = false;
    }
  }

  /** Persists a hand-pasted token, then flips the card to the connected state. */
  async function saveManualMangalibToken() {
    if (manualTokenBusy) return;
    manualTokenBusy = true;
    error = "";
    const saved = await saveMangalibToken(manualTokenInput);
    manualTokenBusy = false;
    if (saved) {
      manualTokenInput = "";
      showManualTokenInput = false;
    }
  }

  /** Asks the server to find the SocialLib session in the user's browsers. */
  async function detectMangalibSession() {
    if (mangalibDetectBusy) return;
    mangalibDetectBusy = true;
    error = "";
    mangalibDetectFailed = false;
    try {
      const result = await detectMangalibBrowserSession();
      if (result === null) {
        // 404: no browser session — surface the "open login page" fallback.
        mangalibDetectFailed = true;
        return;
      }
      await adoptBrowserSession(result.userId);
    } catch (caught) {
      console.error("mangalib browser session detection failed:", caught);
      showToast(i18n.t.importModal.mangalibAuth.detectFailedToast, "error");
    } finally {
      mangalibDetectBusy = false;
    }
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
    "title": "Berserk",
    "type": "manga",
    "status": "reading",
    "score": 10,
    "progress": 350,
    "totalCount": 374,
    "author": "Kentaro Miura",
    "year": 1989
  }
]`;

  const templateCsv = "title,type,status,score,progress,totalCount,author,releaseYear";

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

<div
  class="space-y-6"
  style={`--imp-accent: ${selectedProviderInfo.accent}; --imp-border: ${selectedProviderInfo.border}; --imp-surface: ${selectedProviderInfo.surface}; --imp-text: ${selectedProviderInfo.text};`}
>
  <!-- Section Header -->
  <div class="flex items-start justify-between gap-4">
    <div>
      <h2 class="text-ink text-base font-semibold sm:text-lg">
        {i18n.t.importModal.title}
      </h2>
      <p class="text-muted mt-1 text-xs sm:text-sm">
        {i18n.t.importModal.description}
      </p>
    </div>
    {#if showCloseButton && onClose}
      <button
        type="button"
        class="text-muted grid h-8 w-8 place-items-center rounded-lg transition hover:bg-white/10 hover:text-white"
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
        <div class="bg-card/60 rounded-lg border border-white/10 p-3.5">
          <span class="text-muted block text-xs">{i18n.t.importModal.total}</span>
          <span class="text-ink mt-1 block text-xl font-bold">{result.totalFound}</span>
        </div>
        <div class="rounded-lg border border-emerald-400/20 bg-emerald-400/5 p-3.5">
          <span class="block text-xs text-emerald-300/80">{i18n.t.importModal.imported}</span>
          <span class="mt-1 block text-xl font-bold text-emerald-200">{result.importedCount}</span>
        </div>
        <div class="bg-card/60 rounded-lg border border-white/10 p-3.5">
          <span class="text-muted block text-xs">{i18n.t.importModal.skipped}</span>
          <span class="text-ink mt-1 block text-xl font-bold">{result.skippedDuplicates}</span>
        </div>
      </div>

      {#if result.skippedTitles && result.skippedTitles.length > 0}
        <div class="bg-card/40 mt-3 rounded-lg border border-white/10 p-3">
          <button
            type="button"
            class="text-muted hover:text-ink flex w-full cursor-pointer items-center justify-between text-xs font-medium transition"
            onclick={() => (showSkippedDuplicates = !showSkippedDuplicates)}
          >
            <span>{i18n.t.importModal.skippedDuplicatesWithCount(result.skippedTitles.length)}</span
            >
            {#if showSkippedDuplicates}
              <ChevronUp size={14} />
            {:else}
              <ChevronDown size={14} />
            {/if}
          </button>
          {#if showSkippedDuplicates}
            <p class="text-muted mt-1 text-xs leading-relaxed break-words">
              {i18n.t.importModal.duplicatesWithTitles(result.skippedTitles.join(", "))}
            </p>
          {/if}
        </div>
      {/if}

      <div class="mt-6 flex flex-wrap items-center gap-3">
        {#if result.targetListId}
          <button
            type="button"
            class="cursor-pointer rounded-lg bg-[var(--imp-accent)] px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90"
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
          class="cursor-pointer rounded-lg border border-[#5446cf]/40 bg-[#5446cf]/15 px-4 py-2 text-sm font-semibold text-[#8f7fff] transition hover:bg-[#5446cf]/25 hover:text-white"
          onclick={() => jobsClient.openModal("jobs")}
        >
          {i18n.t.backgroundJobs.openProcesses}
        </button>
        <button
          type="button"
          class="bg-field text-ink hover:bg-elevated cursor-pointer rounded-lg border border-white/10 px-4 py-2 text-sm font-medium transition hover:text-white"
          onclick={resetImport}
        >
          {i18n.t.importModal.importAnother}
        </button>
        {#if showCloseButton && onClose}
          <button
            type="button"
            class="text-muted hover:text-ink cursor-pointer rounded-lg border border-white/10 px-4 py-2 text-sm transition hover:bg-white/5"
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
        class="mb-2.5 flex items-center gap-2 text-xs font-bold tracking-wider text-slate-200 uppercase"
      >
        <span class="size-1.5 rounded-full bg-[var(--imp-accent)]"></span>
        {i18n.t.importModal.source}
      </h3>
      <div class="grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-4">
        {#each providers as item (item.id)}
          {@const isSelected = provider === item.id}
          <button
            type="button"
            class={`group relative flex cursor-pointer items-center gap-3 rounded-xl border p-3 text-left transition ${
              isSelected
                ? "shadow-md ring-1 ring-inset"
                : "bg-card/80 hover:bg-card border-white/10 hover:border-white/20"
            }`}
            style={isSelected
              ? `border-color: ${item.accent}; --tw-ring-color: ${item.border}; background-color: ${item.surface};`
              : undefined}
            onclick={() => selectProvider(item.id)}
          >
            <span
              class="grid h-10 w-10 shrink-0 place-items-center rounded-lg text-sm font-bold transition"
              style={`background-color: ${item.surface}; color: ${item.text}; border: 1px solid ${item.border};`}
            >
              {item.icon}
            </span>
            <div class="min-w-0 flex-1">
              <span class="text-ink block truncate text-sm font-semibold group-hover:text-white">
                {item.title}
              </span>
              <span class="text-muted mt-0.5 block truncate text-xs">
                {item.subtitle}
              </span>
            </div>
            {#if isSelected}
              <span class="shrink-0 rounded-full p-0.5" style={`color: ${item.accent};`}>
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
          class="mb-2.5 flex items-center gap-2 text-xs font-bold tracking-wider text-slate-200 uppercase"
        >
          <span class="size-1.5 rounded-full bg-[var(--imp-accent)]"></span>
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
              class={`flex-1 cursor-pointer rounded-lg border px-3.5 py-2 text-xs font-medium transition ${
                anilistMode === "profile"
                  ? "border-[var(--color-import-anilist-border)] bg-[var(--color-import-anilist-surface)] font-semibold text-[var(--color-import-anilist-text)]"
                  : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
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
              class={`flex-1 cursor-pointer rounded-lg border px-3.5 py-2 text-xs font-medium transition ${
                anilistMode === "file"
                  ? "border-[var(--color-import-anilist-border)] bg-[var(--color-import-anilist-surface)] font-semibold text-[var(--color-import-anilist-text)]"
                  : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
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
            <div class="bg-card/50 space-y-2 rounded-xl border border-white/[0.08] p-4">
              <label class="text-muted block text-xs font-medium" for="anilist-username">
                {i18n.t.importModal.anilistUsername}
              </label>
              <div class="flex gap-2">
                <input
                  id="anilist-username"
                  bind:value={anilistUsername}
                  placeholder={i18n.t.importModal.anilistUsernamePlaceholder}
                  class="bg-field text-ink min-w-0 flex-1 rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[var(--imp-accent)] focus:ring-1 focus:ring-[var(--imp-accent)]"
                  onkeydown={(e) => {
                    if (e.key === "Enter") void runImport();
                  }}
                />
                <button
                  type="button"
                  class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-[var(--color-import-anilist-accent)] px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:cursor-wait disabled:opacity-60"
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
              class={`relative flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
                dragging
                  ? "border-[var(--color-import-anilist-accent)] bg-[var(--color-import-anilist-surface)]"
                  : file
                    ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                    : "bg-card/60 hover:bg-card border-white/15 hover:border-white/30"
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
                  <div
                    class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                  >
                    <FileText size={24} />
                  </div>
                  <div>
                    <p class="text-ink text-sm font-semibold">
                      {file.name}
                    </p>
                    <p class="text-muted text-xs">
                      {(file.size / 1024).toFixed(1)} KB
                    </p>
                  </div>
                  <button
                    type="button"
                    class="bg-field text-muted hover:bg-elevated mt-1 cursor-pointer rounded-md border border-white/10 px-3 py-1 text-xs font-medium hover:text-white"
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
                <div
                  class="bg-field text-muted mb-2 grid h-11 w-11 place-items-center rounded-full"
                >
                  <Upload size={20} />
                </div>
                <span class="text-ink block text-sm font-medium">
                  {i18n.t.importModal.dropFile}
                </span>
                <span class="text-muted mt-1 block text-xs">
                  {i18n.t.importModal.formats(fileAccept)}
                </span>
              {/if}
            </div>
          {/if}

          <p class="text-muted text-xs leading-relaxed">
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
              class={`flex-1 cursor-pointer rounded-lg border px-3.5 py-2 text-xs font-medium transition ${
                steamMode === "profile"
                  ? "border-[var(--color-import-steam-border)] bg-[var(--color-import-steam-surface)] font-semibold text-[var(--color-import-steam-text)]"
                  : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
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
              class={`flex-1 cursor-pointer rounded-lg border px-3.5 py-2 text-xs font-medium transition ${
                steamMode === "file"
                  ? "border-[var(--color-import-steam-border)] bg-[var(--color-import-steam-surface)] font-semibold text-[var(--color-import-steam-text)]"
                  : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
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
            <div class="bg-card/50 space-y-3.5 rounded-xl border border-white/[0.08] p-4">
              <div>
                <label class="text-muted mb-1 block text-xs font-medium" for="steam-profile">
                  {i18n.t.importModal.steamProfile}
                </label>
                <div class="flex gap-2">
                  <input
                    id="steam-profile"
                    bind:value={steamProfile}
                    oninput={() => (profileChecked = false)}
                    placeholder="https://steamcommunity.com/id/... or 76561198..."
                    class="bg-field text-ink min-w-0 flex-1 rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[var(--imp-accent)] focus:ring-1 focus:ring-[var(--imp-accent)]"
                  />
                  <button
                    type="button"
                    class="bg-field text-ink hover:bg-elevated cursor-pointer rounded-lg border border-white/10 px-3.5 text-xs font-medium transition hover:text-white"
                    onclick={() => {
                      const val = steamProfile.trim();
                      profileChecked =
                        /^\d{17}$/.test(val) ||
                        /^https?:\/\/(www\.)?steamcommunity\.com\/(id|profiles)\/[^/]+\/?$/i.test(
                          val,
                        );
                      error = profileChecked ? "" : i18n.t.importModal.steamRequired;
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
                <label class="text-muted mb-1 block text-xs font-medium" for="steam-api-key">
                  {i18n.t.importModal.steamApiKey}
                </label>
                <input
                  id="steam-api-key"
                  type="password"
                  bind:value={steamApiKey}
                  autocomplete="off"
                  placeholder="••••••••••••••••••••••••••••••••"
                  class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[var(--imp-accent)] focus:ring-1 focus:ring-[var(--imp-accent)]"
                />
                {#if steamKeyConfigured}
                  <p class="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-300">
                    <Check size={14} />
                    {i18n.t.importModal.steamKeyConfigured}
                  </p>
                {/if}
              </div>

              <label class="text-ink flex cursor-pointer items-center gap-2 text-xs select-none">
                <input
                  type="checkbox"
                  bind:checked={saveSteamKey}
                  class="bg-field rounded border-white/20 accent-[var(--imp-accent)]"
                />
                <span>{i18n.t.importModal.saveSteamKey}</span>
              </label>
            </div>
          {:else}
            <!-- Steam JSON File Drag & Drop -->
            <div
              class={`relative flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
                dragging
                  ? "border-[var(--color-import-steam-accent)] bg-[var(--color-import-steam-surface)]"
                  : file
                    ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                    : "bg-card/60 hover:bg-card border-white/15 hover:border-white/30"
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
                  <div
                    class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                  >
                    <FileText size={24} />
                  </div>
                  <div>
                    <p class="text-ink text-sm font-semibold">
                      {file.name}
                    </p>
                    <p class="text-muted text-xs">
                      {(file.size / 1024).toFixed(1)} KB
                    </p>
                  </div>
                  <button
                    type="button"
                    class="bg-field text-muted hover:bg-elevated mt-1 cursor-pointer rounded-md border border-white/10 px-3 py-1 text-xs font-medium hover:text-white"
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
                <div
                  class="bg-field text-muted mb-2 grid h-11 w-11 place-items-center rounded-full"
                >
                  <Upload size={20} />
                </div>
                <span class="text-ink block text-sm font-medium">
                  {i18n.t.importModal.dropFile}
                </span>
                <span class="text-muted mt-1 block text-xs">
                  {i18n.t.importModal.formats(fileAccept)}
                </span>
              {/if}
            </div>
          {/if}

          <p class="text-muted text-xs leading-relaxed">
            {helpText}
            <a
              href="https://steamcommunity.com/dev/apikey"
              target="_blank"
              rel="noreferrer"
              class="inline-flex items-center gap-1 text-[var(--imp-text)] underline hover:text-white"
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
          <div class="bg-card/50 space-y-2.5 rounded-xl border border-white/[0.08] p-3.5">
            <div class="flex items-center justify-between">
              <h3
                class="mb-2.5 flex items-center gap-2 text-xs font-bold tracking-wider text-slate-200 uppercase"
              >
                <span class="size-1.5 rounded-full bg-[var(--color-import-mangalib-accent)]"></span>
                {i18n.t.importModal.socialLibSites}
              </h3>
              <span class="text-[11px] font-medium text-[var(--color-import-mangalib-text)]">
                {i18n.t.importModal.selectedOf(mangalibSites.length, socialLibSites.length)}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {#each socialLibSites as s (s.id)}
                {@const checked = mangalibSites.includes(s.id)}
                <button
                  type="button"
                  class={`flex cursor-pointer items-center gap-2.5 rounded-xl p-2.5 text-left transition ${
                    checked
                      ? "border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] text-[var(--color-import-mangalib-text)] ring-1 ring-[var(--color-import-mangalib-border)]"
                      : "border border-white/5 bg-white/[0.015] text-slate-400 hover:border-white/10 hover:text-slate-300"
                  }`}
                  onclick={() => toggleSite(s.id)}
                >
                  <span
                    class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                      checked
                        ? "border-[var(--color-import-mangalib-accent)] bg-[var(--color-import-mangalib-accent)]/30 text-[var(--color-import-mangalib-text)]"
                        : "border-white/20 bg-black/20"
                    }`}
                  >
                    {#if checked}
                      <Check size={12} strokeWidth={3} />
                    {/if}
                  </span>
                  <div class="min-w-0 flex-1">
                    <div class="truncate text-xs font-medium">
                      {s.name}
                    </div>
                    <div class="text-muted truncate text-[10px]">
                      {s.tag}
                    </div>
                  </div>
                </button>
              {/each}
            </div>
          </div>

          <!-- Folder Status Selection Checkboxes -->
          <div class="bg-card/50 space-y-2.5 rounded-xl border border-white/[0.08] p-3.5">
            <div class="flex items-center justify-between">
              <h3
                class="mb-2.5 flex items-center gap-2 text-xs font-bold tracking-wider text-slate-200 uppercase"
              >
                <span class="size-1.5 rounded-full bg-[var(--color-import-mangalib-accent)]"></span>
                {i18n.t.importModal.listsToImport}
              </h3>
              <span class="text-[11px] font-medium text-[var(--color-import-mangalib-text)]">
                {i18n.t.importModal.selectedOf(
                  mangalibSelectedFolders.length,
                  mangalibFolderOptions.length,
                )}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {#each mangalibFolderOptions as opt (opt.id)}
                {@const checked = mangalibSelectedFolders.includes(opt.id)}
                <button
                  type="button"
                  class={`flex cursor-pointer items-center gap-2.5 rounded-xl p-2.5 text-left transition ${
                    checked
                      ? "border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] text-[var(--color-import-mangalib-text)] ring-1 ring-[var(--color-import-mangalib-border)]"
                      : "border border-white/5 bg-white/[0.015] text-slate-400 hover:border-white/10 hover:text-slate-300"
                  }`}
                  onclick={() => toggleMangaLibFolder(opt.id)}
                >
                  <span
                    class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                      checked
                        ? "border-[var(--color-import-mangalib-accent)] bg-[var(--color-import-mangalib-accent)]/30 text-[var(--color-import-mangalib-text)]"
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
              class={`flex flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-lg border px-3 py-2 text-xs font-medium transition ${
                mangalibMode === "collector"
                  ? "border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] font-semibold text-[var(--color-import-mangalib-text)] ring-1 ring-[var(--color-import-mangalib-border)]"
                  : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
              }`}
              onclick={() => {
                mangalibMode = "collector";
                error = "";
              }}
            >
              <Sparkles size={14} class="text-[var(--color-import-mangalib-accent)]" />
              <span>{i18n.t.importModal.instantCollector}</span>
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mangalibMode === "file"}
              class={`flex-1 cursor-pointer rounded-lg border px-3 py-2 text-xs font-medium transition ${
                mangalibMode === "file"
                  ? "border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] font-semibold text-[var(--color-import-mangalib-text)] ring-1 ring-[var(--color-import-mangalib-border)]"
                  : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
              }`}
              onclick={() => {
                mangalibMode = "file";
                error = "";
              }}
            >
              {i18n.t.importModal.fileJsonCsv}
            </button>
          </div>

          <!-- Mode 1: Authorization + one-click API import -->
          {#if mangalibMode === "collector"}
            <div class="bg-card/50 space-y-3 rounded-xl border border-white/[0.08] p-4">
              {#if mangalibAuth.checking}
                <div class="text-muted flex items-center justify-center gap-2 p-4 text-sm">
                  <LoaderCircle size={16} class="animate-spin" />
                  <span>{i18n.t.importModal.mangalibAuth.checking}</span>
                </div>
              {:else if mangalibAuth.connected}
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <span
                    class="inline-flex items-center gap-1.5 rounded-md border border-emerald-400/40 bg-emerald-500/15 px-2 py-0.5 text-[11px] font-semibold text-emerald-300"
                  >
                    <Check size={12} strokeWidth={3} />
                    {i18n.t.importModal.mangalibAuth.connected}{#if mangalibAuth.userId}
                      &nbsp;·&nbsp;{i18n.t.importModal.mangalibAuth.connectedAs(
                        mangalibAuth.userId,
                      )}
                    {/if}
                  </span>
                  <div class="flex items-center gap-3">
                    <button
                      type="button"
                      class="cursor-pointer text-xs text-[var(--color-import-mangalib-text)] underline hover:text-white"
                      onclick={() => void openMangalibLoginPage()}
                    >
                      {i18n.t.importModal.mangalibAuth.reconnect}
                    </button>
                    <button
                      type="button"
                      class="cursor-pointer text-xs text-rose-300 underline hover:text-rose-200"
                      onclick={() => void disconnectMangalib()}
                    >
                      {i18n.t.importModal.mangalibAuth.logout}
                    </button>
                  </div>
                </div>
                <p class="text-sm leading-relaxed text-slate-300">
                  {i18n.t.importModal.mangalibAuth.oneClickHint}
                </p>
                <div class="flex flex-col gap-2 sm:flex-row">
                  <input
                    id="mangalib-profile-id"
                    bind:value={mangalibProfileInput}
                    placeholder={mangalibAuth.userId ||
                      "123456 · https://mangalib.org/ru/users/123456"}
                    class="bg-field text-ink min-w-0 flex-1 rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[var(--imp-accent)] focus:ring-1 focus:ring-[var(--imp-border)]"
                    onkeydown={(e) => {
                      if (e.key === "Enter") void importMangaLibOneClick();
                    }}
                  />
                  <button
                    type="button"
                    disabled={mangalibOneClickBusy}
                    class="inline-flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-accent-dim)] px-4 py-2 text-sm font-semibold whitespace-nowrap text-white shadow-sm transition hover:bg-[var(--color-import-mangalib-accent)] disabled:cursor-wait disabled:opacity-60"
                    onclick={() => void importMangaLibOneClick()}
                  >
                    {#if mangalibOneClickBusy}
                      <LoaderCircle size={16} class="animate-spin" />
                      <span>{i18n.t.importModal.importingStatus}</span>
                    {:else}
                      <Download size={16} />
                      <span>{i18n.t.importModal.mangalibAuth.importNow}</span>
                    {/if}
                  </button>
                </div>
              {:else}
                <!-- Compact auth card: explanation left, actions right -->
                <div
                  class="flex flex-col gap-4 rounded-xl border border-white/5 bg-white/[0.02] p-4 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div class="min-w-0">
                    <p class="text-sm font-semibold text-white">
                      {i18n.t.importModal.mangalibAuth.detectTitle}
                    </p>
                    <p class="text-muted mt-0.5 text-xs leading-relaxed">
                      {i18n.t.importModal.mangalibAuth.detectHint}
                    </p>
                    {#if mangalibDetectFailed}
                      <p class="mt-1.5 text-xs font-medium text-amber-300" role="status">
                        {i18n.t.importModal.mangalibAuth.detectNotFound}
                      </p>
                    {/if}
                  </div>
                  <div class="flex shrink-0 items-center gap-1.5">
                    <button
                      type="button"
                      disabled={mangalibDetectBusy}
                      class="w-auto inline-flex cursor-pointer items-center gap-2 rounded-lg bg-[#c25e2e] hover:bg-[#b05224] text-white shadow-sm px-3.5 py-2 text-xs font-semibold transition disabled:cursor-wait disabled:opacity-60"
                      onclick={() => void detectMangalibSession()}
                    >
                      {#if mangalibDetectBusy}
                        <LoaderCircle size={14} class="animate-spin" />
                      {:else}
                        <Key size={14} />
                      {/if}
                      <span>{i18n.t.importModal.mangalibAuth.detectButton}</span>
                    </button>
                    <button
                      type="button"
                      class="inline-flex cursor-pointer items-center gap-1.5 rounded-lg px-3 py-2 text-xs text-slate-400 transition hover:text-white"
                      onclick={() => void openMangalibLoginPage()}
                    >
                      <span>{i18n.t.importModal.mangalibAuth.openLoginPage}</span>
                      <ExternalLink size={13} aria-hidden="true" />
                    </button>
                  </div>
                </div>

                <!-- Manual token fallback: subtle spoiler link at the bottom -->
                <div>
                  <button
                    type="button"
                    aria-expanded={showManualTokenInput}
                    class="text-muted inline-flex cursor-pointer items-center gap-1.5 px-1 text-left text-xs transition hover:text-white"
                    onclick={() => (showManualTokenInput = !showManualTokenInput)}
                  >
                    <span>{i18n.t.importModal.mangalibAuth.manualTokenTitle}</span>
                    {#if showManualTokenInput}
                      <ChevronUp size={13} />
                    {:else}
                      <ChevronDown size={13} />
                    {/if}
                  </button>
                  {#if showManualTokenInput}
                    <div class="mt-2 flex flex-col gap-2 sm:flex-row">
                      <input
                        bind:value={manualTokenInput}
                        placeholder={i18n.t.importModal.mangalibAuth.manualTokenPlaceholder}
                        class="bg-field text-ink min-w-0 flex-1 rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[var(--imp-accent)] focus:ring-1 focus:ring-[var(--imp-border)]"
                      />
                      <button
                        type="button"
                        disabled={manualTokenBusy || manualTokenInput.trim() === ""}
                        class="bg-field text-ink hover:bg-elevated inline-flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-white/10 px-4 py-2 text-sm font-medium whitespace-nowrap transition hover:text-white disabled:cursor-wait disabled:opacity-60"
                        onclick={() => void saveManualMangalibToken()}
                      >
                        {#if manualTokenBusy}
                          <LoaderCircle size={14} class="animate-spin" />
                        {:else}
                          <Check size={14} />
                        {/if}
                        <span>{i18n.t.importModal.mangalibAuth.manualTokenSave}</span>
                      </button>
                    </div>
                  {/if}
                </div>
              {/if}
            </div>

            <!-- Mode 2: File Upload (.json / .csv) -->
          {:else}
            <div
              class={`relative flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
                dragging
                  ? "border-[var(--imp-accent)] bg-[var(--imp-surface)]"
                  : file
                    ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                    : "bg-card/60 hover:bg-card border-white/15 hover:border-white/30"
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
                  <div
                    class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                  >
                    <FileText size={24} />
                  </div>
                  <div>
                    <p class="text-ink text-sm font-semibold">
                      {file.name}
                    </p>
                    <p class="text-muted text-xs">
                      {(file.size / 1024).toFixed(1)} KB
                    </p>
                  </div>
                  <button
                    type="button"
                    class="bg-field text-muted hover:bg-elevated mt-1 cursor-pointer rounded-md border border-white/10 px-3 py-1 text-xs font-medium hover:text-white"
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
                <div
                  class="bg-field text-muted mb-2 grid h-11 w-11 place-items-center rounded-full"
                >
                  <Upload size={20} />
                </div>
                <span class="text-ink block text-sm font-medium">
                  {i18n.t.importModal.dropFile}
                </span>
                <span class="text-muted mt-1 block text-xs">
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
            class={`relative flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
              dragging
                ? "border-[var(--color-import-custom-accent)] bg-[var(--color-import-custom-surface)]"
                : file
                  ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                  : "bg-card/60 hover:bg-card border-white/15 hover:border-white/30"
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
                <div
                  class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                >
                  <FileText size={24} />
                </div>
                <div>
                  <p class="text-ink text-sm font-semibold">
                    {file.name}
                  </p>
                  <p class="text-muted text-xs">
                    {(file.size / 1024).toFixed(1)} KB
                  </p>
                </div>
                <button
                  type="button"
                  class="bg-field text-muted hover:bg-elevated mt-1 cursor-pointer rounded-md border border-white/10 px-3 py-1 text-xs font-medium hover:text-white"
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
              <div class="bg-field text-muted mb-2 grid h-11 w-11 place-items-center rounded-full">
                <Upload size={20} />
              </div>
              <span class="text-ink block text-sm font-medium">
                {i18n.t.importModal.dropFile}
              </span>
              <span class="text-muted mt-1 block text-xs">
                {i18n.t.importModal.formats(fileAccept)}
              </span>
            {/if}
          </div>

          <p class="text-muted text-xs leading-relaxed">
            {helpText}
          </p>

          <!-- Template Accordion -->
          <div class="bg-card/60 rounded-xl border border-white/[0.08]">
            <button
              type="button"
              aria-expanded={showTemplate}
              class="text-ink flex w-full cursor-pointer items-center justify-between p-3.5 text-left text-xs font-medium transition hover:bg-white/5"
              onclick={() => (showTemplate = !showTemplate)}
            >
              <span class="flex items-center gap-2">
                <FileText size={16} class="text-[var(--color-import-custom-accent)]" />
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
              <div class="space-y-3 border-t border-white/[0.08] bg-black/20 p-4">
                <div>
                  <div class="mb-1.5 flex items-center justify-between">
                    <span class="text-muted text-xs font-semibold tracking-wider uppercase">
                      {i18n.t.importModal.templateJsonLabel}
                    </span>
                    <button
                      type="button"
                      class="bg-field text-ink hover:bg-elevated inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 px-2.5 py-1 text-xs transition hover:text-white"
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
                  <pre
                    class="thin-scroll max-h-44 overflow-auto rounded-lg border border-white/10 bg-black/40 p-3 font-mono text-[11px] leading-relaxed text-emerald-300">{templateJson}</pre>
                </div>

                <div>
                  <div class="mb-1.5 flex items-center justify-between">
                    <span class="text-muted text-xs font-semibold tracking-wider uppercase">
                      {i18n.t.importModal.templateCsvLabel}
                    </span>
                    <button
                      type="button"
                      class="bg-field text-ink hover:bg-elevated inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 px-2.5 py-1 text-xs transition hover:text-white"
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
                  <pre
                    class="thin-scroll overflow-auto rounded-lg border border-white/10 bg-black/40 p-2.5 font-mono text-[11px] text-emerald-300">{templateCsv}</pre>
                </div>
              </div>
            {/if}
          </div>
        </div>

        <!-- Standard Providers (MAL, Shikimori, Letterboxd, Goodreads, MangaLib) -->
      {:else}
        <div class="space-y-3">
          <div
            class={`relative flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
              dragging
                ? "border-[var(--imp-accent)] bg-[var(--imp-surface)]"
                : file
                  ? "border-emerald-500/40 bg-emerald-500/5 hover:border-emerald-500/60"
                  : "bg-card/60 hover:bg-card border-white/15 hover:border-white/30"
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
                <div
                  class="grid h-12 w-12 place-items-center rounded-full bg-emerald-500/20 text-emerald-400"
                >
                  <FileText size={24} />
                </div>
                <div>
                  <p class="text-ink text-sm font-semibold">
                    {file.name}
                  </p>
                  <p class="text-muted text-xs">
                    {(file.size / 1024).toFixed(1)} KB
                  </p>
                </div>
                <button
                  type="button"
                  class="bg-field text-muted hover:bg-elevated mt-1 cursor-pointer rounded-md border border-white/10 px-3 py-1 text-xs font-medium hover:text-white"
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
              <div class="bg-field text-muted mb-2 grid h-11 w-11 place-items-center rounded-full">
                <Upload size={20} />
              </div>
              <span class="text-ink block text-sm font-medium">
                {i18n.t.importModal.dropFile}
              </span>
              <span class="text-muted mt-1 block text-xs">
                {i18n.t.importModal.formats(fileAccept)}
              </span>
            {/if}
          </div>

          <p class="text-muted text-xs leading-relaxed">
            {helpText}
          </p>
        </div>
      {/if}
    </section>

    <!-- Block 3: Import Options -->
    <section class="bg-card/60 space-y-3.5 rounded-xl border border-white/[0.08] p-4">
      <h3 class="text-muted text-xs font-semibold tracking-wider uppercase">
        {i18n.t.importModal.optionsTitle}
      </h3>

      <div class="space-y-2.5">
        <label class="text-ink flex cursor-pointer items-center gap-2.5 text-sm select-none">
          <input
            type="checkbox"
            bind:checked={skipDuplicates}
            class="bg-field rounded border-white/20 accent-[var(--imp-accent)]"
          />
          <span>{i18n.t.importModal.skipDuplicates}</span>
        </label>

        <label class="text-ink flex cursor-pointer items-center gap-2.5 text-sm select-none">
          <input
            type="checkbox"
            bind:checked={addToList}
            class="bg-field rounded border-white/20 accent-[var(--imp-accent)]"
          />
          <span>{i18n.t.importModal.addToList}</span>
        </label>
      </div>

      {#if addToList}
        <div class="ml-6 space-y-3 border-l-2 border-white/10 pt-1 pl-4">
          <div class="flex flex-wrap gap-4 text-xs">
            <label class="text-ink flex cursor-pointer items-center gap-2">
              <input
                type="radio"
                bind:group={listMode}
                value="new"
                class="accent-[var(--imp-accent)]"
              />
              <span>{i18n.t.importModal.newList}</span>
            </label>
            <label class="text-ink flex cursor-pointer items-center gap-2">
              <input
                type="radio"
                bind:group={listMode}
                value="existing"
                class="accent-[var(--imp-accent)]"
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
                class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[var(--imp-accent)] focus:ring-1 focus:ring-[var(--imp-accent)]"
              />
            </div>
          {:else}
            <div>
              <Select
                id="import-target-list"
                options={[
                  { value: "", label: i18n.t.importModal.selectList },
                  ...lists.map((list) => ({ value: list.id, label: list.name })),
                ]}
                value={targetListId}
                onChange={(next) => (targetListId = next)}
                class="w-full rounded-lg px-3 py-2 text-sm"
              />
            </div>
          {/if}
        </div>
      {/if}

      {#if provider === "anixart"}
        <div class="space-y-3 rounded-xl border border-purple-500/20 bg-purple-500/5 p-3.5">
          <label class="text-ink flex cursor-pointer items-center gap-2.5 text-sm select-none">
            <input
              type="checkbox"
              bind:checked={anixartCreateFavoritesList}
              class="rounded border-white/20 accent-[var(--imp-accent)]"
            />
            <span>{i18n.t.importModal.anixartFavoritesCheckbox}</span>
          </label>

          <div class="space-y-1.5 pt-1">
            <label for="anixart-unwatching-status" class="text-muted block text-xs font-medium">
              {i18n.t.importModal.anixartUnwatchingStatusLabel}
            </label>
            <Select
              id="anixart-unwatching-status"
              options={anixartUnwatchingStatusOptions}
              value={anixartUnwatchingStatus}
              onChange={(next) => (anixartUnwatchingStatus = next)}
              class="w-full rounded-lg px-3 py-2 text-sm"
            />
          </div>
        </div>
      {/if}

      <!-- Folder Selection Filter (Common Options) -->
      {#if provider !== "mangalib" && provider !== "anixart"}
        <div class="space-y-2 border-t border-white/5 pt-2">
          <div class="flex items-center justify-between">
            <h3
              class="mb-2.5 flex items-center gap-2 text-xs font-bold tracking-wider text-slate-200 uppercase"
            >
              <span class="size-1.5 rounded-full bg-[var(--imp-accent)]"></span>
              {i18n.t.importModal.listsToImport}
            </h3>
            <span class="text-[11px] font-medium text-[var(--imp-text)]">
              {i18n.t.importModal.selectedOf(selectedStatuses.length, folderFilterOptions.length)}
            </span>
          </div>
          <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {#each folderFilterOptions as opt (opt.id)}
              {@const checked = selectedStatuses.includes(opt.id)}
              <button
                type="button"
                class={`flex cursor-pointer items-center gap-2.5 rounded-xl p-2.5 text-left transition ${
                  checked
                    ? "border border-[var(--imp-border)] bg-[var(--imp-surface)] text-[var(--imp-text)] ring-1 ring-[var(--imp-border)]"
                    : "border border-white/10 bg-white/[0.02] text-slate-400 hover:border-white/20 hover:text-white"
                }`}
                onclick={() => toggleStatus(opt.id)}
              >
                <span
                  class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                    checked
                      ? "border-[var(--imp-accent)] bg-[var(--imp-accent)] text-white"
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
        class="bg-accent hover:bg-accent-hover inline-flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 px-5 py-2.5 text-sm font-semibold text-white transition disabled:cursor-wait disabled:opacity-60"
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
    <div class="space-y-5 p-6">
      <div class="flex items-start gap-3.5">
        <div
          class="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-orange-500/20 bg-orange-500/10 text-orange-300/80"
        >
          <FolderInput size={20} />
        </div>
        <div class="min-w-0 flex-1">
          <h3 id="custom-folder-setup-title" class="text-base font-semibold text-white">
            {i18n.t.importModal.customFoldersTitle}
          </h3>
          <p class="mt-1 text-xs leading-relaxed text-slate-300">
            {i18n.t.importModal.customFoldersExplanation}
          </p>
        </div>
      </div>

      <!-- List of custom folders -->
      <div class="max-h-[60vh] space-y-3 overflow-y-auto pr-1">
        {#each pendingCustomFolders as folder, idx (folder.name)}
          <div class="space-y-3 rounded-xl border border-white/5 bg-white/[0.02] p-3.5">
            <div class="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
              <div class="flex min-w-0 items-center gap-2">
                <span class="truncate text-sm font-bold text-white">
                  «{folder.name}»
                </span>
                <span class="text-muted shrink-0 text-xs">
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
                      class="tap bg-field flex h-9 min-w-[140px] items-center justify-between gap-2 rounded-lg border border-white/10 px-3 text-xs font-semibold text-white transition hover:border-white/20"
                    >
                      <span class="truncate">
                        {customFolderStatusOptions.find((o) => o.value === folder.status)?.label ??
                          folder.status}
                      </span>
                      <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
                    </button>
                  {/snippet}
                </PopoverMenu>
              </div>
            </div>

            <label class="flex cursor-pointer items-center gap-2.5 select-none">
              <input
                type="checkbox"
                bind:checked={folder.createList}
                disabled={folder.status === "skip"}
                class="bg-field rounded border-white/20 accent-orange-500/60 disabled:opacity-40"
              />
              <span
                class="text-sm leading-snug font-medium text-slate-200 {folder.status === 'skip'
                  ? 'opacity-40'
                  : ''}"
              >
                {i18n.t.importModal.customFoldersCreateListFor(folder.name)}
              </span>
            </label>
          </div>
        {/each}
      </div>

      <div class="flex items-center justify-end gap-2.5 border-t border-white/[0.07] pt-4">
        <button
          type="button"
          disabled={busy}
          class="bg-field hover:bg-card inline-flex h-9 cursor-pointer items-center rounded-lg border border-white/10 px-4 text-xs font-semibold text-slate-300 transition hover:text-white disabled:opacity-50"
          onclick={cancelCustomFolderModal}
        >
          {i18n.t.common.cancel}
        </button>
        <button
          type="button"
          disabled={busy}
          class="inline-flex h-9 cursor-pointer items-center justify-center gap-2 rounded-lg border border-orange-500/25 bg-orange-700/60 px-5 text-xs font-semibold text-white/90 shadow-sm transition hover:bg-orange-600/70 disabled:opacity-50"
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
