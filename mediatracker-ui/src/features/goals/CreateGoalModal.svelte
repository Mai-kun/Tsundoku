<script lang="ts">
  import { untrack } from "svelte";
  import { Sparkles, Trophy } from "$shared/ui/Icons";
  import Modal from "$shared/ui/Modal.svelte";
  import Select from "$shared/ui/Select.svelte";
  import { createGoal } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { CreateGoalPayload, GoalDto } from "$shared/types";

  interface Props {
    isOpen: boolean;
    year: number;
    onClose: () => void;
    onCreated: (goal: GoalDto) => void;
  }

  let { isOpen, year, onClose, onCreated }: Props = $props();

  type Tab = "templates" | "custom";

  let tab = $state<Tab>("templates");
  let busy = $state(false);
  let error = $state("");

  // Custom-goal form
  let title = $state("");
  let description = $state("");
  let icon = $state("🎯");
  let goalYear = $state(new Date().getFullYear());
  let targetCount = $state(10);
  let category = $state("all");

  $effect(() => {
    if (isOpen) {
      untrack(() => {
        tab = "templates";
        error = "";
        title = "";
        description = "";
        icon = "🎯";
        goalYear = year;
        targetCount = 10;
        category = "all";
      });
    }
  });

  const categoryOptions = $derived([
    { value: "all", label: i18n.t.goals.modal.categoryAll },
    { value: "book", label: i18n.t.navigation.book },
    { value: "movie", label: i18n.t.navigation.movie },
    { value: "anime", label: i18n.t.navigation.anime },
    { value: "manga", label: i18n.t.navigation.manga },
    { value: "game", label: i18n.t.navigation.game },
    { value: "tvshow", label: i18n.t.navigation.tvshow },
  ]);

  interface Template {
    title: string;
    icon: string;
    target: number;
    category: string;
    smartQueryJson?: string;
  }

  const templates = $derived<Template[]>([
    { title: i18n.t.goals.modal.templateBooks(15), icon: "📚", target: 15, category: "book" },
    { title: i18n.t.goals.modal.templateGames(10), icon: "🎮", target: 10, category: "game" },
    { title: i18n.t.goals.modal.templateAnime(30), icon: "🍥", target: 30, category: "anime" },
    {
      title: i18n.t.goals.modal.templateRetro(5),
      icon: "🕹️",
      target: 5,
      category: "movie",
      smartQueryJson: '{"releaseYearTo":1999,"sortOrder":"desc"}',
    },
  ]);

  async function submit(payload: CreateGoalPayload) {
    if (busy) return;
    busy = true;
    error = "";
    try {
      const goal = await createGoal(payload);
      onCreated(goal);
      onClose();
    } catch {
      error = i18n.t.goals.modal.createFailed;
    } finally {
      busy = false;
    }
  }

  function submitCustom() {
    if (!title.trim() || targetCount < 1) return;
    void submit({
      title: title.trim(),
      description: description.trim() || null,
      icon: icon.trim() || "🎯",
      year: goalYear,
      targetCount,
      category,
    });
  }
</script>

<Modal {isOpen} {onClose} size="md">
  <div class="space-y-4 p-1">
    <div class="flex items-center gap-2.5">
      <span
        class="bg-elevated grid size-9 place-items-center rounded-lg border border-white/[0.08]"
      >
        <Trophy size={17} class="text-[#818cf8]" aria-hidden="true" />
      </span>
      <h2 class="text-ink text-base font-semibold">{i18n.t.goals.modal.createTitle}</h2>
    </div>

    <div class="flex gap-2" role="tablist">
      <button
        type="button"
        role="tab"
        aria-selected={tab === "templates"}
        class={`flex flex-1 cursor-pointer items-center justify-center gap-1.5 rounded-lg border px-3 py-2 text-xs font-medium transition ${
          tab === "templates"
            ? "border-[#818cf8]/40 bg-[#5844e0]/15 font-semibold text-[#a5b4fc]"
            : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
        }`}
        onclick={() => (tab = "templates")}
      >
        <Sparkles size={14} />
        {i18n.t.goals.modal.templatesTab}
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={tab === "custom"}
        class={`flex flex-1 cursor-pointer items-center justify-center rounded-lg border px-3 py-2 text-xs font-medium transition ${
          tab === "custom"
            ? "border-[#818cf8]/40 bg-[#5844e0]/15 font-semibold text-[#a5b4fc]"
            : "bg-card/60 text-muted hover:text-ink hover:bg-card border-white/10"
        }`}
        onclick={() => (tab = "custom")}
      >
        {i18n.t.goals.modal.customTab}
      </button>
    </div>

    {#if tab === "templates"}
      <div class="grid gap-2">
        {#each templates as template (template.title)}
          <button
            type="button"
            disabled={busy}
            class="bg-card/60 hover:bg-elevated flex cursor-pointer items-center gap-3 rounded-lg border border-white/10 p-3 text-left transition hover:border-[#818cf8]/40 disabled:cursor-wait disabled:opacity-60"
            onclick={() =>
              void submit({
                title: `${template.title} ${goalYear}`,
                icon: template.icon,
                year: goalYear,
                targetCount: template.target,
                category: template.category,
                smartQueryJson: template.smartQueryJson ?? null,
              })}
          >
            <span class="bg-field text-xl" aria-hidden="true">{template.icon}</span>
            <span class="text-ink flex-1 text-sm font-medium">{template.title}</span>
            <span class="text-muted text-xs tabular-nums">{goalYear}</span>
          </button>
        {/each}
      </div>
    {:else}
      <div class="space-y-3">
        <div>
          <label class="text-muted mb-1 block text-xs font-medium" for="goal-title">
            {i18n.t.goals.modal.titleField}
          </label>
          <input
            id="goal-title"
            bind:value={title}
            maxlength="120"
            class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[#818cf8]/60 focus:ring-1 focus:ring-[#818cf8]/30"
            placeholder="🎯"
          />
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-muted mb-1 block text-xs font-medium" for="goal-year">
              {i18n.t.goals.modal.yearField}
            </label>
            <input
              id="goal-year"
              type="number"
              bind:value={goalYear}
              min="1900"
              max="2200"
              class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[#818cf8]/60 focus:ring-1 focus:ring-[#818cf8]/30"
            />
          </div>
          <div>
            <label class="text-muted mb-1 block text-xs font-medium" for="goal-target">
              {i18n.t.goals.modal.targetField}
            </label>
            <input
              id="goal-target"
              type="number"
              bind:value={targetCount}
              min="1"
              class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[#818cf8]/60 focus:ring-1 focus:ring-[#818cf8]/30"
            />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="text-muted mb-1 block text-xs font-medium" for="goal-category">
              {i18n.t.goals.modal.categoryField}
            </label>
            <Select
              id="goal-category"
              options={categoryOptions}
              value={category}
              onChange={(next) => (category = next)}
              class="w-full rounded-lg px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label class="text-muted mb-1 block text-xs font-medium" for="goal-icon">
              {i18n.t.goals.modal.iconField}
            </label>
            <input
              id="goal-icon"
              bind:value={icon}
              maxlength="8"
              class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[#818cf8]/60 focus:ring-1 focus:ring-[#818cf8]/30"
            />
          </div>
        </div>
        <div>
          <label class="text-muted mb-1 block text-xs font-medium" for="goal-description">
            {i18n.t.goals.modal.descriptionField}
          </label>
          <input
            id="goal-description"
            bind:value={description}
            maxlength="300"
            class="bg-field text-ink w-full rounded-lg border border-white/10 px-3 py-2 text-sm transition outline-none focus:border-[#818cf8]/60 focus:ring-1 focus:ring-[#818cf8]/30"
          />
        </div>
      </div>
    {/if}

    {#if error}
      <div
        class="flex items-center gap-2.5 rounded-lg border border-rose-400/25 bg-rose-400/10 p-3 text-xs text-rose-200"
        role="alert"
      >
        <span class="shrink-0 font-bold">!</span>
        <span>{error}</span>
      </div>
    {/if}

    {#if tab === "custom"}
      <div class="flex justify-end">
        <button
          type="button"
          disabled={busy || title.trim() === "" || targetCount < 1}
          class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-[#818cf8]/40 bg-[#5446cf]/80 px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#5446cf] disabled:cursor-wait disabled:opacity-60"
          onclick={submitCustom}
        >
          {i18n.t.goals.modal.create}
        </button>
      </div>
    {/if}
  </div>
</Modal>
