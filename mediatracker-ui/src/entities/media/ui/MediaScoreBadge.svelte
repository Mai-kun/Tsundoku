<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import { formatNumber } from "$entities/media/model/mediaLabels";

    interface Props {
        score: number | null;
    }

    let { score }: Props = $props();
</script>

{#if score !== null && score > 0}
    <div
        class="relative z-10 -ml-2 grid h-[2.33rem] w-[2.33rem] place-items-center rounded-full bg-score-bg text-[17px] font-black tabular-nums tracking-tight text-white shadow-lg select-none"
        title={`${i18n.t.createModal.fields.score}: ${score}`}
    >
        {formatNumber(score)}
    </div>
{/if}