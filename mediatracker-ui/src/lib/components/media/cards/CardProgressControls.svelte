<script lang="ts">
    import { errorMessage } from "$lib/api";
    import MediaProgressStepper from "../atoms/MediaProgressStepper.svelte";
    import { formatNumber } from "../mediaLabels";
    import type { CardProgressState } from "./cardProgress.svelte";

    interface Props {
        progress: CardProgressState;
    }

    let { progress }: Props = $props();
</script>

<MediaProgressStepper
    text={formatNumber(progress.value)}
    onStep={(delta) => progress.step(delta)}
/>

{#if progress.error}
    <p class="text-xs leading-4 text-rose-300" role="alert">
        {errorMessage(progress.error)}
    </p>
{/if}