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
    <section class="space-y-3">
        <h2 class="text-sm font-semibold text-ink">{isAnime ? i18n.t.detail.voiceActorsTitle : i18n.t.detail.castTitle}</h2>
        <div class="flex gap-3 overflow-x-auto pb-1">
            {#each cast as member (member.name + member.character)}
                <article class="flex w-24 shrink-0 flex-col items-center gap-1.5 text-center">
                    {#if member.photoUrl}
                        <img src={member.photoUrl} alt={member.name} loading="lazy" class="size-12 rounded-full border border-white/10 object-cover" />
                    {:else}
                        <span class="flex size-12 items-center justify-center rounded-full border border-white/10 bg-surface/60 text-muted"><User size={20} /></span>
                    {/if}
                    <span class="w-full truncate text-xs font-semibold text-white" title={member.name}>{member.name}</span>
                    {#if member.character}<span class="w-full truncate text-[11px] text-muted" title={member.character}>{member.character}</span>{/if}
                </article>
            {/each}
        </div>
    </section>
{/if}
