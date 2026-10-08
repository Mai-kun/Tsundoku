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
        <div class="grid grid-cols-3 gap-2.5">
            {#each cast as member (member.name + member.character)}
                <div class="flex min-w-0 items-center gap-2">
                    {#if member.photoUrl}
                        <img
                            src={member.photoUrl}
                            alt={member.name}
                            loading="lazy"
                            referrerpolicy="no-referrer"
                            class="size-9 shrink-0 rounded-full border border-white/10 object-cover"
                        />
                    {:else}
                        <span
                            class="flex size-9 shrink-0 items-center justify-center rounded-full border border-white/10 bg-surface/60 text-muted"
                            ><User size={15} /></span
                        >
                    {/if}
                    <div class="min-w-0 flex-1">
                        <p class="truncate text-xs font-semibold text-white" title={member.name}>
                            {member.name}
                        </p>
                        {#if member.character}
                            <p class="truncate text-[10px] text-muted" title={member.character}>
                                {member.character}
                            </p>
                        {/if}
                    </div>
                </div>
            {/each}
        </div>
    </section>
{/if}
