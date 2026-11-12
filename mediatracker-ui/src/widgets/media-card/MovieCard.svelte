<script lang="ts">
  import { MEDIA_STATUS, type MovieMedia } from "$shared/types";
  import { i18n } from "$shared/i18n/index.svelte";
  import BaseCard from "./BaseCard.svelte";
  import CardProgressControls from "./CardProgressControls.svelte";
  import CardTitleBlock from "./CardTitleBlock.svelte";
  import { createCardStatus } from "$features/change-status/statusController.svelte";
  import type { MediaCardProps } from "./cardTypes";

  let {
    item,
    timeHint,
    showProgress = true,
    onOpen = () => {},
    onStatusChange,
    onProgressCommitted = () => {},
    onDelete,
    onEdit,
  }: MediaCardProps & { item: MovieMedia } = $props();

  const status = createCardStatus({
    getItem: () => item,
    getOnStatusChange: () => onStatusChange,
    getOnProgressCommitted: () => onProgressCommitted,
  });

  /* A film has no episode/page counter: watched is a single 0/1 toggle. */
  const watched = $derived(item.status === MEDIA_STATUS.completed);

  function toggleWatched(delta: number) {
    if (delta > 0 === watched) return;
    void status.changeStatus(delta > 0 ? MEDIA_STATUS.completed : MEDIA_STATUS.planned);
  }
</script>

<BaseCard {item} {timeHint} {onOpen} {onStatusChange} {onProgressCommitted} {onDelete} {onEdit}>
  <CardTitleBlock title={item.title} subtitle={item.director?.trim() || i18n.t.types.movie} />

  {#snippet hover()}
    {#if showProgress}
      <CardProgressControls
        text={watched ? "1 / 1" : "0 / 1"}
        onStep={toggleWatched}
        decrementDisabled={!watched}
        incrementDisabled={watched}
      />
    {/if}
  {/snippet}
</BaseCard>
