<script lang="ts">
    import { errorMessage } from "$shared/api/api";
    import MediaStepper from "$entities/media/ui/MediaStepper.svelte";
    import { formatNumber } from "$entities/media/model/mediaLabels";
    import type { CardProgressState } from "$features/update-progress/progressController.svelte";

    interface Props {
        progress: CardProgressState;
    }

    let { progress }: Props = $props();
</script>

<MediaStepper
    text={formatNumber(progress.value)}
    onStep={(delta) => progress.step(delta)}
/>

{#if progress.error}
    <p class="text-xs leading-4 text-rose-300" role="alert">
        {errorMessage(progress.error)}
    </p>
{/if}