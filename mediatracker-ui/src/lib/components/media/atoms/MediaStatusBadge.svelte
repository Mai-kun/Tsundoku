<script lang="ts">
    import Bookmark from "lucide-svelte/icons/bookmark";
    import Check from "lucide-svelte/icons/check";
    import Pause from "lucide-svelte/icons/pause";
    import Play from "lucide-svelte/icons/play";
    import X from "lucide-svelte/icons/x";
    import { i18n } from "$lib/i18n/index.svelte";
    import { MEDIA_STATUS, type MediaStatus } from "$lib/types";
    import PopoverMenu from "$lib/components/common/PopoverMenu.svelte";
    import { statusBadgeClasses, statusLabel } from "../mediaLabels";

    interface Props {
        id: string;
        status: MediaStatus;
        onSelect: (status: MediaStatus) => void;
    }

    let { id, status, onSelect }: Props = $props();

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
    {id}
    options={statusMenuItems}
    selected={status}
    onSelect={(value) => onSelect(value as MediaStatus)}
    label={i18n.t.status.label}
>
    {#snippet trigger({ popoverTargetId, anchorName })}
        <button
            type="button"
            popovertarget={popoverTargetId}
            popovertargetaction="toggle"
            style="anchor-name: {anchorName}"
            class="tap grid h-[2.33rem] w-[2.33rem] shrink-0 place-items-center p-0 rounded-full border shadow-lg backdrop-blur transition hover:brightness-125 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-400/70 {statusBadgeClasses(
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