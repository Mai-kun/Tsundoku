<script lang="ts">
  import { Bookmark, Check, Pause, Play, X } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS, type MediaStatus } from "$shared/types";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import { statusBadgeClasses, statusLabel } from "$entities/media/model/mediaLabels";

  interface Props {
    id: string;
    status: MediaStatus;
    onSelect: (status: MediaStatus) => void;
  }

  let { id, status, onSelect }: Props = $props();

  const instanceId = Math.random().toString(36).slice(2, 8);
  const popoverMenuId = $derived(`${id}-${instanceId}`);

  const statusOptions: readonly MediaStatus[] = [
    MEDIA_STATUS.planned,
    MEDIA_STATUS.inProgress,
    MEDIA_STATUS.completed,
    MEDIA_STATUS.onHold,
    MEDIA_STATUS.dropped,
  ];

  const statusMenuItems = $derived(
    statusOptions.map((value) => ({ value, label: statusLabel(value) })),
  );
</script>

<PopoverMenu
  id={popoverMenuId}
  options={statusMenuItems}
  selected={status}
  onSelect={(value) => onSelect(value as MediaStatus)}
  label={i18n.t.status.label}
>
  {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
    <button
      type="button"
      popovertarget={popoverTargetId}
      popovertargetaction="toggle"
      style={isOpen ? `anchor-name: ${anchorName}` : undefined}
      class="tap grid h-[2.33rem] w-[2.33rem] shrink-0 place-items-center rounded-full border bg-[#14171f]/95 p-0 shadow-md transition hover:brightness-125 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-400/70 {statusBadgeClasses(
        status,
      )}"
      title={statusLabel(status)}
      aria-label={statusLabel(status)}
    >
      {#if status === MEDIA_STATUS.planned}
        <Bookmark size={20} stroke-width={2.5} aria-hidden="true" />
      {:else if status === MEDIA_STATUS.inProgress}
        <Play size={20} fill="currentColor" aria-hidden="true" />
      {:else if status === MEDIA_STATUS.completed}
        <Check size={21} stroke-width={3} aria-hidden="true" />
      {:else if status === MEDIA_STATUS.onHold}
        <Pause size={21} stroke-width={2.5} aria-hidden="true" />
      {:else if status === MEDIA_STATUS.dropped}
        <X size={20} stroke-width={4} aria-hidden="true" />
      {/if}
    </button>
  {/snippet}
</PopoverMenu>
