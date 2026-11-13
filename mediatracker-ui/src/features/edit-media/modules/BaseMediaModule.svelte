<script lang="ts">
  import Select from "$shared/ui/Select.svelte";
  import { Layers } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import { statusLabel } from "$entities/media/model/mediaLabels";
  import { MEDIA_STATUS, type MediaStatus, type MediaType } from "$shared/types";
  import { EDIT_MEDIA_TYPES } from "./moduleTypes";
  import ModuleCard from "./ModuleCard.svelte";

  /**
   * Block 1 — category-independent basics: type, title, score, status and the start/finish dates.
   * Everything arrives through `$bindable` props, so the module renders anywhere (the big editor
   * modal, a quick-edit popover, a dedicated screen) without knowing about the modal's state.
   */
  interface Props {
    flat?: boolean;
    /** Prefix for inner Select ids, so several instances can coexist on one page. */
    idPrefix?: string;
    type: MediaType;
    title: string;
    score: string;
    status: MediaStatus;
    startedAt: string;
    finishedAt: string;
  }

  let {
    flat = false,
    idPrefix = "edit-media",
    type = $bindable(),
    title = $bindable(),
    score = $bindable(),
    status = $bindable(),
    startedAt = $bindable(),
    finishedAt = $bindable(),
  }: Props = $props();

  const statusOptions = Object.values(MEDIA_STATUS).map((value) => ({
    value,
    label: statusLabel(value),
  }));
</script>

<ModuleCard flat={flat} title={i18n.t.createModal.modules.base}>
  {#snippet icon()}
    <Layers size={15} aria-hidden="true" />
  {/snippet}
  <div class="space-y-3">
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.createModal.fields.type}</span>
        <Select
          id="{idPrefix}-type"
          options={EDIT_MEDIA_TYPES.map((mediaType) => ({
            value: mediaType,
            label: i18n.t.types[mediaType],
          }))}
          value={type}
          onChange={(next) => (type = next)}
        />
      </label>
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.createModal.fields.title}</span>
        <input
          id="{idPrefix}-title"
          class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          bind:value={title}
          placeholder={i18n.t.createModal.placeholders.title}
          required
        />
      </label>
    </div>
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.createModal.fields.score}</span>
        <input
          class="bg-field h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          type="number"
          min="1"
          max="10"
          bind:value={score}
        />
      </label>
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.status.label}</span>
        <Select
          id="{idPrefix}-status"
          options={statusOptions}
          value={status}
          onChange={(next) => (status = next)}
        />
      </label>
    </div>
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.createModal.fields.startedAt}</span>
        <input
          class="bg-field focus:border-accent h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none"
          type="datetime-local"
          bind:value={startedAt}
        />
      </label>
      <label class="text-ink space-y-1.5 text-sm font-medium">
        <span>{i18n.t.createModal.fields.finishedAt}</span>
        <input
          class="bg-field focus:border-accent h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none"
          type="datetime-local"
          bind:value={finishedAt}
        />
      </label>
    </div>
  </div>
</ModuleCard>
