<script lang="ts">
    interface Props {
        label: string;
    }

    let { label }: Props = $props();
</script>

<div class="space-y-3" aria-hidden="true">
    {#each [0, 1, 2] as row (row)}
        <div
            class="flex animate-pulse items-center gap-3 rounded-lg border border-white/[0.06] bg-card p-3 {row ===
            1
                ? 'opacity-80'
                : ''}"
        >
            <div class="h-12 w-9 shrink-0 rounded-md bg-white/[0.06]"></div>
            <div class="min-w-0 flex-1 space-y-2">
                <div
                    class="h-3 rounded bg-white/[0.08]"
                    style={`width:${88 - row * 16}%`}
                ></div>
                <div
                    class="h-2.5 w-2/5 rounded bg-white/[0.05]"
                ></div>
            </div>
        </div>
    {/each}
</div>
<p class="sr-only" role="status">{label}</p>