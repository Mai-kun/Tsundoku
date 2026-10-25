<script lang="ts">
    import {
        Archive,
        Bookmark,
        BookOpen,
        Boxes,
        Clapperboard,
        Compass,
        Film,
        Flame,
        Gamepad2,
        Heart,
        Layers,
        ListChecks,
        Scale,
        Sparkles,
        Tv,
    } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { TastePersona } from "$shared/types";

    interface Props {
        persona: TastePersona;
    }

    let { persona }: Props = $props();

    const ICONS: Record<string, typeof Sparkles> = {
        critic: Scale,
        enthusiast: Sparkles,
        perfectionist: ListChecks,
        tsundoku_master: Boxes,
        manga_reader: BookOpen,
        otaku: Tv,
        gamer: Gamepad2,
        bookworm: Bookmark,
        cinephile: Film,
        serial_binger: Clapperboard,
        dark_philosopher: Compass,
        cozy_hedonist: Heart,
        action_junkie: Flame,
        visionary: Compass,
        omnivore: Layers,
        archivist: Archive,
    };

    type PersonaKeys = keyof typeof i18n.t.stats.taste.personas;

    const copy = $derived(i18n.t.stats.taste.personas[persona.icon as PersonaKeys] ?? null);
    const title = $derived(copy?.title ?? persona.title);
    const description = $derived(copy?.description ?? persona.description);
    const Icon = $derived(ICONS[persona.icon] ?? Sparkles);

    function traitLabel(trait: string): string {
        return i18n.t.stats.taste.traits[trait as keyof typeof i18n.t.stats.taste.traits] ?? trait;
    }

    const traits = $derived<string[]>(
        copy?.traits ?? persona.traits.map(traitLabel)
    );
</script>

<div
    class="relative overflow-hidden rounded-xl border border-[#5844e0]/25 bg-gradient-to-br from-[#5844e0]/25 via-[#151a26] to-[#151a26] p-6"
>
    <div class="pointer-events-none absolute -top-16 -right-16 size-56 rounded-full bg-[#5844e0]/30 blur-3xl" aria-hidden="true"></div>
    <div class="pointer-events-none absolute -bottom-20 -left-10 size-40 rounded-full bg-amber-400/10 blur-3xl" aria-hidden="true"></div>
    <div class="relative flex flex-col items-center gap-5 text-center sm:flex-row sm:items-start sm:text-left">
        <div class="flex size-20 shrink-0 items-center justify-center rounded-2xl bg-[#5844e0]/30 ring-1 ring-white/10">
            <Icon class="size-10 text-white drop-shadow" aria-hidden="true" />
        </div>
        <div class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-widest text-[#a5b4fc]">{i18n.t.stats.taste.personaBadge}</p>
            <h2 class="mt-1 text-2xl font-bold tracking-tight text-white">{title}</h2>
            <p class="mt-2 max-w-2xl text-sm leading-relaxed text-slate-300">{description}</p>
            <div class="mt-4 flex flex-wrap justify-center gap-2 sm:justify-start">
                {#each traits as trait (trait)}
                    <span class="rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-medium text-slate-200">
                        {trait}
                    </span>
                {/each}
            </div>
        </div>
    </div>
</div>
