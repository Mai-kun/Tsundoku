<script lang="ts">
  import {
    AlertCircle,
    AlertTriangle,
    AppWindow,
    Archive,
    ArrowDown,
    BookOpen,
    Check,
    ChevronDown,
    ChevronUp,
    Copy,
    ExternalLink,
    Eye,
    EyeOff,
    FolderInput,
    FolderOpen,
    GripVertical,
    Key,
    LoaderCircle,
    Plus,
    RefreshCw,
    RotateCcw,
    Search,
    Server,
    Settings,
    FileText,
    ShieldCheck,
    Trash2,
    X,
  } from "$shared/ui/Icons";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import { readOnCloseAction, writeOnCloseAction, type CloseBehavior } from "$shared/utils/tauri";
  import {
    createApiToken,
    errorMessage,
    exportBackup,
    exportLibraryCsv,
    exportLibraryJson,
    getApiTokens,
    getCategoryOrder,
    getSources,
    getSourcePriority,
    restoreBackup,
    resetAllData,
    revokeApiToken,
    saveCategoryOrder,
    saveSourceKey,
    saveSourcePriority,
    testSourceConnection,
    toggleSourceEnabled,
    checkAppUpdate,
    applyAppUpdate,
    getStorageSettings,
    saveStorageSettings,
  } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import Select from "$shared/ui/Select.svelte";
  import { flip } from "svelte/animate";
  import ImportPanel from "$features/import-media/ImportPanel.svelte";
  import type {
    ApiTokenSummary,
    ConnectionTestResult,
    CreateApiTokenResponse,
    SourceInfo,
    StorageSettings,
  } from "$shared/types";
  import type { UpdateCheckResult } from "$shared/api/api";

  interface Props {
    isOpen: boolean;
    onClose: () => void;
    onImportCompleted: () => void;
    onNavigateToList?: (id: string) => void;
  }

  let { isOpen, onClose, onImportCompleted, onNavigateToList }: Props = $props();

  type Tab =
    | "sources"
    | "search"
    | "backup"
    | "import"
    | "reading"
    | "apiTokens"
    | "update"
    | "storage"
    | "desktop";
  let activeTab = $state<Tab>("sources");

  /* Read once when the modal mounts; written through on every radio change. */
  let onCloseAction = $state<CloseBehavior>(readOnCloseAction());

  const closeBehaviorOptions = $derived([
    { value: "ask", label: i18n.t.settingsModal.closeBehavior.ask },
    { value: "minimize_to_tray", label: i18n.t.settingsModal.closeBehavior.minimizeToTray },
    { value: "close_gui", label: i18n.t.settingsModal.closeBehavior.closeGui },
    { value: "exit_all", label: i18n.t.settingsModal.closeBehavior.exitAll },
  ] as { value: CloseBehavior; label: string }[]);

  function setCloseBehavior(value: CloseBehavior) {
    onCloseAction = value;
    writeOnCloseAction(value);
  }

  let tokens = $state<ApiTokenSummary[]>([]);
  let isLoadingTokens = $state(false);
  let isCreatingToken = $state(false);
  let isRevokingToken = $state(false);

  let showCreateTokenModal = $state(false);
  let newTokenName = $state("");
  let newTokenExpiresInDays = $state<number | undefined>(undefined);

  let createdTokenResult = $state<CreateApiTokenResponse | null>(null);
  let hasCopiedToken = $state(false);

  let tokenToRevoke = $state<ApiTokenSummary | null>(null);
  let updateCheck = $state<UpdateCheckResult | null>(null);
  let isCheckingUpdate = $state(false);
  let isApplyingUpdate = $state(false);

  $effect(() => {
    if (isOpen && activeTab === "apiTokens") {
      loadTokens();
    }
    if (isOpen && activeTab === "update") {
      handleCheckUpdate();
    }
    if (isOpen && activeTab === "storage") {
      loadStorage();
    }
  });

  async function handleCheckUpdate() {
    isCheckingUpdate = true;
    try {
      updateCheck = await checkAppUpdate();
    } catch (e) {
      showToast(errorMessage(e), "error");
    } finally {
      isCheckingUpdate = false;
    }
  }

  async function handleApplyUpdate() {
    isApplyingUpdate = true;
    try {
      await applyAppUpdate();
      showToast("Обновление применено, сервер перезапускается...", "success");
      const interval = setInterval(async () => {
        try {
          await checkAppUpdate();
          window.location.reload();
          clearInterval(interval);
        } catch {
          /* ignored, still down */
        }
      }, 1500);
    } catch (e) {
      showToast(errorMessage(e), "error");
      isApplyingUpdate = false;
    }
  }

  async function loadTokens() {
    isLoadingTokens = true;
    try {
      tokens = await getApiTokens();
    } catch (e) {
      console.error(e);
      showToast(errorMessage(e), "error");
    } finally {
      isLoadingTokens = false;
    }
  }

  async function handleCreateToken() {
    if (!newTokenName.trim() || isCreatingToken) return;
    isCreatingToken = true;
    try {
      const res = await createApiToken(
        newTokenName.trim(),
        newTokenExpiresInDays && newTokenExpiresInDays > 0 ? newTokenExpiresInDays : undefined,
      );
      createdTokenResult = res;
      hasCopiedToken = false;
      showCreateTokenModal = false;
      newTokenName = "";
      newTokenExpiresInDays = undefined;
      showToast(i18n.t.settingsModal.apiTokens.createdToast, "success");
      await loadTokens();
    } catch (e) {
      console.error(e);
      showToast(errorMessage(e), "error");
    } finally {
      isCreatingToken = false;
    }
  }

  async function handleCopyToken(token: string) {
    try {
      await navigator.clipboard.writeText(token);
      hasCopiedToken = true;
      showToast(i18n.t.settingsModal.apiTokens.copied, "success");
      setTimeout(() => {
        hasCopiedToken = false;
      }, 3000);
    } catch (e) {
      console.error(e);
      showToast("Failed to copy", "error");
    }
  }

  async function handleRevokeToken() {
    if (!tokenToRevoke || isRevokingToken) return;
    isRevokingToken = true;
    try {
      await revokeApiToken(tokenToRevoke.id);
      tokens = tokens.filter((t) => t.id !== tokenToRevoke!.id);
      showToast(i18n.t.settingsModal.apiTokens.revokedToast, "success");
      tokenToRevoke = null;
    } catch (e) {
      console.error(e);
      showToast(errorMessage(e), "error");
    } finally {
      isRevokingToken = false;
    }
  }

  function formatRelativeTime(dateString: string | null | undefined): string {
    if (!dateString) return i18n.t.settingsModal.apiTokens.neverUsed;
    const date = new Date(dateString);
    const diffSec = Math.round((date.getTime() - Date.now()) / 1000);
    const diffMin = Math.round(diffSec / 60);
    const diffHours = Math.round(diffMin / 60);
    const diffDays = Math.round(diffHours / 24);

    try {
      const rtf = new Intl.RelativeTimeFormat(i18n.current, { numeric: "auto" });
      if (Math.abs(diffSec) < 60) {
        return i18n.current === "ru" ? "только что" : "just now";
      }
      if (Math.abs(diffMin) < 60) {
        return rtf.format(diffMin, "minute");
      }
      if (Math.abs(diffHours) < 24) {
        return rtf.format(diffHours, "hour");
      }
      return rtf.format(diffDays, "day");
    } catch {
      return date.toLocaleDateString();
    }
  }

  function formatDate(dateString: string | null | undefined): string {
    if (!dateString) return "";
    return new Date(dateString).toLocaleDateString(i18n.current, {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  }

  let storage = $state<StorageSettings | null>(null);
  let storageMode = $state<"default" | "portable" | "custom">("default");
  let customPathInput = $state("");
  let migrateExistingData = $state(false);
  let isSavingStorage = $state(false);
  let storageError = $state<unknown>(null);

  async function loadStorage() {
    try {
      storage = await getStorageSettings();
      storageMode = storage.mode;
      customPathInput = storage.customPath ?? "";
      migrateExistingData = false;
      storageError = null;
    } catch (e) {
      storageError = e;
      console.error("Failed to load storage settings:", e);
    }
  }

  async function handleSaveStorage() {
    if (isSavingStorage) return;
    isSavingStorage = true;
    try {
      await saveStorageSettings({
        mode: storageMode,
        customPath: customPathInput.trim() || "",
        migrateExistingData,
      });
      showToast(i18n.t.settingsModal.storage.savedToast, "success");
      setTimeout(() => {
        window.location.reload();
      }, 1500);
    } catch (e) {
      showToast(errorMessage(e), "error");
    } finally {
      isSavingStorage = false;
    }
  }

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
      showToast(i18n.t.settingsModal.reading.bookSpeedValidation, "error");
      return;
    }
    if (isNaN(mangaMin) || mangaMin < 0.5 || mangaMin > 30.0) {
      showToast(i18n.t.settingsModal.reading.mangaSpeedValidation, "error");
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
  let exportingTableFormat = $state<"" | "json" | "csv">("");
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

  async function handleExportTable(format: "json" | "csv") {
    if (exportingTableFormat) return;
    exportingTableFormat = format;
    try {
      const blob = format === "json" ? await exportLibraryJson() : await exportLibraryCsv();
      const now = new Date();
      const pad = (n: number) => String(n).padStart(2, "0");
      const timestamp = `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}`;
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `tsundoku-library-${timestamp}.${format}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error(e);
      showToast(errorMessage(e), "error");
    } finally {
      exportingTableFormat = "";
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
    if (
      isResetting ||
      resetConfirmationInput.trim() !== i18n.t.settingsModal.backup.confirmationWord
    )
      return;
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

  let sources = $state.raw<SourceInfo[]>([]);
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

  const defaultCategories = ["anime", "movie", "tvshow", "manga", "game", "book"];

  const defaultPriority: Record<string, string[]> = {
    anime: ["anilist", "shikimori", "kitsu", "simkl"],
    manga: ["anilist", "shikimori", "mangadex", "mangaupdates"],
    movie: ["tmdb", "imdb", "kinopoisk", "simkl"],
    tvshow: ["tmdb", "imdb", "kinopoisk", "simkl"],
    game: ["rawg", "steam"],
    book: ["openlibrary"],
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

  /**
   * Per-source colors from the shared Source Themes token group in tokens.css
   * (the same palette the import provider cards use). Unknown ids fall back to
   * the neutral card chrome.
   */
  const THEMED_SOURCES = new Set([
    "tmdb",
    "imdb",
    "rawg",
    "simkl",
    "kinopoisk",
    "steam",
    "anilist",
    "shikimori",
    "kitsu",
    "mangadex",
    "mangaupdates",
    "openlibrary",
  ]);

  function sourceThemeVars(sourceId: string) {
    if (!THEMED_SOURCES.has(sourceId)) {
      return {
        accent: "var(--color-accent)",
        border: "var(--color-panel-border)",
      };
    }
    return {
      accent: `var(--color-import-${sourceId}-accent)`,
      border: `var(--color-import-${sourceId}-border)`,
    };
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
        showToast(res.message || i18n.t.settingsModal.sources.testFailed, "error");
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

  async function moveSourcePriority(type: string, index: number, direction: "up" | "down") {
    const currentList = [...(sourcePriority[type] || defaultPriority[type] || [])];
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

  /* Live-reorder drag state. The list order mutates on every dragover that
     crosses a new row (animate:flip then slides the neighbours aside), and the
     persisted save happens once on drop/dragend. */
  let draggedIndex = $state<number | null>(null);
  let orderDirty = false;

  /**
   * Midpoint thresholding: a swap fires only when the cursor actually crosses
   * the vertical midpoint of the hovered row in the drag direction. Without it
   * the shifted neighbour slides under the cursor, fires dragover back and the
   * row oscillates on every mouse twitch. Shared by both drag lists.
   */
  function crossesMidpoint(event: DragEvent, targetIndex: number, currentIndex: number): boolean {
    const target = event.currentTarget;
    if (!(target instanceof HTMLElement)) return true;
    const middleY = target.getBoundingClientRect().top + target.getBoundingClientRect().height / 2;
    if (currentIndex < targetIndex) return event.clientY >= middleY; // dragging down
    return event.clientY <= middleY; // dragging up
  }

  function handleDragStart(idx: number, event: DragEvent) {
    draggedIndex = idx;
    orderDirty = false;
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", String(idx));
    }
  }

  function handleDragOver(idx: number, event: DragEvent) {
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = "move";
    }
    if (draggedIndex === null || draggedIndex === idx) return;
    if (!crossesMidpoint(event, idx, draggedIndex)) return;

    const updated = [...categoryOrder];
    const [moved] = updated.splice(draggedIndex, 1);
    updated.splice(idx, 0, moved);

    categoryOrder = updated;
    draggedIndex = idx;
    orderDirty = true;
  }

  async function finishCategoryDrag() {
    const wasDirty = orderDirty;
    draggedIndex = null;
    orderDirty = false;
    if (!wasDirty) return;

    try {
      await saveCategoryOrder(categoryOrder);
      showToast(i18n.t.settingsModal.search.saved, "success");
    } catch (err) {
      console.error(err);
      showToast(errorMessage(err), "error");
    }
  }

  let draggedSource: { type: string; index: number } | null = $state(null);
  let priorityDirty = false;

  function handleSourceDragStart(type: string, index: number, event: DragEvent) {
    draggedSource = { type, index };
    priorityDirty = false;
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", `${type}:${index}`);
    }
  }

  function handleSourceDragOver(type: string, index: number, event: DragEvent) {
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = "move";
    }
    if (!draggedSource || draggedSource.type !== type || draggedSource.index === index) return;
    if (!crossesMidpoint(event, index, draggedSource.index)) return;

    const list = [...(sourcePriority[type] || [])];
    const [moved] = list.splice(draggedSource.index, 1);
    list.splice(index, 0, moved);

    sourcePriority = { ...sourcePriority, [type]: list };
    draggedSource = { type, index };
    priorityDirty = true;
  }

  async function finishSourceDrag() {
    const wasDirty = priorityDirty;
    draggedSource = null;
    priorityDirty = false;
    if (!wasDirty) return;

    try {
      await saveSourcePriority(sourcePriority);
      showToast(i18n.t.settingsModal.search.prioritySaved, "success");
    } catch (err) {
      console.error(err);
      showToast(errorMessage(err), "error");
    }
  }

  function getSourceName(id: string): string {
    const s = sources.find((x) => x.id === id);
    if (s) return s.name;
    if (id === "mangaupdates") return "MangaUpdates";
    if (id === "mangadex") return "MangaDex";
    if (id === "anilist") return "AniList";
    if (id === "tmdb") return "TMDb";
    if (id === "rawg") return "RAWG";
    if (id === "openlibrary") return "OpenLibrary";
    if (id === "shikimori") return "Shikimori";
    if (id === "steam") return "Steam";
    if (id === "imdb") return "IMDb";
    if (id === "simkl") return "Simkl";
    if (id === "kinopoisk") return "Кинопоиск";
    return id;
  }

  function isSourceDisabled(id: string): boolean {
    const norm = id.toLowerCase().trim();
    const s = sources.find((x) => x.id.toLowerCase().trim() === norm);
    return s ? s.isEnabled === false : false;
  }
</script>

<Modal {isOpen} {onClose} size="xl" labelledBy="settings-title">
  <div class="flex h-full min-h-0 flex-col overflow-hidden">
    <!-- Header -->
    <header
      class="flex shrink-0 items-center justify-between border-b border-white/[0.08] px-6 py-4"
    >
      <div class="flex items-center gap-3">
        <div class="grid h-9 w-9 place-items-center rounded-lg bg-[#5844e0]/15 text-[#a5b4fc]">
          <Settings size={20} />
        </div>
        <div>
          <h2 id="settings-title" class="text-lg font-bold tracking-tight text-white">
            {i18n.t.settingsModal.title}
          </h2>
        </div>
      </div>
      <button
        type="button"
        class="text-muted grid h-8 w-8 cursor-pointer place-items-center rounded-lg transition hover:bg-white/10 hover:text-white"
        aria-label={i18n.t.common.close}
        onclick={onClose}
      >
        <X size={18} />
      </button>
    </header>

    <!-- Modal Body: 2 columns -->
    <div class="flex min-h-0 flex-1 overflow-hidden">
      <!-- Left sidebar navigation -->
      <nav
        class="thin-scroll w-56 shrink-0 space-y-1.5 overflow-y-auto border-r border-white/[0.08] bg-[#12151c]/60 p-3 sm:w-64"
        aria-label={i18n.t.settingsModal.title}
      >
        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "sources"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "sources")}
        >
          <Server size={16} />
          <span>{i18n.t.settingsModal.tabs.sources}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "search"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "search")}
        >
          <Search size={16} />
          <span>{i18n.t.settingsModal.tabs.search}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "backup"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "backup")}
        >
          <RotateCcw size={16} />
          <span>{i18n.t.settingsModal.tabs.backup}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "import"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "import")}
        >
          <FolderInput size={16} />
          <span>{i18n.t.settingsModal.tabs.import}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "reading"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "reading")}
        >
          <BookOpen size={16} />
          <span>{i18n.t.settingsModal.tabs.reading}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "update"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "update")}
        >
          <RefreshCw size={16} />
          <span>{i18n.t.settingsModal.tabs.update}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "storage"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "storage")}
        >
          <FolderInput size={16} />
          <span>{i18n.t.settingsModal.tabs.storage}</span>
        </button>

        <button
          type="button"
          class={`tap flex w-full cursor-pointer items-center gap-3 rounded-lg px-3.5 py-2.5 text-left text-xs transition ${
            activeTab === "desktop"
              ? "border border-[#5844e0]/30 bg-[#5844e0]/15 font-semibold text-[#a5b4fc] shadow-sm"
              : "text-muted border border-transparent font-medium hover:bg-white/5 hover:text-white"
          }`}
          onclick={() => (activeTab = "desktop")}
        >
          <AppWindow size={16} />
          <span>{i18n.t.settingsModal.tabs.desktop}</span>
        </button>
      </nav>

      <!-- Right content area -->
      <div class="thin-scroll min-w-0 flex-1 overflow-y-auto bg-[#151a26]/40 p-6">
        {#if activeTab === "sources"}
          <div class="space-y-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 class="text-ink text-sm font-semibold">
                  {i18n.t.settingsModal.sources.title}
                </h3>
                <p class="text-muted mt-0.5 text-xs">
                  {i18n.t.settingsModal.sources.description}
                </p>
              </div>

              <!-- Media Type Filter Dropdown (Item 15) -->
              <div class="flex items-center gap-2">
                <label for="source-type-filter" class="text-muted shrink-0 text-xs"
                  >{i18n.t.settingsModal.sources.filterLabel}:</label
                >
                <Select
                  id="source-type-filter"
                  options={[
                    { value: "all", label: i18n.t.settingsModal.sources.filterAll },
                    { value: "anime", label: i18n.t.navigation.anime },
                    { value: "manga", label: i18n.t.types.manga },
                    { value: "movie", label: i18n.t.types.movie },
                    { value: "tvshow", label: i18n.t.types.tvshow },
                    { value: "game", label: i18n.t.types.game },
                    { value: "book", label: i18n.t.types.book },
                  ]}
                  value={selectedTypeFilter}
                  onChange={(next) => (selectedTypeFilter = next)}
                  class="h-8 rounded-md px-2.5 text-xs"
                />
              </div>
            </div>

            {#if sourcesLoading}
              <div class="space-y-4">
                {#each Array(4) as _, i (i)}
                  <div class="bg-card h-24 animate-pulse rounded-xl"></div>
                {/each}
              </div>
            {:else if sourcesError}
              <p class="rounded-lg bg-rose-400/10 p-3 text-xs text-rose-300">
                {errorMessage(sourcesError)}
              </p>
            {:else}
              <div class="space-y-4">
                {#each filteredSources as source (source.id)}
                  {@const theme = sourceThemeVars(source.id)}
                  <div
                    class="rounded-xl border bg-white/[0.02] p-4 transition hover:border-white/15 sm:p-5 {source.isEnabled ===
                    false
                      ? 'opacity-65'
                      : ''}"
                    style={`border-color: ${theme.border};`}
                  >
                    <div class="flex flex-wrap items-start justify-between gap-3">
                      <div class="min-w-[200px] flex-1">
                        <div class="flex flex-wrap items-center gap-2">
                          <span
                            class="size-2.5 shrink-0 rounded-full"
                            style={`background: ${theme.accent};`}
                            aria-hidden="true"
                          ></span>
                          <h4 class="text-ink text-sm font-bold">
                            {source.name}
                          </h4>
                          {#if !source.isEnabled}
                            <span
                              class="inline-flex items-center rounded bg-zinc-500/15 px-2 py-0.5 text-[11px] font-semibold text-zinc-400"
                            >
                              {i18n.t.settingsModal.sources.disabledBadge}
                            </span>
                          {/if}
                          {#if source.optionalApiKey && !source.requiresApiKey}
                            <span
                              class="inline-flex items-center gap-1 rounded bg-sky-500/15 px-2 py-0.5 text-[11px] font-semibold text-sky-400"
                              title={i18n.t.settingsModal.sources.optionalKeyHint}
                            >
                              <Key size={12} />
                              {i18n.t.settingsModal.sources.optionalKey}
                            </span>
                          {:else if source.requiresApiKey}
                            {#if source.hasKey}
                              <span
                                class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 text-[11px] font-semibold text-emerald-400"
                              >
                                <Check size={12} />
                                {i18n.t.settingsModal.sources.keyConfigured}
                              </span>
                            {:else}
                              <span
                                class="inline-flex items-center gap-1 rounded bg-amber-500/15 px-2 py-0.5 text-[11px] font-semibold text-amber-400"
                              >
                                <Key size={12} />
                                {i18n.t.settingsModal.sources.keyRequired}
                              </span>
                            {/if}
                          {:else}
                            <span
                              class="inline-flex items-center gap-1 rounded bg-sky-500/15 px-2 py-0.5 text-[11px] font-semibold text-sky-400"
                            >
                              <ShieldCheck size={12} />
                              {i18n.t.settingsModal.sources.noKeyRequired}
                            </span>
                          {/if}
                        </div>
                        <p class="text-muted mt-1 text-xs">
                          {source.description}
                        </p>
                        <div class="mt-2 flex flex-wrap gap-1.5">
                          {#each source.mediaTypes as mt}
                            <span
                              class="bg-canvas text-muted rounded px-2 py-0.5 text-[10px] font-medium"
                            >
                              {categoryLabel(mt)}
                            </span>
                          {/each}
                        </div>
                      </div>

                      <div class="flex shrink-0 items-center gap-2.5">
                        <button
                          type="button"
                          class="bg-field text-ink hover:bg-card hover:border-accent-soft inline-flex h-7 cursor-pointer items-center gap-1.5 rounded-md border border-white/10 px-2.5 text-xs font-medium transition disabled:cursor-not-allowed disabled:opacity-60"
                          disabled={testingSource === source.id}
                          title={i18n.t.settingsModal.sources.testConnection}
                          onclick={() => void handleTestSource(source.id)}
                        >
                          <RefreshCw
                            size={12}
                            class={testingSource === source.id
                              ? "text-accent-soft animate-spin"
                              : "text-muted"}
                          />
                          <span
                            >{testingSource === source.id
                              ? i18n.t.settingsModal.sources.testing
                              : i18n.t.settingsModal.sources.testConnection}</span
                          >
                        </button>

                        <button
                          type="button"
                          role="switch"
                          aria-checked={source.isEnabled}
                          class={`focus:ring-accent-soft focus:ring-offset-surface relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border transition-colors duration-200 focus:ring-2 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 ${
                            source.isEnabled
                              ? "border-indigo-400 bg-indigo-600"
                              : "border-white/10 bg-white/10"
                          }`}
                          onclick={() => void handleToggleSource(source)}
                          disabled={togglingSource === source.id}
                          title={source.isEnabled
                            ? i18n.t.settingsModal.sources.disable
                            : i18n.t.settingsModal.sources.enable}
                        >
                          <span
                            aria-hidden="true"
                            class={`pointer-events-none inline-block h-5 w-5 transform rounded-full shadow ring-0 transition duration-200 ease-in-out ${
                              source.isEnabled
                                ? "translate-x-5 bg-white"
                                : "translate-x-0 bg-slate-400"
                            }`}
                          ></span>
                        </button>
                      </div>
                    </div>

                    {#if testResults[source.id]}
                      <div class="mt-2.5 flex items-center gap-1.5 text-xs">
                        {#if testResults[source.id].success}
                          <span
                            class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 font-medium text-emerald-400"
                          >
                            <Check size={12} />
                            {i18n.t.settingsModal.sources.testSuccess(
                              testResults[source.id].latencyMs,
                            )}
                          </span>
                        {:else}
                          <span
                            class="inline-flex items-center gap-1 rounded bg-rose-500/15 px-2 py-0.5 font-medium text-rose-400"
                            title={testResults[source.id].message}
                          >
                            <AlertCircle size={12} />
                            {testResults[source.id].message ||
                              i18n.t.settingsModal.sources.testFailed}
                          </span>
                        {/if}
                      </div>
                    {/if}

                    {#if source.requiresApiKey || source.optionalApiKey}
                      <div class="border-white/[0.07]/60 mt-3 border-t pt-3">
                        {#if source.optionalApiKey && !source.requiresApiKey}
                          <p class="text-muted mb-2 flex items-start gap-1.5 text-xs">
                            <Key size={12} class="mt-0.5 shrink-0 text-sky-400" />
                            {i18n.t.settingsModal.sources.optionalKeyHint}
                          </p>
                        {/if}
                        {#if source.maskedKey}
                          <div class="text-muted mb-2 flex items-center gap-2 text-xs">
                            <span>{i18n.t.settingsModal.sources.currentKey}</span>
                            <code
                              class="bg-canvas text-ink rounded px-2 py-0.5 font-mono text-[11px]"
                              >{source.maskedKey}</code
                            >
                          </div>
                        {/if}

                        <div class="flex flex-wrap items-center gap-2">
                          <div class="relative min-w-[200px] flex-1">
                            <input
                              type={showKeys[source.id] ? "text" : "password"}
                              class="bg-field text-ink placeholder:text-muted focus:border-accent-soft focus:ring-accent-soft h-9 w-full rounded-md border border-white/10 px-3 pr-9 text-xs focus:ring-1 focus:outline-none"
                              placeholder={source.hasKey
                                ? i18n.t.settingsModal.sources.replaceKeyPlaceholder
                                : i18n.t.settingsModal.sources.inputPlaceholder}
                              value={inputKeys[source.id] ?? ""}
                              oninput={(e) =>
                                (inputKeys[source.id] = (
                                  e.currentTarget as HTMLInputElement
                                ).value)}
                            />
                            <button
                              type="button"
                              class="text-muted hover:text-ink absolute top-1/2 right-2 -translate-y-1/2 cursor-pointer"
                              aria-label="Toggle key visibility"
                              onclick={() => (showKeys[source.id] = !showKeys[source.id])}
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
                            class="bg-field text-ink hover:bg-card hover:border-accent-soft inline-flex h-9 cursor-pointer items-center gap-1.5 rounded-md border border-white/10 px-3 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-60"
                            class:cursor-wait={savingKey === source.id}
                            disabled={savingKey === source.id || !inputKeys[source.id]?.trim()}
                            onclick={() => void handleSaveKey(source.id)}
                          >
                            <ShieldCheck size={14} />
                            {savingKey === source.id
                              ? i18n.t.common.saving
                              : i18n.t.settingsModal.sources.saveKey}
                          </button>
                        </div>

                        {#if keySuccess[source.id]}
                          <p class="mt-2 text-xs font-medium text-emerald-400">
                            {keySuccess[source.id]}
                          </p>
                        {/if}
                        {#if keyErrors[source.id]}
                          <p class="mt-2 text-xs text-rose-300">
                            {errorMessage(keyErrors[source.id])}
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
                <h3 class="text-ink text-sm font-semibold">
                  {i18n.t.settingsModal.search.orderTitle}
                </h3>
                <p class="text-muted mt-0.5 text-xs">
                  {i18n.t.settingsModal.search.orderHint}
                </p>
              </div>

              {#if orderLoading}
                <div class="bg-card h-32 animate-pulse rounded-lg"></div>
              {:else}
                <div class="space-y-2" role="list">
                  {#each categoryOrder as cat, idx (cat)}
                    <div
                      role="listitem"
                      animate:flip={{ duration: 180 }}
                      class="group flex cursor-grab items-center justify-between rounded-lg border p-3 transition-colors {draggedIndex ===
                      idx
                        ? 'pointer-events-none border-indigo-500/60 bg-indigo-500/[0.06] opacity-40'
                        : 'border-white/10 bg-white/[0.02] hover:border-white/20'}"
                      draggable="true"
                      ondragstart={(e) => handleDragStart(idx, e)}
                      ondragover={(e) => handleDragOver(idx, e)}
                      ondrop={(e) => {
                        e.preventDefault();
                        void finishCategoryDrag();
                      }}
                      ondragend={() => void finishCategoryDrag()}
                    >
                      <!-- Left: position number + category name -->
                      <div class="flex min-w-36 items-center gap-3">
                        <span
                          class="flex h-6 w-6 items-center justify-center rounded bg-white/5 text-xs font-semibold text-slate-400 tabular-nums"
                        >
                          {idx + 1}
                        </span>
                        <span class="text-ink text-sm font-semibold">{categoryLabel(cat)}</span>
                      </div>

                      <!-- Center: drag handle in the middle of the row -->
                      <div class="flex flex-1 items-center justify-center">
                        <div
                          class="rounded-md p-1.5 text-slate-500 transition group-hover:text-slate-300 hover:bg-white/5 active:cursor-grabbing"
                          title={i18n.t.settingsModal.search.dragHint}
                        >
                          <GripVertical size={18} class="rotate-90 sm:rotate-0" />
                        </div>
                      </div>

                      <!-- Right: accessible fallback buttons -->
                      <div class="flex items-center gap-1">
                        <button
                          type="button"
                          class="text-muted hover:bg-elevated hover:text-ink grid h-7 w-7 cursor-pointer place-items-center rounded-md transition disabled:cursor-not-allowed disabled:opacity-30"
                          disabled={idx === 0 || orderSaving}
                          aria-label={i18n.t.settingsModal.search.moveUp}
                          onclick={() => void moveCategory(idx, "up")}
                        >
                          <ChevronUp size={16} />
                        </button>
                        <button
                          type="button"
                          class="text-muted hover:bg-elevated hover:text-ink grid h-7 w-7 cursor-pointer place-items-center rounded-md transition disabled:cursor-not-allowed disabled:opacity-30"
                          disabled={idx === categoryOrder.length - 1 || orderSaving}
                          aria-label={i18n.t.settingsModal.search.moveDown}
                          onclick={() => void moveCategory(idx, "down")}
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
            <div class="space-y-4 border-t border-white/[0.07] pt-6">
              <div>
                <h3 class="text-ink text-sm font-semibold">
                  {i18n.t.settingsModal.search.sourcePriorityTitle}
                </h3>
                <p class="text-muted mt-0.5 text-xs">
                  {i18n.t.settingsModal.search.sourcePriorityHint}
                </p>
              </div>

              {#if priorityLoading}
                <div class="bg-card h-28 animate-pulse rounded-lg"></div>
              {:else}
                <div class="space-y-4">
                  {#each Object.entries(sourcePriority) as [mediaType, providers] (mediaType)}
                    {#if providers && providers.length > 1}
                      <div class="bg-field/60 space-y-2 rounded-lg border border-white/10 p-3.5">
                        <div class="flex items-center justify-between">
                          <h4 class="text-accent-soft text-xs font-bold tracking-wider uppercase">
                            {categoryLabel(mediaType)}
                          </h4>
                          <span class="text-muted text-[11px]"
                            >{i18n.t.settingsModal.sources.providersCount(providers.length)}</span
                          >
                        </div>
                        <div class="space-y-1.5" role="list">
                          {#each providers as provId, pIdx (provId)}
                            <div
                              role="listitem"
                              animate:flip={{ duration: 180 }}
                              draggable="true"
                              ondragstart={(e) => handleSourceDragStart(mediaType, pIdx, e)}
                              ondragover={(e) => handleSourceDragOver(mediaType, pIdx, e)}
                              ondrop={(e) => {
                                e.preventDefault();
                                void finishSourceDrag();
                              }}
                              ondragend={() => void finishSourceDrag()}
                              class="border-border/70 bg-surface flex cursor-grab items-center justify-between rounded-md border px-3 py-2 {draggedSource?.type ===
                                mediaType && draggedSource.index === pIdx
                                ? 'pointer-events-none border-indigo-500/60 bg-indigo-500/10 opacity-40'
                                : draggedSource?.type === mediaType
                                  ? 'border-indigo-500/25'
                                  : ''} {isSourceDisabled(provId)
                                ? 'bg-surface/50 opacity-60'
                                : ''}"
                            >
                              <div class="flex items-center gap-2.5">
                                <GripVertical
                                  size={14}
                                  class="text-muted/60 shrink-0 cursor-grab"
                                  aria-hidden="true"
                                />
                                <span
                                  class="bg-canvas text-muted grid h-5 w-5 place-items-center rounded text-[11px] font-bold"
                                >
                                  {pIdx + 1}
                                </span>
                                <span class="text-ink text-xs font-medium"
                                  >{getSourceName(provId)}</span
                                >
                                {#if isSourceDisabled(provId)}
                                  <span
                                    class="rounded bg-zinc-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-zinc-400"
                                  >
                                    {i18n.t.settingsModal.sources.disabledBadge}
                                  </span>
                                {/if}
                                {#if pIdx === 0}
                                  <span
                                    class="rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-400"
                                    >{i18n.t.settingsModal.search.primary}</span
                                  >
                                {:else}
                                  <span
                                    class="bg-canvas text-muted rounded px-1.5 py-0.5 text-[10px]"
                                    >{i18n.t.settingsModal.search.fallback(pIdx + 1)}</span
                                  >
                                {/if}
                              </div>
                              <div class="flex items-center gap-1">
                                <button
                                  type="button"
                                  class="text-muted hover:bg-elevated hover:text-ink grid h-6 w-6 cursor-pointer place-items-center rounded transition disabled:cursor-not-allowed disabled:opacity-30"
                                  disabled={pIdx === 0 || prioritySaving}
                                  aria-label={i18n.t.settingsModal.search.moveUp}
                                  onclick={() => void moveSourcePriority(mediaType, pIdx, "up")}
                                >
                                  <ChevronUp size={14} />
                                </button>
                                <button
                                  type="button"
                                  class="text-muted hover:bg-elevated hover:text-ink grid h-6 w-6 cursor-pointer place-items-center rounded transition disabled:cursor-not-allowed disabled:opacity-30"
                                  disabled={pIdx === providers.length - 1 || prioritySaving}
                                  aria-label={i18n.t.settingsModal.search.moveDown}
                                  onclick={() => void moveSourcePriority(mediaType, pIdx, "down")}
                                >
                                  <ChevronDown size={14} />
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
            <!-- Export Section (Neutral / Safe) -->
            <div class="rounded-xl border border-white/10 bg-white/[0.02] p-5">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div class="max-w-xl">
                  <h3 class="text-ink text-sm font-semibold">
                    {i18n.t.settingsModal.backup.exportTitle}
                  </h3>
                  <p class="text-muted mt-1 text-xs leading-relaxed">
                    {i18n.t.settingsModal.backup.exportDescription}
                  </p>
                </div>
                <div class="shrink-0">
                  <button
                    type="button"
                    class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-60"
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

            <!-- Data Table Export (Neutral / Safe) -->
            <div class="rounded-xl border border-white/10 bg-white/[0.02] p-5">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div class="max-w-xl">
                  <h3 class="text-ink text-sm font-semibold">
                    {i18n.t.settingsModal.backup.exportDataTitle}
                  </h3>
                  <p class="text-muted mt-1 text-xs leading-relaxed">
                    {i18n.t.settingsModal.backup.exportDataDescription}
                  </p>
                </div>
                <div class="flex shrink-0 gap-2">
                  <button
                    type="button"
                    class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-indigo-500/40 bg-indigo-500/10 px-4 py-2 text-xs font-semibold text-indigo-300 transition hover:bg-indigo-500/20 disabled:cursor-not-allowed disabled:opacity-60"
                    disabled={Boolean(exportingTableFormat)}
                    onclick={() => handleExportTable("json")}
                  >
                    {#if exportingTableFormat === "json"}
                      <LoaderCircle size={14} class="animate-spin" />
                      {i18n.t.settingsModal.backup.exportingTable}
                    {:else}
                      <FileText size={14} />
                      {i18n.t.settingsModal.backup.exportJsonButton}
                    {/if}
                  </button>
                  <button
                    type="button"
                    class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-4 py-2 text-xs font-semibold text-emerald-300 transition hover:bg-emerald-500/20 disabled:cursor-not-allowed disabled:opacity-60"
                    disabled={Boolean(exportingTableFormat)}
                    onclick={() => handleExportTable("csv")}
                  >
                    {#if exportingTableFormat === "csv"}
                      <LoaderCircle size={14} class="animate-spin" />
                      {i18n.t.settingsModal.backup.exportingTable}
                    {:else}
                      <ArrowDown size={14} />
                      {i18n.t.settingsModal.backup.exportCsvButton}
                    {/if}
                  </button>
                </div>
              </div>
            </div>

            <!-- Restore Section (Warning Zone - Amber) -->
            <div class="rounded-xl border border-amber-500/25 bg-amber-500/5 p-5">
              <div
                class="flex items-center gap-2 text-xs font-bold tracking-wider text-amber-400 uppercase"
              >
                <AlertTriangle size={16} />
                <h3>
                  {i18n.t.settingsModal.backup.dangerZone}: {i18n.t.settingsModal.backup
                    .restoreTitle}
                </h3>
              </div>
              <p class="mt-1 text-xs text-slate-400">
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
                  class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-4 py-2 text-xs font-semibold text-amber-300 transition hover:bg-amber-500/20 disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={isRestoring}
                  onclick={() => fileInputRef?.click()}
                >
                  <RotateCcw size={14} />
                  {i18n.t.settingsModal.backup.selectFileButton}
                </button>
              </div>
            </div>

            <!-- Reset Section (Danger Zone - Rose) -->
            <div class="rounded-xl border border-rose-500/25 bg-rose-500/5 p-5">
              <div
                class="flex items-center gap-2 text-xs font-bold tracking-wider text-rose-400 uppercase"
              >
                <AlertCircle size={16} />
                <h3>
                  {i18n.t.settingsModal.backup.dangerZone}: {i18n.t.settingsModal.backup.resetTitle}
                </h3>
              </div>
              <p class="mt-1 text-xs text-slate-400">
                {i18n.t.settingsModal.backup.resetDescription}
              </p>
              <button
                type="button"
                class="mt-4 inline-flex cursor-pointer items-center gap-2 rounded-lg bg-rose-600 px-4 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-rose-500 disabled:cursor-not-allowed disabled:opacity-60"
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
              <h3 class="text-ink text-sm font-semibold">
                {i18n.t.settingsModal.reading.title}
              </h3>
              <p class="text-muted mt-1 text-xs">
                {i18n.t.settingsModal.reading.description}
              </p>
            </div>

            <div class="max-w-md space-y-5">
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
                  class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
                  bind:value={readingBookPageMinutes}
                />
                <p class="text-muted text-[11px]">
                  По умолчанию: 1.5 мин/стр. Диапазон: 0.2 – 10.0
                </p>
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
                  class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
                  bind:value={readingMangaChapterMinutes}
                />
                <p class="text-muted text-[11px]">По умолчанию: 6.0 мин/гл. Диапазон: 0.5 – 30.0</p>
              </div>

              <div class="pt-2">
                <button
                  type="button"
                  disabled={isSavingReading}
                  class="bg-accent hover:bg-accent-hover inline-flex cursor-pointer items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-50"
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
        {:else if activeTab === "update"}
          <section class="space-y-6">
            <h3 class="text-ink text-base font-bold">Обновление</h3>
            {#if isCheckingUpdate}
              <div class="text-muted flex items-center gap-2 text-sm">
                <LoaderCircle class="animate-spin" size={16} /> Проверка...
              </div>
            {:else if updateCheck}
              <div class="space-y-2">
                <p class="text-sm">Версия: {updateCheck.currentVersion}</p>
                {#if updateCheck.isUpdateAvailable && updateCheck.canSelfUpdate}
                  <p class="font-bold text-emerald-400">
                    Доступна версия {updateCheck.latestVersion}
                  </p>
                  <button
                    type="button"
                    onclick={handleApplyUpdate}
                    disabled={isApplyingUpdate}
                    class="bg-accent rounded px-4 py-2 text-xs font-semibold text-white"
                    >Обновить и перезапустить</button
                  >
                  {#if updateCheck.releaseNotes}
                    <div
                      class="text-muted mt-4 rounded bg-black/20 p-4 text-xs whitespace-pre-wrap"
                    >
                      {updateCheck.releaseNotes}
                    </div>
                  {/if}
                {:else if updateCheck.isUpdateAvailable}
                  <p class="text-xs text-rose-400">
                    Обновление доступно, но автообновление недоступно.
                  </p>
                {:else}
                  <p class="text-muted text-sm">Установлена актуальная версия.</p>
                {/if}
              </div>
            {/if}
          </section>
        {:else if activeTab === "storage"}
          <section class="space-y-6">
            <div>
              <h3 class="text-ink text-base font-bold">
                {i18n.t.settingsModal.storage.title}
              </h3>
              <p class="text-muted mt-1 text-xs leading-relaxed">
                {i18n.t.settingsModal.storage.description}
              </p>
            </div>

            {#if storageError}
              <p class="rounded-lg bg-rose-400/10 p-3 text-xs text-rose-300">
                {errorMessage(storageError)}
              </p>
            {:else if storage}
              <div class="bg-card space-y-5 rounded-xl border border-white/[0.08] p-5">
                <div class="space-y-2">
                  <span class="block text-xs font-semibold text-slate-300">
                    {i18n.t.settingsModal.storage.title}
                  </span>
                  <div class="grid gap-2.5 sm:grid-cols-3">
                    <label
                      class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
                        storageMode === "default"
                          ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                          : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
                      }`}
                    >
                      <input
                        type="radio"
                        bind:group={storageMode}
                        value="default"
                        class="sr-only"
                      />
                      <Server
                        size={18}
                        class="shrink-0 {storageMode === 'default'
                          ? 'text-indigo-400'
                          : 'text-slate-400'}"
                      />
                      <span class="text-xs leading-snug font-semibold">
                        {i18n.t.settingsModal.storage.modeDefault}
                      </span>
                    </label>
                    <label
                      class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
                        storageMode === "portable"
                          ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                          : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
                      }`}
                    >
                      <input
                        type="radio"
                        bind:group={storageMode}
                        value="portable"
                        class="sr-only"
                      />
                      <Archive
                        size={18}
                        class="shrink-0 {storageMode === 'portable'
                          ? 'text-indigo-400'
                          : 'text-slate-400'}"
                      />
                      <span class="text-xs leading-snug font-semibold">
                        {i18n.t.settingsModal.storage.modePortable}
                      </span>
                    </label>
                    <label
                      class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
                        storageMode === "custom"
                          ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                          : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
                      }`}
                    >
                      <input type="radio" bind:group={storageMode} value="custom" class="sr-only" />
                      <FolderOpen
                        size={18}
                        class="shrink-0 {storageMode === 'custom'
                          ? 'text-indigo-400'
                          : 'text-slate-400'}"
                      />
                      <span class="text-xs leading-snug font-semibold">
                        {i18n.t.settingsModal.storage.modeCustom}
                      </span>
                    </label>
                  </div>
                </div>

                {#if storageMode === "custom"}
                  <div class="space-y-1.5" transition:slide={{ duration: 150 }}>
                    <label
                      for="custom-path-input"
                      class="block text-xs font-semibold text-slate-300"
                    >
                      {i18n.t.settingsModal.storage.customPathLabel}
                    </label>
                    <input
                      id="custom-path-input"
                      type="text"
                      bind:value={customPathInput}
                      placeholder={i18n.t.settingsModal.storage.customPathPlaceholder}
                      class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft h-10 w-full rounded-lg border border-white/10 px-3 text-xs transition outline-none focus:ring-1"
                    />
                  </div>
                {/if}

                <label
                  class="flex cursor-pointer items-center gap-2 text-sm text-slate-200 hover:text-white"
                >
                  <input
                    type="checkbox"
                    bind:checked={migrateExistingData}
                    class="accent-accent-soft shrink-0"
                  />
                  {i18n.t.settingsModal.storage.migrateLabel}
                </label>

                <div class="space-y-2 border-t border-white/5 pt-2">
                  <div
                    class="flex items-center justify-between gap-3 rounded-lg border border-white/5 bg-black/20 p-2.5 text-xs"
                  >
                    <span class="shrink-0 font-medium text-slate-400">
                      {i18n.t.settingsModal.storage.dbPathLabel}
                    </span>
                    <span
                      class="truncate font-mono text-[11px] text-slate-200 select-all"
                      title={storage.defaultDirectory}
                    >
                      {storage.defaultDirectory}
                    </span>
                  </div>
                  <div
                    class="flex items-center justify-between gap-3 rounded-lg border border-white/5 bg-black/20 p-2.5 text-xs"
                  >
                    <span class="shrink-0 font-medium text-slate-400">
                      {i18n.t.settingsModal.storage.coversPathLabel}
                    </span>
                    <span
                      class="truncate font-mono text-[11px] text-slate-200 select-all"
                      title={storage.portableDirectory}
                    >
                      {storage.portableDirectory}
                    </span>
                  </div>
                  <div
                    class="flex items-center justify-between gap-3 rounded-lg border border-white/5 bg-black/20 p-2.5 text-xs"
                  >
                    <span class="shrink-0 font-medium text-slate-400">
                      {i18n.t.settingsModal.storage.logsPathLabel}
                    </span>
                    <span
                      class="truncate font-mono text-[11px] text-slate-200 select-all"
                      title={storage.defaultDirectory}
                    >
                      {storage.defaultDirectory}
                    </span>
                  </div>
                </div>

                <button
                  type="button"
                  disabled={isSavingStorage}
                  class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
                  onclick={handleSaveStorage}
                >
                  {#if isSavingStorage}
                    <LoaderCircle size={15} class="animate-spin" />
                  {/if}
                  {i18n.t.settingsModal.storage.saveButton}
                </button>
              </div>
            {/if}
          </section>
        {:else if activeTab === "desktop"}
          <section class="space-y-6">
            <div>
              <h3 class="text-ink text-base font-bold">
                {i18n.t.settingsModal.closeBehavior.title}
              </h3>
              <p class="text-muted mt-1 text-xs leading-relaxed">
                {i18n.t.settingsModal.closeBehavior.description}
              </p>
            </div>

            <div class="bg-card grid gap-2.5 rounded-xl border border-white/[0.08] p-5">
              {#each closeBehaviorOptions as option (option.value)}
                <label
                  class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
                    onCloseAction === option.value
                      ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                      : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
                  }`}
                >
                  <input
                    type="radio"
                    name="on-close-action"
                    value={option.value}
                    checked={onCloseAction === option.value}
                    onchange={() => setCloseBehavior(option.value)}
                    class="sr-only"
                  />
                  <span
                    class={`h-4 w-4 shrink-0 rounded-full border transition ${
                      onCloseAction === option.value
                        ? "border-4 border-indigo-400"
                        : "border-white/25"
                    }`}
                  ></span>
                  <span class="text-xs leading-snug font-semibold">{option.label}</span>
                </label>
              {/each}
            </div>
          </section>
        {:else if activeTab === "apiTokens"}
          <section class="space-y-6">
            <!-- Header -->
            <div
              class="flex flex-col gap-4 border-b border-white/[0.08] pb-5 sm:flex-row sm:items-center sm:justify-between"
            >
              <div>
                <h3 class="text-ink text-base font-bold">
                  {i18n.t.settingsModal.apiTokens.title}
                </h3>
                <p class="text-muted mt-1 max-w-xl text-xs leading-relaxed">
                  {i18n.t.settingsModal.apiTokens.description}
                </p>
              </div>
              <div class="flex shrink-0 items-center gap-2.5">
                <a
                  href="/api/docs"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-3.5 text-xs font-semibold text-slate-200 transition hover:bg-white/10"
                >
                  <span>{i18n.t.settingsModal.apiTokens.docsButton}</span>
                  <ExternalLink size={13} />
                </a>
                {#if tokens.length > 0}
                  <button
                    type="button"
                    class="bg-accent hover:bg-accent-hover shadow-accent/20 inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg px-3.5 text-xs font-semibold text-white shadow-md transition"
                    onclick={() => {
                      newTokenName = "";
                      newTokenExpiresInDays = undefined;
                      showCreateTokenModal = true;
                    }}
                  >
                    <Plus size={14} />
                    <span>{i18n.t.settingsModal.apiTokens.createButton}</span>
                  </button>
                {/if}
              </div>
            </div>

            <!-- Token list or empty state -->
            {#if isLoadingTokens}
              <div class="flex flex-col items-center justify-center p-12 text-center">
                <LoaderCircle size={28} class="mb-3 animate-spin text-[#a5b4fc]" />
                <p class="text-muted text-xs">Загрузка...</p>
              </div>
            {:else if tokens.length === 0}
              <div
                class="flex flex-col items-center justify-center rounded-2xl border border-dashed border-white/[0.1] bg-white/[0.02] p-12 text-center"
              >
                <div
                  class="mb-3 grid h-12 w-12 place-items-center rounded-2xl bg-[#5844e0]/10 text-[#a5b4fc]"
                >
                  <Key size={22} />
                </div>
                <p class="text-sm font-medium text-slate-300">
                  {i18n.t.settingsModal.apiTokens.emptyState}
                </p>
                <p class="text-muted mt-1 max-w-sm text-xs">
                  {i18n.t.settingsModal.apiTokens.description}
                </p>
                <button
                  type="button"
                  class="bg-accent hover:bg-accent-hover shadow-accent/20 mt-4 inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg px-3.5 text-xs font-semibold text-white shadow-md transition"
                  onclick={() => {
                    newTokenName = "";
                    newTokenExpiresInDays = undefined;
                    showCreateTokenModal = true;
                  }}
                >
                  <Plus size={14} />
                  <span>{i18n.t.settingsModal.apiTokens.createButton}</span>
                </button>
              </div>
            {:else}
              <div class="space-y-3">
                {#each tokens as token (token.id)}
                  <div
                    class="bg-field flex items-center justify-between rounded-xl border border-white/[0.08] p-4 shadow-sm transition hover:border-white/[0.15]"
                  >
                    <div class="min-w-0 space-y-1.5 pr-4">
                      <div class="flex flex-wrap items-center gap-2.5">
                        <span class="text-ink truncate text-sm font-bold">{token.name}</span>
                        <code
                          class="rounded border border-white/[0.06] bg-black/40 px-2 py-0.5 font-mono text-[11px] text-indigo-300"
                        >
                          {token.tokenPrefix}••••••••
                        </code>
                      </div>
                      <div class="text-muted flex flex-wrap items-center gap-4 text-[11px]">
                        <span>
                          {i18n.t.settingsModal.apiTokens.created}: {formatDate(token.createdAt)}
                        </span>
                        <span>•</span>
                        <span>
                          {i18n.t.settingsModal.apiTokens.lastUsed}:
                          <strong class="font-normal text-slate-300"
                            >{formatRelativeTime(token.lastUsedAt)}</strong
                          >
                        </span>
                        {#if token.expiresAt}
                          <span>•</span>
                          <span class="text-amber-400/90">
                            {i18n.t.settingsModal.apiTokens.expiresAt}: {formatDate(
                              token.expiresAt,
                            )}
                          </span>
                        {/if}
                      </div>
                    </div>
                    <button
                      type="button"
                      class="tap shrink-0 cursor-pointer rounded-lg p-2 text-rose-400 transition hover:bg-rose-500/10 hover:text-rose-300"
                      title={i18n.t.settingsModal.apiTokens.revokeButton}
                      onclick={() => (tokenToRevoke = token)}
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                {/each}
              </div>
            {/if}
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
      <div
        class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-rose-500/15 text-rose-400"
      >
        <AlertTriangle size={20} />
      </div>
      <div class="min-w-0 flex-1">
        <h3 id="reset-confirm-title" class="text-ink text-base font-bold">
          {i18n.t.settingsModal.backup.resetConfirmTitle}
        </h3>
        <p class="text-muted mt-2 text-xs leading-relaxed">
          {i18n.t.settingsModal.backup.resetWarning}
        </p>
        <label class="text-ink mt-4 flex items-center gap-2 text-xs">
          <input
            type="checkbox"
            bind:checked={keepApiKeys}
            disabled={isResetting}
            class="accent-rose-500"
          />
          {i18n.t.settingsModal.backup.keepApiKeys}
        </label>
        <label for="reset-confirmation-input" class="text-muted mt-4 block text-xs">
          {i18n.t.settingsModal.backup.typeToConfirm}
          <span class="ml-1 font-mono font-semibold text-rose-300"
            >{i18n.t.settingsModal.backup.confirmationWord}</span
          >
        </label>
        <input
          id="reset-confirmation-input"
          type="text"
          bind:value={resetConfirmationInput}
          disabled={isResetting}
          autocomplete="off"
          spellcheck="false"
          class="bg-field text-ink mt-2 h-9 w-full rounded-md border border-white/10 px-3 text-sm outline-none focus:border-rose-500/60"
        />
      </div>
    </div>
    <div class="mt-6 flex items-center justify-end gap-3 border-t border-white/[0.07] pt-4">
      <button
        type="button"
        class="bg-field text-ink hover:bg-card inline-flex h-9 cursor-pointer items-center rounded-md border border-white/10 px-4 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-60"
        disabled={isResetting}
        onclick={handleCancelReset}
      >
        {i18n.t.settingsModal.backup.cancelButton}
      </button>
      <button
        type="button"
        class="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md bg-rose-700 px-4 text-xs font-semibold text-white transition hover:bg-rose-600 disabled:cursor-not-allowed disabled:opacity-60"
        class:cursor-wait={isResetting}
        disabled={isResetting ||
          resetConfirmationInput.trim() !== i18n.t.settingsModal.backup.confirmationWord}
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
      <div
        class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-rose-500/15 text-rose-400"
      >
        <AlertTriangle size={20} />
      </div>
      <div>
        <h3 id="restore-confirm-title" class="text-ink text-base font-bold">
          {i18n.t.settingsModal.backup.confirmModalTitle}
        </h3>
        <p class="text-muted mt-2 text-xs leading-relaxed">
          {i18n.t.settingsModal.backup.confirmModalWarning}
        </p>
        {#if selectedBackupFile}
          <div
            class="bg-field text-ink mt-3 rounded-md border border-white/10 px-3 py-2 font-mono text-xs"
          >
            <span class="text-muted mr-1 font-sans"
              >{i18n.t.settingsModal.backup.selectedFileLabel}</span
            >
            {selectedBackupFile.name} ({(selectedBackupFile.size / (1024 * 1024)).toFixed(2)} MB)
          </div>
        {/if}
      </div>
    </div>

    <div class="mt-6 flex items-center justify-end gap-3 border-t border-white/[0.07] pt-4">
      <button
        type="button"
        class="bg-field text-ink hover:bg-card inline-flex h-9 cursor-pointer items-center rounded-md border border-white/10 px-4 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-60"
        disabled={isRestoring}
        onclick={handleCancelRestore}
      >
        {i18n.t.settingsModal.backup.cancelButton}
      </button>
      <button
        type="button"
        class="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md bg-rose-600 px-4 text-xs font-semibold text-white transition hover:bg-rose-500 disabled:cursor-not-allowed disabled:opacity-60"
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

<!-- Create API Token Modal -->
<Modal
  isOpen={showCreateTokenModal}
  onClose={() => (showCreateTokenModal = false)}
  labelledBy="create-token-title"
>
  <div class="p-6">
    <div class="mb-5 flex items-start gap-4">
      <div
        class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#5844e0]/15 text-[#a5b4fc]"
      >
        <Key size={20} />
      </div>
      <div>
        <h3 id="create-token-title" class="text-ink text-base font-bold">
          {i18n.t.settingsModal.apiTokens.modalTitle}
        </h3>
        <p class="text-muted mt-1 text-xs leading-relaxed">
          {i18n.t.settingsModal.apiTokens.description}
        </p>
      </div>
    </div>

    <form
      onsubmit={(e) => {
        e.preventDefault();
        handleCreateToken();
      }}
      class="space-y-4"
    >
      <div class="space-y-1.5">
        <label for="token-name-input" class="block text-xs font-semibold text-slate-300">
          {i18n.t.settingsModal.apiTokens.nameLabel} <span class="text-rose-400">*</span>
        </label>
        <input
          id="token-name-input"
          type="text"
          required
          maxlength="100"
          placeholder={i18n.t.settingsModal.apiTokens.namePlaceholder}
          class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
          bind:value={newTokenName}
        />
      </div>

      <div class="space-y-1.5">
        <label for="token-expires-input" class="block text-xs font-semibold text-slate-300">
          {i18n.t.settingsModal.apiTokens.expiresInDaysLabel}
        </label>
        <input
          id="token-expires-input"
          type="number"
          min="1"
          max="3650"
          placeholder={i18n.t.settingsModal.apiTokens.expiresInDaysPlaceholder}
          class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:ring-1"
          bind:value={newTokenExpiresInDays}
        />
      </div>

      <div class="mt-6 flex items-center justify-end gap-3 border-t border-white/[0.07] pt-4">
        <button
          type="button"
          class="bg-field text-ink hover:bg-card inline-flex h-9 cursor-pointer items-center rounded-md border border-white/10 px-4 text-xs font-semibold transition"
          disabled={isCreatingToken}
          onclick={() => (showCreateTokenModal = false)}
        >
          {i18n.t.settingsModal.apiTokens.cancel}
        </button>
        <button
          type="submit"
          class="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md bg-[#5844e0] px-4 text-xs font-semibold text-white transition hover:bg-[#6854f0] disabled:cursor-not-allowed disabled:opacity-60"
          disabled={isCreatingToken || !newTokenName.trim()}
        >
          {#if isCreatingToken}
            <LoaderCircle size={14} class="animate-spin" />
            {i18n.t.settingsModal.apiTokens.generating}
          {:else}
            <Plus size={14} />
            {i18n.t.settingsModal.apiTokens.generateSubmit}
          {/if}
        </button>
      </div>
    </form>
  </div>
</Modal>

<!-- Generated API Token Reveal Modal (Shown once!) -->
<Modal
  isOpen={createdTokenResult !== null}
  onClose={() => (createdTokenResult = null)}
  labelledBy="token-reveal-title"
>
  <div class="p-6">
    <div class="mb-4 flex items-start gap-4">
      <div
        class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-emerald-500/15 text-emerald-400"
      >
        <ShieldCheck size={22} />
      </div>
      <div>
        <h3 id="token-reveal-title" class="text-ink text-base font-bold">
          {createdTokenResult?.name}
        </h3>
        <p class="text-muted mt-0.5 text-xs">
          {i18n.t.settingsModal.apiTokens.modalTitle}
        </p>
      </div>
    </div>

    <!-- Warning in gold/amber -->
    <div
      class="mb-4 flex items-start gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3.5 text-xs leading-relaxed text-amber-200"
    >
      <AlertTriangle size={18} class="mt-0.5 shrink-0 text-amber-400" />
      <div>
        <strong class="mb-0.5 block font-semibold text-amber-300"
          >{i18n.t.settingsModal.apiTokens.warningTitle}</strong
        >
        {i18n.t.settingsModal.apiTokens.warningText}
      </div>
    </div>

    {#if createdTokenResult}
      <div class="mb-6 space-y-2">
        <div class="flex items-center gap-2 rounded-xl border border-white/[0.12] bg-black/60 p-3">
          <code
            class="flex-1 font-mono text-xs tracking-wide break-all text-emerald-400 select-all sm:text-sm"
          >
            {createdTokenResult.rawToken}
          </code>
          <button
            type="button"
            class="tap inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-lg bg-[#5844e0] px-3 py-2 text-xs font-semibold text-white shadow-sm transition hover:bg-[#6854f0]"
            onclick={() => handleCopyToken(createdTokenResult!.rawToken)}
          >
            {#if hasCopiedToken}
              <Check size={14} class="text-emerald-300" />
              <span>{i18n.t.settingsModal.apiTokens.copied}</span>
            {:else}
              <Copy size={14} />
              <span>{i18n.t.settingsModal.apiTokens.copyToken}</span>
            {/if}
          </button>
        </div>
      </div>
    {/if}

    <div class="flex justify-end pt-2">
      <button
        type="button"
        class="tap inline-flex h-9 w-full cursor-pointer items-center justify-center rounded-lg bg-white/10 px-5 text-xs font-semibold text-white transition hover:bg-white/15 sm:w-auto"
        onclick={() => (createdTokenResult = null)}
      >
        {i18n.t.settingsModal.apiTokens.closeModal}
      </button>
    </div>
  </div>
</Modal>

<!-- Revoke API Token Confirmation Modal -->
<Modal
  isOpen={tokenToRevoke !== null}
  onClose={() => (tokenToRevoke = null)}
  labelledBy="revoke-token-title"
>
  <div class="p-6">
    <div class="flex items-start gap-4">
      <div
        class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-rose-500/15 text-rose-400"
      >
        <AlertTriangle size={20} />
      </div>
      <div>
        <h3 id="revoke-token-title" class="text-ink text-base font-bold">
          {i18n.t.settingsModal.apiTokens.revokeConfirmTitle}
        </h3>
        <p class="text-muted mt-2 text-xs leading-relaxed">
          {i18n.t.settingsModal.apiTokens.revokeConfirmText}
        </p>
        {#if tokenToRevoke}
          <div
            class="bg-field text-ink mt-3 rounded-md border border-white/10 px-3 py-2 font-mono text-xs"
          >
            <span class="text-muted mr-2 font-sans">{tokenToRevoke.name}:</span>
            {tokenToRevoke.tokenPrefix}••••••••
          </div>
        {/if}
      </div>
    </div>

    <div class="mt-6 flex items-center justify-end gap-3 border-t border-white/[0.07] pt-4">
      <button
        type="button"
        class="bg-field text-ink hover:bg-card inline-flex h-9 cursor-pointer items-center rounded-md border border-white/10 px-4 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-60"
        disabled={isRevokingToken}
        onclick={() => (tokenToRevoke = null)}
      >
        {i18n.t.settingsModal.apiTokens.cancel}
      </button>
      <button
        type="button"
        class="inline-flex h-9 cursor-pointer items-center gap-2 rounded-md bg-rose-600 px-4 text-xs font-semibold text-white transition hover:bg-rose-500 disabled:cursor-not-allowed disabled:opacity-60"
        disabled={isRevokingToken}
        onclick={handleRevokeToken}
      >
        {#if isRevokingToken}
          <LoaderCircle size={14} class="animate-spin" />
          {i18n.t.settingsModal.apiTokens.revoking}
        {:else}
          <Trash2 size={14} />
          {i18n.t.settingsModal.apiTokens.revokeButton}
        {/if}
      </button>
    </div>
  </div>
</Modal>
