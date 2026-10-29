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
  let pendingCustomFolders = $state<CustomFolderItem[]>([]);

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

  // Matching patterns using unicode escapes to avoid raw Cyrillic literals
  const ON_HOLD_RE =
    /(?:\u0436\u0434\u0443|\u043E\u0436\u0438\u0434|\u043F\u0430\u0443\u0437|\u043E\u0442\u043B\u043E\u0436|hold|wait|pause)/i;
  const DROPPED_RE =
    /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0434\u0440\u043E\u043F|\u0431\u0440\u043E\u0448|drop)/i;
  const READING_RE =
    /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching|in_progress|in progress)/i;
  const PLANNED_RE =
    /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|\u0431\u0443\u0434\u0443|planned|plan_to_watch)/i;
  const COMPLETED_RE =
    /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|finished|watched)/i;
  const FAVORITE_RE = /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i;

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
      (typeof rawStatus === "string" && /^\d+$/.test(rawStatus))
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
      accent: "#a855f7",
      border: "rgba(168, 85, 247, 0.3)",
      surface: "rgba(168, 85, 247, 0.1)",
      text: "#c084fc",
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
          ...(/^\d{17}$/.test(value) ? { steamId: value } : { profileUrl: value }),
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
  const urlMatch = window.location.pathname.match(/\/(?:ru\/)?user[s]?\/(\d+)/i) || window.location.pathname.match(/\/user\/(\d+)/);
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
    userId = prompt("Tsundoku: Enter Lib numeric User ID (e.g.: 123456):");
    if (!userId) { console.error("Export cancelled: User ID not provided."); return; }
    userId = userId.trim().replace(/\D+/g, "");
  }

  console.log("%c[Tsundoku SocialLib Collector]%c Starting bookmarks export for User ID:", "color:#ff6740;font-weight:bold", "", userId);

  // Auth token in SocialLib is stored in localStorage.auth as JSON: { token: { access_token } }
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

    // 3. Scan all localStorage keys for valid JWT (eyJ...)
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        const val = localStorage.getItem(key);
        if (!val) continue;
        if (val.startsWith("eyJ") && val.includes(".")) return val.trim();
        try {
          const parsed = JSON.parse(val);
          const match = JSON.stringify(parsed).match(/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/);
          if (match) return match[0];
        } catch {}
      }
    } catch {}

    return null;
  };
  const token = getAuthToken();
  console.log("Auth token:", token ? \`✅ found (\${token.slice(0, 15)}...)\` : "❌ not found (guest mode, limit 100 titles)");

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
    return /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching|in_progress|in progress)/i.test(s) ||
      /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|\u0431\u0443\u0434\u0443|planned|plan_to_watch)/i.test(s) ||
      /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i.test(s) ||
      /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i.test(s) ||
      /(?:\u043E\u0442\u043B\u043E\u0436|hold|pause)/i.test(s) ||
      /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i.test(s);
  };

  const statusToCode = (statusId, statusName) => {
    const s = String(statusName || "").toLowerCase();
    if (/(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i.test(s)) return 3;
    if (/(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching)/i.test(s)) return 1;
    if (/(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|planned)/i.test(s)) return 2;
    if (/(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i.test(s)) return 4;
    if (/(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i.test(s)) return 5;
    if (/(?:\u043E\u0442\u043B\u043E\u0436|hold)/i.test(s)) return 6;
    if (typeof statusId === "number") {
      if (statusId >= 1 && statusId <= 6) return statusId;
      return 6;
    }
    return 2;
  };

  const allItems = [];
  const counts = { 1: 0, 5: 0, 3: 0, 2: 0, 4: 0, 6: 0 };
  const statusMap = { 1: "Reading", 2: "Planned", 3: "Dropped", 4: "Completed", 5: "Favorites", 6: "On Hold" };

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

    const item = {
      title: m.rus_name || m.name || m.eng_name || b.name || b.title,
      englishTitle: m.eng_name || m.name || b.eng_name || null,
      type: site.type,
      status: statusText || itemStatus || "Planned",
      status_id: (typeof itemStatus === "number" ? itemStatus : (folderId || null)),
      folder_name: folderName || null,
      folder_id: folderId || null,
      is_custom_folder: isCustomFolder,
      progress: prog.chapter !== undefined ? Number(prog.chapter) : (prog.episodes !== undefined ? Number(prog.episodes) : (b.progress ?? 0)),
      totalEpisodes: site.type === "anime" ? totalChapters : null,
      totalChapters: site.type !== "anime" ? totalChapters : null,
      totalVolumes: volumes,
      rating: userRating !== null ? Number(userRating) : null,
      score: userRating !== null ? Number(userRating) : null,
      author: authorList,
      genres: genresList,
      description: summary,
      sourceUrl: \`https://\${site.name.toLowerCase()}.me/\${m.slug_url || m.slug || b.slug || ""}\`,
      coverUrl: coverUrl,
      source_site: site.name
    };

    allItems.push(item);
    counts[site.id] = (counts[site.id] || 0) + 1;
  };

  const headers = {
    "Accept": "application/json",
    "Site-Id": "1"
  };
  if (token) {
    headers["Authorization"] = token.startsWith("Bearer ") ? token : ("Bearer " + token);
  }

  let siteIdx = 0;
  const totalSites = selectedSites.length;

  for (const site of selectedSites) {
    siteIdx++;
    headers["Site-Id"] = String(site.id);
    let siteTotal = 0;
    console.log(\`%c[\${siteIdx}/\${totalSites}] \${site.name}%c: polling folders...\`, "color:#ff6740;font-weight:bold", "");

    let activeFolders = [];
    try {
      const res = await fetch(\`https://api.lib.social/api/bookmarks/folders?user_id=\${userId}\`, { headers });
      if (res.ok) {
        const json = await res.json();
        const rawFolders = json.data || json || [];
        if (Array.isArray(rawFolders) && rawFolders.length > 0) {
          activeFolders = rawFolders.map(f => ({
            id: f.id,
            name: f.name || f.slug || ("Folder " + f.id),
            count: f.count ?? f.items_count ?? 0
          }));
        }
      }
    } catch (err) {
      console.warn(\`Failed to get folders for \${site.name}:\`, err.message);
    }

    if (activeFolders.length === 0) {
      const isAnime = site.type === "anime";
      if (standardIds.some(id => allowedStandardStatuses.includes(id))) {
        activeFolders = isAnime ? [
          { id: 1, name: "Watching" },
          { id: 2, name: "Planned" },
          { id: 4, name: "Completed" },
          { id: 5, name: "Favorites" },
          { id: 6, name: "On Hold" },
          { id: 3, name: "Dropped" }
        ] : [
          { id: 1, name: "Reading" },
          { id: 2, name: "Planned" },
          { id: 4, name: "Completed" },
          { id: 5, name: "Favorites" },
          { id: 3, name: "Dropped" }
        ];
      }
    }

    // Custom folders ("Waiting", "Deleted", etc.) — scan DOM of bookmark sidebar
    // on the current page and merge with API list by unique id
    if (includeCustomFolders) {
      try {
        const domFolderElements = document.querySelectorAll("a[href*=\"/bookmark/\"], a[href*=\"/bookmarks\"]");
        const discovered = [];
        domFolderElements.forEach(el => {
          const m = el.getAttribute("href")?.match(/folder[=\/](\d+)/i) || el.getAttribute("href")?.match(/\/(\d+)$/);
          const rawName = el.innerText?.trim();
          if (m && rawName) {
            const id = Number(m[1]);
            const folder = { id: id, name: rawName.replace(/\s*\d+$/, "").trim() || ("Folder " + id) };
            if (!activeFolders.some(f => f.id === id) && !discovered.some(f => f.id === id)) {
              discovered.push(folder);
            }
          }
        });
        if (discovered.length > 0) {
          activeFolders = [...activeFolders, ...discovered];
        }
      } catch {}
    }

    console.log(\`📁 [\${site.name}] Folders: \${activeFolders.map(f => \`\${f.name} (\${f.count})\`).join(', ')}\`);

    for (const folder of activeFolders) {
      const isStd = standardIds.includes(folder.id) || isStandardName(folder.name);
      if (isStd) {
        const stdCode = folder.id >= 1 && folder.id <= 6 ? folder.id : statusToCode(folder.id, folder.name);
        if (!allowedStandardStatuses.includes(stdCode)) {
          continue;
        }
      } else {
        if (!includeCustomFolders) {
          continue;
        }
      }

      let page = 1;
      let maxPage = 1;
      let folderCount = 0;
      let totalExpected = null;

      // Pagination: in SocialLib API fields (last_page / total / per_page) are root-level
      while (page <= maxPage && page <= 50) {
        let res;
        try {
          res = await fetch(\`https://api.lib.social/api/bookmarks?user_id=\${userId}&folder_id=\${folder.id}&page=\${page}&per_page=60\`, { headers });
        } catch (fetchErr) {
          console.error(\`Network error for folder "\${folder.name}" (page \${page}):\`, fetchErr);
          break;
        }

        if (res.status === 429) {
          console.warn(\`[\${site.name}] ⚠️ Rate limit (429), pausing 6s...\`);
          await new Promise(r => setTimeout(r, 6000));
          continue;
        }

        if (!res.ok) {
          if (res.status === 401 || res.status === 403) {
            console.warn(\`\${site.name}: access restricted (\${res.status})\`);
          } else if (res.status === 422) {
            const errDetail = await res.text().catch(() => "");
            console.warn(\`\${site.name} (folder "\${folder.name}" id:\${folder.id}): 422 detail:\`, errDetail);
          }
          break;
        }

        const json = await res.json();
        const items = json.data || (Array.isArray(json) ? json : []);
        if (!items || items.length === 0) break;

        const isCustom = !standardIds.includes(folder.id) && !isStandardName(folder.name);
        for (const b of items) {
          processBookmark(b, site, folder.id, folder.name, isCustom);
        }
        folderCount += items.length;
        siteTotal += items.length;

        // Pagination can come at root or inside meta
        const meta = json.meta || {};
        totalExpected = json.total ?? meta.total ?? totalExpected;
        const perPage = json.per_page ?? meta.per_page ?? 60;
        if (json.last_page !== undefined) maxPage = json.last_page;
        else if (meta.last_page !== undefined) maxPage = meta.last_page;
        else if (totalExpected && perPage) maxPage = Math.ceil(totalExpected / perPage);
        else maxPage = items.length === 60 ? page + 1 : page;

        console.log(\`  ↳ Folder "\${folder.name}" (total \${totalExpected ?? "?"}): page \${page}/\${maxPage ?? "?"} ✓ (+\${items.length} titles, collected: \${folderCount})\`);

        page++;
        if (page <= maxPage) {
          await new Promise(r => setTimeout(r, 600));
        }
      }
    }

    console.log(\`✔ \${site.name}: successfully collected \${siteTotal} titles.\`);
  }

  if (allItems.length === 0) {
    console.log("Attempting fallback export from open page DOM...");
    const cards = document.querySelectorAll(".media-card, .bookmark-item, .card, [data-media-id]");
    cards.forEach(card => {
      const titleEl = card.querySelector(".media-card__title, .title, h3, a[href*='/ru/']");
      const title = titleEl ? titleEl.textContent?.trim() : null;
      if (!title) return;
      const href = card.querySelector("a[href]")?.getAttribute("href") || "";
      const cover = card.querySelector("img")?.getAttribute("src") || null;
      let text = card.textContent || "";
      const progMatch = text.match(/(?:\u0433\u043B\u0430\u0432\u0430|\u0441\u0435\u0440\u0438\u044F|\u0442\u043E\u043C|\u0433\u043B\.|\u0441\u0435\u0440\.|chapter|episode|vol\.)\s*(\d+)/i) || text.match(/\b(\d+)\s*\/\s*\d+/);
      const scoreMatch = text.match(/(?:★|☆|\u043E\u0446\u0435\u043D\u043A\u0430|score)?\s*(\d+(?:\.\d+)?)\s*\/\s*10/i);
      allItems.push({
        title: title,
        type: window.location.host.includes("anime") ? "anime" : "manga",
        status: "Planned",
        status_id: 2,
        folder_name: null,
        is_custom_folder: false,
        progress: progMatch ? parseInt(progMatch[1], 10) : 0,
        score: scoreMatch ? parseFloat(scoreMatch[1]) : null,
        sourceUrl: href ? (href.startsWith("http") ? href : window.location.origin + href) : null,
        coverUrl: cover
      });
    });
  }

  if (allItems.length === 0) {
    console.warn("No bookmarks found. Ensure you are signed in and viewing the right profile.");
    return;
  }

  const exportPayload = {
    version: 1,
    exported_at: new Date().toISOString(),
    source: "SocialLib Instant Collector",
    items: allItems
  };

  const jsonStr = JSON.stringify(exportPayload, null, 2);

  try {
    await navigator.clipboard.writeText(jsonStr);
  } catch {
    const ta = document.createElement("textarea");
    ta.value = jsonStr;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
  }

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
  console.log(\`%c🎉 EXPORT SUCCESSFUL: \${allItems.length} titles!\`, "color:#10b981;font-weight:bold;font-size:13px;");
  console.log(\`MangaLib: \${counts[1] || 0}, AnimeLib: \${counts[5] || 0}, RanobeLib: \${counts[3] || 0}, SlashLib: \${counts[2] || 0}, HentaiLib: \${counts[4] || 0}\`);
  console.log("Data copied to clipboard and downloaded as tsundoku-sociallib.json.");
  console.log("👉 Return to Tsundoku and click Paste from clipboard and import!");
  console.log("%c==================================================", "color:#10b981");

  if (directUploaded) {
    alert("🎉 Exported " + allItems.length + " bookmarks and sent to Tsundoku! Check your library.");
  } else {
    alert("✅ Exported " + allItems.length + " bookmarks! Copied to clipboard — return to Tsundoku and click Paste from clipboard and import!");
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
      error = i18n.t.importModal.copyBookmarkletFailed;
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
      error = i18n.t.importModal.copyScriptFailed;
    }
  }

  async function importFromClipboard() {
    if (busy) return;
    error = "";
    try {
      if (!navigator.clipboard?.readText) {
        error = i18n.t.importModal.clipboardUnavailable;
        return;
      }
      const text = await navigator.clipboard.readText();
      if (!text || !text.trim()) {
        error = i18n.t.importModal.clipboardEmpty;
        return;
      }
      let data: any;
      try {
        data = JSON.parse(text);
      } catch {
        error = i18n.t.importModal.clipboardNoJson;
        return;
      }

      let items: any[] = Array.isArray(data)
        ? data
        : data && Array.isArray(data.data)
          ? data.data
          : [];
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
      const clipboardFile = new File([JSON.stringify(items)], "tsundoku-sociallib.json", {
        type: "application/json",
      });
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

<div class="space-y-6">
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
            class="bg-accent hover:bg-accent-hover cursor-pointer rounded-lg px-4 py-2 text-sm font-semibold text-white transition"
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
        <span class="bg-accent size-1.5 rounded-full"></span>
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
          <span class="bg-accent size-1.5 rounded-full"></span>
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
                  class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft min-w-0 flex-1 rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
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
                    class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft min-w-0 flex-1 rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
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
                  class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
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
                  class="bg-field accent-accent rounded border-white/20"
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
              class="text-accent-soft inline-flex items-center gap-1 underline hover:text-white"
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

          <!-- Mode 1: Instant Collector Script + Clipboard 1-Click Import -->
          {#if mangalibMode === "collector"}
            <div class="bg-card/50 space-y-4 rounded-xl border border-white/[0.08] p-4">
              <div class="space-y-1.5">
                <div class="flex items-center gap-2">
                  <span
                    class="inline-flex items-center rounded-md border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] px-2 py-0.5 text-[11px] font-medium text-[var(--color-import-mangalib-text)]"
                  >
                    {i18n.t.importModal.recommended}
                  </span>
                  <h4 class="text-sm font-semibold text-white">
                    {i18n.t.importModal.instantCollectorTitle}
                  </h4>
                </div>
                <p class="mt-2 text-sm leading-relaxed text-slate-300">
                  {i18n.t.importModal.instantCollectorDesc}
                </p>
              </div>

              <!-- Bookmarklet Banner: 1-Click Import without F12 -->
              <div
                class="space-y-3 rounded-xl border border-[var(--color-import-mangalib-border)] bg-gradient-to-r from-[var(--color-import-mangalib-surface)] via-transparent to-transparent p-4"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="flex items-center gap-2">
                    <span
                      class="inline-flex items-center rounded-md border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] px-2 py-0.5 text-[11px] font-medium text-[var(--color-import-mangalib-text)]"
                    >
                      {i18n.t.importModal.oneClickNoF12}
                    </span>
                    <h4 class="text-sm font-bold text-white">
                      {i18n.t.importModal.bookmarkletButton}
                    </h4>
                  </div>
                  <button
                    type="button"
                    class="cursor-pointer text-xs text-[var(--color-import-mangalib-text)] underline hover:text-white"
                    onclick={() => void copyBookmarkletUrl()}
                  >
                    {#if bookmarkletCopied}
                      <span class="font-medium text-emerald-400"
                        >{i18n.t.importModal.linkCopied}</span
                      >
                    {:else}
                      {i18n.t.importModal.copyBookmarkletLink}
                    {/if}
                  </button>
                </div>
                <p class="text-sm leading-relaxed text-slate-300">
                  {i18n.t.importModal.bookmarkletInstruction} (<kbd
                    class="bg-canvas rounded border border-white/10 px-1.5 py-0.5 font-mono text-xs text-slate-300"
                    >Ctrl+Shift+B</kbd
                  >){i18n.t.importModal.bookmarkletInstructionSuffix}
                </p>
                <div class="flex flex-wrap items-center gap-3 pt-1">
                  <a
                    href={bookmarkletUrl}
                    draggable="true"
                    class="inline-flex cursor-grab items-center gap-2 rounded-lg border-2 border-dashed border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-surface)] px-4 py-2.5 text-xs font-bold text-[var(--color-import-mangalib-text)] shadow-md transition select-none hover:scale-[1.01] hover:brightness-110 active:scale-95 active:cursor-grabbing"
                    title={i18n.t.importModal.bookmarkletDragTooltip}
                    onclick={(e) => {
                      e.preventDefault();
                      alert(i18n.t.importModal.bookmarkletDragAlert);
                    }}
                  >
                    <span>{i18n.t.importModal.bookmarkletButtonText}</span>
                  </a>
                  <span class="text-muted text-xs">
                    {i18n.t.importModal.bookmarkletDragHint}
                  </span>
                </div>
              </div>

              <!-- Instructions -->
              <ol
                class="space-y-3 rounded-lg border border-white/5 bg-black/30 p-3.5 text-sm leading-normal text-slate-200"
              >
                <li class="flex items-start gap-2.5">
                  <span
                    class="grid size-6 shrink-0 place-items-center rounded-full bg-[var(--color-import-mangalib-surface)] text-xs font-bold text-[var(--color-import-mangalib-text)]"
                    >1</span
                  >
                  <span>
                    {i18n.t.importModal.step1Text} (<a
                      href="https://mangalib.me"
                      target="_blank"
                      rel="noreferrer"
                      class="font-medium text-[var(--color-import-mangalib-text)] hover:underline"
                      >MangaLib</a
                    >,
                    <a
                      href="https://animelib.org"
                      target="_blank"
                      rel="noreferrer"
                      class="font-medium text-[var(--color-import-mangalib-text)] hover:underline"
                      >AnimeLib</a
                    >,
                    <a
                      href="https://ranobelib.me"
                      target="_blank"
                      rel="noreferrer"
                      class="font-medium text-[var(--color-import-mangalib-text)] hover:underline"
                      >RanobeLib</a
                    >).
                  </span>
                </li>
                <li class="flex items-start gap-2.5">
                  <span
                    class="grid size-6 shrink-0 place-items-center rounded-full bg-[var(--color-import-mangalib-surface)] text-xs font-bold text-[var(--color-import-mangalib-text)]"
                    >2</span
                  >
                  <span>
                    {i18n.t.importModal.step2TextPre}
                    <kbd
                      class="bg-canvas rounded border border-white/10 px-1.5 py-0.5 font-mono text-xs text-slate-300"
                      >F12 → Console</kbd
                    >{i18n.t.importModal.step2TextMid}
                    <kbd
                      class="bg-canvas rounded border border-white/10 px-1.5 py-0.5 font-mono text-xs text-slate-300"
                      >Enter</kbd
                    >{i18n.t.importModal.step2TextPost}
                  </span>
                </li>
                <li class="flex items-start gap-2.5">
                  <span
                    class="grid size-6 shrink-0 place-items-center rounded-full bg-[var(--color-import-mangalib-surface)] text-xs font-bold text-[var(--color-import-mangalib-text)]"
                    >3</span
                  >
                  <span>
                    {i18n.t.importModal.step3TextPre}
                    <strong>{i18n.t.importModal.step3TextBtn}</strong>{i18n.t.importModal
                      .step3TextPost}
                  </span>
                </li>
              </ol>

              <!-- Actions -->
              <div class="grid grid-cols-1 gap-2.5 pt-1 sm:grid-cols-2">
                <button
                  type="button"
                  class="bg-field inline-flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-white/10 px-4 py-2.5 text-sm font-medium text-slate-200 transition hover:border-[var(--color-import-mangalib-border)] hover:bg-[var(--color-import-mangalib-surface)] hover:text-[var(--color-import-mangalib-text)]"
                  onclick={() => void copySocialLibScript()}
                >
                  {#if scriptCopied}
                    <Check size={16} class="text-emerald-400" />
                    <span class="text-emerald-300">{i18n.t.importModal.scriptCopied}</span>
                  {:else}
                    <Copy size={16} />
                    <span>{i18n.t.importModal.copyCollectorScript}</span>
                  {/if}
                </button>

                <button
                  type="button"
                  disabled={busy}
                  class="inline-flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-[var(--color-import-mangalib-border)] bg-[var(--color-import-mangalib-accent)] px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:opacity-90 disabled:cursor-wait disabled:opacity-60"
                  onclick={() => void importFromClipboard()}
                >
                  {#if busy}
                    <LoaderCircle size={16} class="animate-spin" />
                    <span>{i18n.t.importModal.importingStatus}</span>
                  {:else}
                    <Download size={16} />
                    <span>{i18n.t.importModal.pasteAndImport}</span>
                  {/if}
                </button>
              </div>
            </div>

            <!-- Mode 2: File Upload (.json / .csv) -->
          {:else}
            <div
              class={`relative flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
                dragging
                  ? "border-accent bg-accent/10"
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
                ? "border-accent bg-accent/10"
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
            class="bg-field accent-accent rounded border-white/20"
          />
          <span>{i18n.t.importModal.skipDuplicates}</span>
        </label>

        <label class="text-ink flex cursor-pointer items-center gap-2.5 text-sm select-none">
          <input
            type="checkbox"
            bind:checked={addToList}
            class="bg-field accent-accent rounded border-white/20"
          />
          <span>{i18n.t.importModal.addToList}</span>
        </label>
      </div>

      {#if addToList}
        <div class="ml-6 space-y-3 border-l-2 border-white/10 pt-1 pl-4">
          <div class="flex flex-wrap gap-4 text-xs">
            <label class="text-ink flex cursor-pointer items-center gap-2">
              <input type="radio" bind:group={listMode} value="new" class="accent-accent" />
              <span>{i18n.t.importModal.newList}</span>
            </label>
            <label class="text-ink flex cursor-pointer items-center gap-2">
              <input type="radio" bind:group={listMode} value="existing" class="accent-accent" />
              <span>{i18n.t.importModal.existingList}</span>
            </label>
          </div>

          {#if listMode === "new"}
            <div>
              <input
                bind:value={newListName}
                placeholder={defaultListName}
                maxlength="100"
                class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
              />
            </div>
          {:else}
            <div>
              <select
                bind:value={targetListId}
                class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full cursor-pointer rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
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

      {#if provider === "anixart"}
        <div class="space-y-3 rounded-xl border border-purple-500/20 bg-purple-500/5 p-3.5">
          <label class="text-ink flex cursor-pointer items-center gap-2.5 text-sm select-none">
            <input
              type="checkbox"
              bind:checked={anixartCreateFavoritesList}
              class="rounded border-white/20 accent-purple-500"
            />
            <span>{i18n.t.importModal.anixartFavoritesCheckbox}</span>
          </label>

          <div class="space-y-1.5 pt-1">
            <label for="anixart-unwatching-status" class="text-muted block text-xs font-medium">
              {i18n.t.importModal.anixartUnwatchingStatusLabel}
            </label>
            <select
              id="anixart-unwatching-status"
              bind:value={anixartUnwatchingStatus}
              class="bg-field text-ink w-full cursor-pointer rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-purple-500/50"
            >
              {#each anixartUnwatchingStatusOptions as opt}
                <option value={opt.value}>{opt.label}</option>
              {/each}
            </select>
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
              <span class="bg-accent size-1.5 rounded-full"></span>
              {i18n.t.importModal.listsToImport}
            </h3>
            <span class="text-accent-soft text-[11px] font-medium">
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
                    ? "border-accent/40 bg-accent/15 text-accent-soft ring-accent/20 border ring-1"
                    : "border border-white/10 bg-white/[0.02] text-slate-400 hover:border-white/20 hover:text-white"
                }`}
                onclick={() => toggleStatus(opt.id)}
              >
                <span
                  class={`grid h-4 w-4 shrink-0 place-items-center rounded border transition ${
                    checked ? "border-accent bg-accent text-white" : "border-white/30 bg-black/20"
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
        class="bg-accent hover:bg-accent-hover shadow-accent/20 inline-flex cursor-pointer items-center gap-2 rounded-lg px-5 py-2.5 text-sm font-semibold text-white shadow-md transition disabled:cursor-wait disabled:opacity-60"
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
