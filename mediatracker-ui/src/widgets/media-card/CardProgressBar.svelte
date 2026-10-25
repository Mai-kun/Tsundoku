<script lang="ts">
    interface Props {
        label: string;
        /** 0..1, or null when the total is unknown and no bar can be drawn. */
        ratio: number | null;
        /** Keeps the stepper below from shifting when no bar is rendered. */
        reserveSpace?: boolean;
    }

    let { label, ratio, reserveSpace = false }: Props = $props();
</script>

<div class="space-y-1.5 flex items-center justify-between gap-2 text-xs text-muted">
    <span>{label}</span>
</div>
