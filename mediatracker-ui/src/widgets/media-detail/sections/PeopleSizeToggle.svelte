<script lang="ts">
  import { uiSettings, type PeopleCardSize } from "$shared/utils/uiSettings.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { LayoutGrid, List } from "$shared/ui/Icons.svelte";

  interface Props {
    /** Storage key (media category): anime / manga / movie / tvshow / game / book. */
    category: string;
    /** Which block this switch drives — cast and staff store their size separately. */
    block: "cast" | "staff";
  }

  let { category, block }: Props = $props();

  /** Icon-only compact/large toggle; mirrored in CastSection and CreatorSection. */
  const isLarge = $derived(
    block === "cast"
      ? uiSettings.getCastSize(category) === "large"
      : uiSettings.getStaffSize(category) === "large",
  );
  const setSize = (size: PeopleCardSize) =>
    block === "cast"
      ? uiSettings.setCastSize(category, size)
      : uiSettings.setStaffSize(category, size);
</script>

<div
  class="inline-flex items-center gap-0.5 rounded-lg border border-white/[0.08] bg-white/[0.03] p-0.5"
>
  <button
    type="button"
    class="grid size-6 cursor-pointer place-items-center rounded-md transition
               {isLarge ? 'text-muted hover:text-white' : 'bg-accent text-white'}"
    onclick={() => setSize("compact")}
    title={i18n.t.detail.compactViewTooltip}
    aria-label={i18n.t.detail.compactViewTooltip}
    aria-pressed={!isLarge}
  >
    <List size={14} />
  </button>
  <button
    type="button"
    class="grid size-6 cursor-pointer place-items-center rounded-md transition
               {isLarge ? 'bg-accent text-white' : 'text-muted hover:text-white'}"
    onclick={() => setSize("large")}
    title={i18n.t.detail.largeViewTooltip}
    aria-label={i18n.t.detail.largeViewTooltip}
    aria-pressed={isLarge}
  >
    <LayoutGrid size={14} />
  </button>
</div>
