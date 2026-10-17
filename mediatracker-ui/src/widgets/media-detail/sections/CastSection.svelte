<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaDetail } from "$shared/types";
    import { User } from "$shared/ui/Icons.svelte";

    let { media }: { media: MediaDetail } = $props();
    const isAnime = $derived((media.type === "movie" || media.type === "tvshow") && media.isAnime);
    const supported = $derived(media.type === "movie" || media.type === "tvshow");
    const cast = $derived(supported ? (media.cast ?? []).slice(0, 6) : []);
</script>

{#if supported && cast.length > 0}
    <!-- Height follows content: the block is a grid cell of the overview ladder,
         never stretched to match its neighbour. -->
    <section
        class="space-y-3 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
    >
        <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
            {isAnime ? i18n.t.detail.voiceActorsTitle : i18n.t.detail.castTitle}
        </h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {#each cast as member (member.name + member.character)}
                <div class="flex items-center gap-3 p-2.5 rounded-xl border border-white/5 bg-white/[0.03] transition hover:bg-white/[0.06]">
                    {#if member.photoUrl}
                        <img
                            src={member.photoUrl}
                            alt={member.name}
                            loading="lazy"
                            referrerpolicy="no-referrer"
                            class="size-13 shrink-0 rounded-xl object-cover ring-1 ring-white/10"
                        />
                    {:else}
                        <span
                            class="flex size-13 shrink-0 items-center justify-center rounded-xl bg-surface/60 text-muted ring-1 ring-white/10"
                            ><User size={15} /></span
                        >
                    {/if}
                    <div class="min-w-0 flex-1">
                        <p class="truncate text-xs font-bold text-white" title={member.name}>{member.name}</p>
                        {#if member.character}
                            <p class="truncate text-[11px] text-muted" title={member.character}>{member.character}</p>
                        {/if}
                    </div>
                </div>
            {/each}
        </div>
    </section>
{/if}
