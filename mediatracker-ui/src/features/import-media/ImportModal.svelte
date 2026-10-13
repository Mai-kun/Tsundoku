<script lang="ts">
  import { getLists, getSources, importAniListProfile, importFile, importSteamProfile, saveSourceKey } from "$shared/api/api";
  import type { CustomListSummary, ImportResultDto } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";

  interface Props { isOpen: boolean; onClose: () => void; onImportCompleted: () => void; onNavigateToList?: (id: string) => void; }
  let { isOpen, onClose, onImportCompleted, onNavigateToList }: Props = $props();
  type Provider = "mal" | "shikimori" | "letterboxd" | "goodreads" | "steam" | "anilist" | "mangalib" | "custom";
  let provider = $state<Provider>("mal");
  let file = $state<File | null>(null);
  let steamProfile = $state("");
  let steamApiKey = $state("");
  let steamKeyConfigured = $state(false);
  let saveSteamKey = $state(false);
  let anilistMode = $state<"file" | "profile">("file");
  let anilistUsername = $state("");
  let showTemplate = $state(false);
  let templateCopied = $state(false);
  let skipDuplicates = $state(true);
  let addToList = $state(false);
  let listMode = $state<"existing" | "new">("new");
  let lists = $state<CustomListSummary[]>([]);
  let targetListId = $state("");
  let newListName = $state("");
  let busy = $state(false);
  let error = $state("");
  let result = $state<ImportResultDto | null>(null);
  let dragging = $state(false);
  let profileChecked = $state(false);
  const providers = $derived<{ id: Provider; icon: string; title: string; subtitle: string; accent?: string }[]>([
    { id: "mal", icon: "MAL", title: "MyAnimeList", subtitle: "Anime and manga XML" },
    { id: "shikimori", icon: "Ш", title: "Shikimori", subtitle: "Anime and manga JSON / XML" },
    { id: "letterboxd", icon: "L", title: "Letterboxd", subtitle: "Movie CSV" },
    { id: "goodreads", icon: "G", title: "Goodreads", subtitle: "Book CSV" },
    { id: "steam", icon: "S", title: "Steam", subtitle: "Games file or public profile" },
    { id: "anilist", icon: "AL", title: "AniList", subtitle: i18n.t.importModal.subtitleAnilist, accent: "#02a9ff" },
    { id: "mangalib", icon: "ML", title: "MangaLib", subtitle: i18n.t.importModal.subtitleMangalib, accent: "#ff6740" },
    { id: "custom", icon: "{ }", title: "Custom", subtitle: i18n.t.importModal.subtitleCustom, accent: "#a78bfa" },
  ]);
  const fileAccept = $derived(provider === "mal" || provider === "shikimori" ? ".xml,.json" : provider === "steam" || provider === "anilist" ? ".json" : provider === "letterboxd" || provider === "goodreads" ? ".csv" : ".json,.csv");
  const allowedExtensions = $derived(provider === "mal" || provider === "shikimori" ? ["xml", "json"] : provider === "steam" || provider === "anilist" ? ["json"] : provider === "letterboxd" || provider === "goodreads" ? ["csv"] : ["json", "csv"]);
  const helpText = $derived(({ mal: i18n.t.importModal.helpMal, shikimori: i18n.t.importModal.helpShikimori, letterboxd: i18n.t.importModal.helpLetterboxd, goodreads: i18n.t.importModal.helpGoodreads, steam: i18n.t.importModal.helpSteam, anilist: i18n.t.importModal.helpAnilist, mangalib: i18n.t.importModal.helpMangalib, custom: i18n.t.importModal.helpCustom })[provider]);
  const defaultListName = $derived(i18n.t.importModal.defaultList(provider));

  $effect(() => {
    if (isOpen) {
      void getLists().then(value => lists = value).catch(() => lists = []);
      void getSources().then(sources => steamKeyConfigured = sources.some(source => source.id === "steam" && source.hasKey)).catch(() => steamKeyConfigured = false);
    }
    else { result = null; error = ""; file = null; }
  });
  $effect(() => { if (addToList && listMode === "new" && !newListName) newListName = defaultListName; });
  function pickFile(value?: File) { if (!value) return; file = value; error = ""; }
  function handleDrop(event: DragEvent) { event.preventDefault(); dragging = false; pickFile(event.dataTransfer?.files[0]); }

  async function runImport() {
    if (busy) return;
    const anilistProfileMode = provider === "anilist" && anilistMode === "profile";
    if (!anilistProfileMode && (provider !== "steam" || file)) {
      if (!file) { error = i18n.t.importModal.selectFileError; return; }
      const ext = file.name.split(".").pop()?.toLowerCase();
      if (!ext || !allowedExtensions.includes(ext)) { error = i18n.t.importModal.invalidFile; return; }
    } else if (anilistProfileMode) {
      if (!anilistUsername.trim()) { error = i18n.t.importModal.anilistUsernameError; return; }
    } else if (!steamProfile.trim()) { error = i18n.t.importModal.steamRequired; return; }
    if (addToList && listMode === "existing" && !targetListId) { error = i18n.t.importModal.chooseListError; return; }
    if (addToList && listMode === "new" && !newListName.trim()) { error = i18n.t.importModal.listNameError; return; }
    busy = true; error = "";
    try {
      const listFields = addToList ? (listMode === "existing" ? { targetListId } : { newListName: newListName.trim() }) : {};
      let importTask: Promise<ImportResultDto>;
      if (anilistProfileMode) {
        importTask = importAniListProfile({ username: anilistUsername.trim(), skipDuplicates, ...listFields });
      }
      else if (provider === "steam" && !file) {
        const value = steamProfile.trim();
        importTask = importSteamProfile({ ...( /^\d{17}$/.test(value) ? { steamId: value } : { profileUrl: value }), steamApiKey: steamApiKey || undefined, skipDuplicates, ...listFields });
      }
      else {
        const form = new FormData();
        form.append("file", file!); form.append("provider", provider); form.append("skipDuplicates", String(skipDuplicates));
        if (addToList && listMode === "existing") form.append("targetListId", targetListId);
        if (addToList && listMode === "new") form.append("newListName", newListName.trim());
        importTask = importFile(form);
      }
      const saveKeyTask = provider === "steam" && saveSteamKey && steamApiKey.trim()
        ? saveSourceKey("steam", steamApiKey.trim())
        : Promise.resolve();
      [result] = await Promise.all([importTask, saveKeyTask]);
      onImportCompleted();
    } catch (caught) { error = caught instanceof Error ? caught.message : i18n.t.importModal.failed; }
    finally { busy = false; }
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
  const templateCsv = "title,type,status,score,progress,totalCount,author,releaseYear";
  async function copyTemplate() {
    try { await navigator.clipboard.writeText(templateJson); templateCopied = true; setTimeout(() => templateCopied = false, 2000); }
    catch { error = i18n.t.importModal.templateCopyFailed; }
  }
</script>

<Modal {isOpen} {onClose} size="lg" labelledBy="import-modal-title">
  <div class="max-h-[88vh] overflow-y-auto p-6">
    <div class="flex items-center justify-between"><div><h2 id="import-modal-title" class="text-xl font-bold text-ink">{i18n.t.importModal.title}</h2><p class="mt-1 text-sm text-muted">{i18n.t.importModal.description}</p></div><button class="rounded-lg px-3 py-2 text-muted hover:bg-elevated" onclick={onClose}>{i18n.t.common.close}</button></div>
    {#if result}
      <div class="mt-6 rounded-xl border border-emerald-400/20 bg-emerald-400/10 p-5">
        <h3 class="text-lg font-semibold text-emerald-200">{i18n.t.importModal.success}</h3>
        <dl class="mt-4 space-y-2 text-sm text-ink"><div class="flex justify-between"><dt>{i18n.t.importModal.total}</dt><dd>{result.totalFound}</dd></div><div class="flex justify-between"><dt>{i18n.t.importModal.imported}</dt><dd>{result.importedCount}</dd></div><div class="flex justify-between"><dt>{i18n.t.importModal.skipped}</dt><dd>{result.skippedDuplicates}</dd></div></dl>
        <div class="mt-5 flex flex-wrap gap-3">{#if result.targetListId}<button class="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white" onclick={() => { onNavigateToList?.(result!.targetListId!); onClose(); }}>{i18n.t.importModal.openList}</button>{/if}<button class="rounded-lg border border-white/10 px-4 py-2 text-sm text-ink" onclick={onClose}>{i18n.t.common.close}</button></div>
      </div>
    {:else}
      <div class="mt-6"><h3 class="mb-3 text-sm font-semibold text-ink">{i18n.t.importModal.source}</h3><div class="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {#each providers as item (item.id)}<button type="button" class={`flex items-center gap-3 rounded-xl border p-3 text-left transition ${provider === item.id ? "border-accent bg-accent/10" : "border-white/10 bg-card hover:border-white/20"}`} style={provider === item.id && item.accent ? `border-color: ${item.accent}` : undefined} onclick={() => { provider = item.id; file = null; error = ""; }}><span class="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-elevated font-bold" style={item.accent ? `background: ${item.accent}1f; color: ${item.accent}` : undefined}>{item.icon}</span><span><span class="block text-sm font-semibold text-ink">{item.title}</span><span class="mt-0.5 block text-xs text-muted">{item.subtitle}</span></span></button>{/each}
      </div></div>
      <div class="mt-5"><h3 class="mb-2 text-sm font-semibold text-ink">{i18n.t.importModal.fileLabel}</h3>
        {#if provider === "anilist"}<div class="mb-3 flex gap-2" role="tablist"><button type="button" role="tab" aria-selected={anilistMode === "file"} class={`flex-1 rounded-lg border px-3 py-2 text-sm font-medium transition ${anilistMode === "file" ? "border-[#02a9ff] bg-[#02a9ff]/10 text-ink" : "border-white/10 bg-card text-muted hover:text-ink"}`} onclick={() => { anilistMode = "file"; error = ""; }}>{i18n.t.importModal.anilistFileTab}</button><button type="button" role="tab" aria-selected={anilistMode === "profile"} class={`flex-1 rounded-lg border px-3 py-2 text-sm font-medium transition ${anilistMode === "profile" ? "border-[#02a9ff] bg-[#02a9ff]/10 text-ink" : "border-white/10 bg-card text-muted hover:text-ink"}`} onclick={() => { anilistMode = "profile"; file = null; error = ""; }}>{i18n.t.importModal.anilistProfileTab}</button></div>{/if}
        {#if provider === "anilist" && anilistMode === "profile"}<div class="mt-1"><label class="mb-1 block text-xs font-medium text-muted" for="anilist-username">{i18n.t.importModal.anilistUsername}</label><div class="flex gap-2"><input id="anilist-username" bind:value={anilistUsername} placeholder={i18n.t.importModal.anilistUsernamePlaceholder} class="min-w-0 flex-1 rounded-lg border border-white/10 bg-card px-3 py-2 text-sm text-ink outline-none focus:border-accent" /><button type="button" class="rounded-lg bg-[#02a9ff] px-4 text-sm font-semibold text-white hover:opacity-90 disabled:cursor-wait disabled:opacity-60" disabled={busy} onclick={() => void runImport()}>{i18n.t.importModal.import}</button></div></div>
        {:else}<label class={`block cursor-pointer rounded-xl border border-dashed p-5 text-center transition ${dragging ? "border-accent bg-accent/10" : "border-white/15 bg-card hover:border-white/25"}`} ondragover={(event) => { event.preventDefault(); dragging = true; }} ondragleave={() => dragging = false} ondrop={handleDrop}><input class="sr-only" type="file" accept={fileAccept} onchange={(event) => pickFile(event.currentTarget.files?.[0])} /><span class="block text-sm text-ink">{file?.name ?? i18n.t.importModal.dropFile}</span><span class="mt-1 block text-xs text-muted">{i18n.t.importModal.formats(fileAccept)}</span></label>{/if}
        {#if provider === "steam"}<div class="mt-3"><label class="mb-1 block text-xs font-medium text-muted" for="steam-profile">{i18n.t.importModal.steamProfile}</label><div class="flex gap-2"><input id="steam-profile" bind:value={steamProfile} oninput={() => profileChecked = false} placeholder="https://steamcommunity.com/id/... or 76561198..." class="min-w-0 flex-1 rounded-lg border border-white/10 bg-card px-3 py-2 text-sm text-ink outline-none focus:border-accent" /><button type="button" class="rounded-lg border border-white/10 px-3 text-sm text-ink hover:bg-elevated" onclick={() => { const value = steamProfile.trim(); profileChecked = /^\d{17}$/.test(value) || /^https?:\/\/(www\.)?steamcommunity\.com\/(id|profiles)\/[^/]+\/?$/i.test(value); error = profileChecked ? "" : i18n.t.importModal.steamRequired; }}>{i18n.t.importModal.checkProfile}</button></div>{#if profileChecked}<p class="mt-2 text-xs text-emerald-300">{i18n.t.importModal.profileValid}</p>{/if}<label class="mb-1 mt-3 block text-xs font-medium text-muted" for="steam-api-key">{i18n.t.importModal.steamApiKey}</label><input id="steam-api-key" type="password" bind:value={steamApiKey} autocomplete="off" class="w-full rounded-lg border border-white/10 bg-card px-3 py-2 text-sm text-ink outline-none focus:border-accent" />{#if steamKeyConfigured}<p class="mt-2 text-xs text-emerald-300">{i18n.t.importModal.steamKeyConfigured}</p>{/if}<label class="mt-3 flex items-center gap-2 text-sm text-ink"><input type="checkbox" bind:checked={saveSteamKey} class="accent-accent" />{i18n.t.importModal.saveSteamKey}</label></div>{/if}
        <p class="mt-2 text-xs text-muted">{helpText}{#if provider === "steam"} <a href="https://steamcommunity.com/dev/apikey" target="_blank" rel="noreferrer" class="text-accent-soft underline">steamcommunity.com/dev/apikey</a>{/if}</p>
        {#if provider === "custom"}<div class="mt-3"><button type="button" aria-expanded={showTemplate} class="flex w-full items-center justify-between rounded-lg border border-white/10 bg-card px-3 py-2 text-left text-sm font-medium text-ink hover:border-white/20" onclick={() => showTemplate = !showTemplate}>{i18n.t.importModal.showTemplate}<span class="text-muted">{showTemplate ? "−" : "+"}</span></button>
          {#if showTemplate}<div class="mt-2 space-y-2 rounded-lg border border-white/[0.07] bg-black/20 p-3"><div><p class="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">{i18n.t.importModal.templateJsonLabel}</p><pre class="max-h-48 overflow-auto rounded-md border border-white/10 bg-black/30 p-2 text-[11px] leading-relaxed text-emerald-200">{templateJson}</pre></div><div><p class="mb-1 text-xs font-semibold uppercase tracking-wider text-muted">{i18n.t.importModal.templateCsvLabel}</p><pre class="overflow-auto rounded-md border border-white/10 bg-black/30 p-2 text-[11px] text-emerald-200">{templateCsv}</pre></div><button type="button" class="rounded-lg border border-white/10 px-3 py-1.5 text-xs font-semibold text-ink hover:bg-elevated" onclick={() => void copyTemplate()}>{templateCopied ? i18n.t.importModal.templateCopied : i18n.t.importModal.copyTemplate}</button></div>{/if}
        </div>{/if}
      </div>
      <div class="mt-5 space-y-3 rounded-xl border border-white/[0.07] bg-card/60 p-4"><h3 class="text-sm font-semibold text-ink">{i18n.t.importModal.options}</h3><label class="flex items-center gap-2 text-sm text-ink"><input type="checkbox" bind:checked={skipDuplicates} class="accent-accent" />{i18n.t.importModal.skipDuplicates}</label><label class="flex items-center gap-2 text-sm text-ink"><input type="checkbox" bind:checked={addToList} class="accent-accent" />{i18n.t.importModal.addToList}</label>
        {#if addToList}<div class="ml-6 space-y-3"><div class="flex flex-wrap gap-4 text-sm text-muted"><label class="flex items-center gap-2"><input type="radio" bind:group={listMode} value="existing" class="accent-accent" />{i18n.t.importModal.existingList}</label><label class="flex items-center gap-2"><input type="radio" bind:group={listMode} value="new" class="accent-accent" />{i18n.t.importModal.newList}</label></div>{#if listMode === "existing"}<select bind:value={targetListId} class="w-full rounded-lg border border-white/10 bg-card px-3 py-2 text-sm text-ink"><option value="">{i18n.t.importModal.selectList}</option>{#each lists as list (list.id)}<option value={list.id}>{list.name}</option>{/each}</select>{:else}<input bind:value={newListName} placeholder={defaultListName} maxlength="100" class="w-full rounded-lg border border-white/10 bg-card px-3 py-2 text-sm text-ink" />{/if}</div>{/if}
      </div>
      {#if error}<p class="mt-4 rounded-lg border border-rose-400/20 bg-rose-400/5 p-3 text-sm text-rose-200" role="alert">{error}</p>{/if}
      <div class="mt-5 flex justify-end"><button type="button" disabled={busy} class="inline-flex items-center gap-2 rounded-lg bg-accent px-5 py-2.5 text-sm font-semibold text-white hover:bg-accent-hover disabled:cursor-wait disabled:opacity-60" onclick={() => void runImport()}>{#if busy}<span class="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white"></span>{i18n.t.importModal.importing}{:else}{i18n.t.importModal.start}{/if}</button></div>
    {/if}
  </div>
</Modal>
