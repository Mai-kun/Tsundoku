<script lang="ts">
  import { Bookmark, Flame, Heart, List, Sparkles, Star, X } from "$shared/ui/Icons.svelte";
  import { createList, errorMessage, getMedia, updateList } from "$shared/api/api";
  import { fullSizeCoverUrl } from "$entities/media/model/coverUrl";
  import type {
    CustomListSummary,
    CreateListPayload,
    SmartListQuery,
    MediaItem,
  } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import SmartListBuilder from "$features/lists/SmartListBuilder.svelte";

  interface Props {
    isOpen: boolean;
    list?: CustomListSummary | null;
    onClose: () => void;
    onSaved: () => void;
  }
  let { isOpen, list = null, onClose, onSaved }: Props = $props();
  let name = $state("");
  let description = $state("");
  let color = $state("#5844e0");
  let icon = $state("list");
  let busy = $state(false);
  let error = $state("");
  let nameInput = $state<HTMLInputElement | null>(null);
  let lastOpen = false;
  let listType = $state<"manual" | "smart">("manual");
  let smartQuery = $state<SmartListQuery>({});
  let allMedia = $state<MediaItem[]>([]);
  let matchedItems = $state<MediaItem[]>([]);

  const colors = ["#5844e0", "#3b82f6", "#10b981", "#f59e0b", "#ec4899", "#06b6d4"];
  const icons = [
    { key: "list", component: List },
    { key: "bookmark", component: Bookmark },
    { key: "heart", component: Heart },
    { key: "star", component: Star },
    { key: "sparkles", component: Sparkles },
    { key: "flame", component: Flame },
  ];

  $effect(() => {
    if (isOpen) nameInput?.focus();
    if (isOpen && !lastOpen) {
      name = list?.name ?? "";
      description = list?.description ?? "";
      color = list?.color ?? colors[0];
      icon = list?.icon ?? "list";
      error = "";
      if (list?.smartQueryJson) {
        listType = "smart";
        try {
          smartQuery = JSON.parse(list.smartQueryJson);
        } catch {
          smartQuery = {};
        }
      } else {
        listType = "manual";
        smartQuery = {};
      }
      // Load media for live preview (best-effort, only when creating)
      if (!list) {
        getMedia({})
          .then((items) => {
            allMedia = items;
          })
          .catch(() => {});
      }
    }
    lastOpen = isOpen;
  });

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (!name.trim() || busy) return;
    busy = true;
    error = "";
    const payload: CreateListPayload = {
      name: name.trim(),
      description: description.trim() || null,
      icon,
      color,
      smartQueryJson: listType === "smart" ? JSON.stringify(smartQuery) : null,
    };
    try {
      if (list) await updateList(list.id, payload);
      else await createList(payload);
      onSaved();
      onClose();
    } catch (caught) {
      error = errorMessage(caught);
    } finally {
      busy = false;
    }
  }
</script>

<Modal {isOpen} {onClose} labelledBy="custom-list-modal-title" size="lg">
  <form class="flex max-h-[85vh] flex-col overflow-hidden" onsubmit={save}>
    <!-- 1. Закрепленная шапка -->
    <header class="shrink-0 space-y-3 border-b border-white/[0.08] bg-[#151a26] px-6 py-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 id="custom-list-modal-title" class="text-ink text-lg font-bold">
            {list ? i18n.t.views.listEdit : i18n.t.views.listCreate}
          </h2>
          <p class="text-muted mt-0.5 text-xs">{i18n.t.views.listModalHint}</p>
        </div>
        <button
          type="button"
          class="text-muted hover:text-ink grid h-8 w-8 shrink-0 place-items-center rounded-lg transition hover:bg-white/10"
          aria-label={i18n.t.common.close}
          onclick={onClose}
        >
          <X size={18} aria-hidden="true" />
        </button>
      </div>

      {#if !list}
        <div class="flex gap-2 pt-1">
          <button
            type="button"
            class={`inline-flex flex-1 items-center justify-center gap-1.5 rounded-lg border py-2 text-sm font-medium transition ${listType === "manual" ? "border-accent bg-accent/15 text-accent" : "text-muted hover:text-ink border-white/10 hover:border-white/20"}`}
            onclick={() => {
              listType = "manual";
              smartQuery = {};
            }}
          >
            <span>📁</span>
            <span>{i18n.t.views.listTypeManual}</span>
          </button>
          <button
            type="button"
            class={`inline-flex flex-1 items-center justify-center gap-1.5 rounded-lg border py-2 text-sm font-medium transition ${listType === "smart" ? "border-violet-400/60 bg-violet-400/15 text-violet-300" : "text-muted hover:text-ink border-white/10 hover:border-white/20"}`}
            onclick={() => (listType = "smart")}
          >
            <span>⚡</span>
            <span>{i18n.t.views.listTypeSmart}</span>
          </button>
        </div>
      {/if}
    </header>

    <!-- 2. Прокручиваемая центральная область -->
    <div class="thin-scroll min-h-0 flex-1 space-y-5 overflow-y-auto p-6">
      <label class="text-ink block space-y-1.5 text-sm font-medium">
        {i18n.t.views.listName}
        <input
          bind:this={nameInput}
          bind:value={name}
          maxlength="100"
          required
          class="bg-canvas focus:border-accent w-full rounded-lg border border-white/10 px-3 py-2.5 text-sm outline-none"
        />
      </label>
      <label class="text-ink block space-y-1.5 text-sm font-medium">
        {i18n.t.views.listDescription}
        <textarea
          bind:value={description}
          maxlength="500"
          rows="2"
          class="bg-canvas focus:border-accent w-full resize-y rounded-lg border border-white/10 px-3 py-2.5 text-sm outline-none"
        ></textarea>
      </label>
      <fieldset class="space-y-2">
        <legend class="text-ink text-sm font-medium">{i18n.t.views.listColor}</legend>
        <div class="flex flex-wrap gap-3">
          {#each colors as value (value)}
            <button
              type="button"
              aria-label={value}
              aria-pressed={color === value}
              class="h-8 w-8 rounded-full ring-offset-2 ring-offset-[#151a26] transition"
              style={`background:${value}`}
              class:ring-2={color === value}
              class:ring-white={color === value}
              onclick={() => (color = value)}
            ></button>
          {/each}
        </div>
      </fieldset>
      <fieldset class="space-y-2">
        <legend class="text-ink text-sm font-medium">{i18n.t.views.listIcon}</legend>
        <div class="flex flex-wrap gap-2">
          {#each icons as choice (choice.key)}
            {@const Icon = choice.component}
            <button
              type="button"
              aria-label={choice.key}
              aria-pressed={icon === choice.key}
              class={`grid h-10 w-10 place-items-center rounded-lg border transition ${icon === choice.key ? "border-accent bg-accent/15" : "text-muted border-white/10 hover:border-white/20"}`}
              onclick={() => (icon = choice.key)}><Icon size={18} /></button
            >
          {/each}
        </div>
      </fieldset>

      {#if listType === "smart"}
        <div class="rounded-xl border border-violet-400/20 bg-violet-400/5 p-4 sm:p-5">
          <SmartListBuilder
            query={smartQuery}
            onQueryChange={(q) => (smartQuery = q)}
            onMatchesChange={(matches) => (matchedItems = matches)}
            {allMedia}
          />
        </div>
      {/if}

      {#if error}<p class="text-sm text-rose-300" role="alert">{error}</p>{/if}
    </div>

    <!-- 3. Закрепленный подвал -->
    <footer
      class="flex shrink-0 flex-wrap items-center justify-between gap-4 border-t border-white/[0.08] bg-[#12151c]/90 px-6 py-4 sm:flex-nowrap"
    >
      <div class="min-w-0 flex-1">
        {#if listType === "smart"}
          <div class="flex items-center gap-3">
            <span class="shrink-0 text-xs font-semibold text-violet-300">
              ⚡ {i18n.t.views.smartPreviewCount(matchedItems.length)}
            </span>
            {#if matchedItems.length > 0}
              <div class="flex items-center gap-1.5 overflow-hidden">
                {#each matchedItems.slice(0, 5) as item (item.id)}
                  {#if item.coverUrl}
                    <img
                      src={fullSizeCoverUrl(item.coverUrl)}
                      alt={item.title}
                      title={item.title}
                      class="aspect-[2/3] h-8 shrink-0 rounded object-cover shadow ring-1 ring-white/10"
                    />
                  {:else}
                    <div
                      class="bg-elevated text-muted grid aspect-[2/3] h-8 w-5 shrink-0 place-items-center rounded text-[9px] ring-1 ring-white/10"
                      title={item.title}
                    >
                      ?
                    </div>
                  {/if}
                {/each}
              </div>
            {/if}
          </div>
        {/if}
      </div>
      <div class="ml-auto flex shrink-0 items-center gap-2">
        <button
          type="button"
          class="text-muted rounded-lg px-4 py-2 text-sm transition hover:bg-white/5"
          onclick={onClose}
        >
          {i18n.t.common.cancel}
        </button>
        <button
          type="submit"
          disabled={!name.trim() || busy}
          class="bg-accent hover:bg-accent-hover rounded-lg px-4 py-2 text-sm font-semibold text-white transition disabled:opacity-50"
        >
          {busy ? i18n.t.common.saving : list ? i18n.t.common.save : i18n.t.views.listCreate}
        </button>
      </div>
    </footer>
  </form>
</Modal>
