<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { CastMember, MediaDetail } from "$shared/types";
    import { User } from "$shared/ui/Icons.svelte";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import PeopleSizeToggle from "./PeopleSizeToggle.svelte";

    let { media }: { media: MediaDetail } = $props();

    const cast = $derived(media.cast ?? []);
    const large = $derived(uiSettings.peopleCardSize === "large");
    const isAnime = $derived(
        (media.type === "movie" || media.type === "tvshow") && media.isAnime,
    );
    const isManga = $derived(media.type === "manga");

    interface CharacterCard {
        name: string;
        photoUrl: string | null;
        role: string | null;
    }

    interface CastDisplay {
        title: string;
        /** Voice-actor mode: actors with the characters they dub. Otherwise flat character rows. */
        voiceMode: boolean;
        voices: Array<{
            name: string;
            photoUrl: string | null;
            characters: CharacterCard[];
        }>;
        members: Array<
            CharacterCard & { photoUrl: string | null; sub: string | null }
        >;
    }

    const display = $derived.by((): CastDisplay | null => {
        if (cast.length === 0) return null;

        const roleLabel = (raw?: string | null): string | null => {
            const value = raw?.trim().toUpperCase();
            if (value === "MAIN") return i18n.t.detail.roleMain;
            if (value === "SUPPORTING") return i18n.t.detail.roleSupporting;
            return raw?.trim() || null;
        };

        // Anime with the new payload: group by the Japanese voice actor.
        if (isAnime && cast.some((member) => member.voiceActorName?.trim())) {
            const voices: CastDisplay["voices"] = [];
            const byName = new Map<string, (typeof voices)[number]>();
            const headless: CharacterCard[] = [];
            for (const member of cast) {
                const character: CharacterCard = {
                    name: member.character ?? member.name,
                    photoUrl: member.characterImageUrl ?? member.photoUrl,
                    role: roleLabel(member.characterRole),
                };
                const vaName = member.voiceActorName?.trim();
                if (!vaName) {
                    headless.push(character);
                    continue;
                }
                let voice = byName.get(vaName);
                if (!voice) {
                    voice = {
                        name: vaName,
                        photoUrl: member.voiceActorImageUrl ?? member.photoUrl,
                        characters: [],
                    };
                    byName.set(vaName, voice);
                    voices.push(voice);
                }
                voice.characters.push(character);
            }
            return { title: i18n.t.detail.voiceActorsTitle, voiceMode: true, voices, members: headless.map((c) => ({ ...c, sub: c.role })) };
        }

        // Manga (and any payload that stores pure characters): one card per character.
        if (isManga) {
            return {
                title: i18n.t.detail.charactersTitle,
                voiceMode: false,
                voices: [],
                members: cast.map((member) => ({
                    name: member.character ?? member.name,
                    photoUrl: member.characterImageUrl ?? member.photoUrl,
                    role: roleLabel(member.characterRole),
                    sub: roleLabel(member.characterRole) ?? member.name,
                })),
            };
        }

        // Legacy flat layout: live-action rows keep "actor + the part they played".
        return {
            title: i18n.t.detail.castTitle,
            voiceMode: false,
            voices: [],
            members: cast.map((member) => ({
                name: member.name,
                photoUrl: member.photoUrl,
                role: member.character,
                sub: member.character,
            })),
        };
    });
</script>

{#if display}
    <!-- Height follows content: the block is a grid cell of the overview ladder,
         never stretched to match its neighbour. -->
    <section
        class="space-y-3 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
    >
        <div class="flex items-center justify-between gap-2">
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {display.title}
            </h2>
            <PeopleSizeToggle />
        </div>

        {#if display.voiceMode}
            <!-- Voice actor ← character: the actor sits left, the dubbed characters right. -->
            <div class={large ? "grid grid-cols-1 gap-3" : "grid grid-cols-1 gap-3 sm:grid-cols-2"}>
                {#each display.voices as voice (voice.name)}
                    <div
                        class="flex items-center gap-3 border border-white/5 bg-white/[0.03] rounded-xl p-2.5 transition hover:bg-white/[0.06]"
                    >
                        {#if voice.photoUrl}
                            <img
                                src={voice.photoUrl}
                                alt={voice.name}
                                loading="lazy"
                                referrerpolicy="no-referrer"
                                class="{large
                                    ? "w-16 h-20 sm:w-20 sm:h-24 shadow-md"
                                    : "size-12"} shrink-0 rounded-xl object-cover ring-1 ring-white/10"
                            />
                        {:else}
                            <span
                                class="{large
                                    ? "w-16 h-20 sm:w-20 sm:h-24 shadow-md"
                                    : "size-12"} flex shrink-0 items-center justify-center rounded-xl bg-surface/60 text-muted ring-1 ring-white/10"
                                ><User size={15} /></span
                            >
                        {/if}
                        <div class="min-w-0 flex-1">
                            <p
                                class="{large
                                    ? 'text-sm leading-snug line-clamp-2'
                                    : 'truncate text-xs'} font-bold text-white"
                                title={voice.name}
                            >
                                {voice.name}
                            </p>
                            <div class={large ? "flex flex-col gap-2" : "flex flex-wrap gap-2"}>
                                {#each voice.characters as character (character.name)}
                                    <div class="flex items-center gap-2">
                                        <span class="text-muted text-xs" aria-hidden="true"
                                            >→</span
                                        >
                                        {#if character.photoUrl}
                                            <img
                                                src={character.photoUrl}
                                                alt={character.name}
                                                loading="lazy"
                                                referrerpolicy="no-referrer"
                                                class="{large
                                                    ? 'w-16 h-20 shadow-md'
                                                    : 'size-10'} shrink-0 rounded-lg object-cover ring-1 ring-white/10"
                                            />
                                        {:else}
                                            <span
                                                class="{large
                                                    ? 'w-16 h-20 rounded-xl'
                                                    : 'size-10 rounded-lg'} flex shrink-0 items-center justify-center bg-surface/60 text-muted ring-1 ring-white/10"
                                                ><User size={13} /></span
                                            >
                                        {/if}
                                        <span class="min-w-0">
                                            <span
                                                class="{large
                                                    ? 'text-sm leading-snug line-clamp-2'
                                                    : 'block truncate text-xs'} font-semibold text-[var(--color-accent-soft)]"
                                                title={character.name}
                                                >{character.name}</span
                                            >
                                            {#if character.role}
                                                <span
                                                    class="{large
                                                        ? 'block text-xs leading-snug line-clamp-2'
                                                        : 'block truncate text-[11px]'} text-muted"
                                                    >{character.role}</span
                                                >
                                            {/if}
                                        </span>
                                    </div>
                                {/each}
                            </div>
                        </div>
                    </div>
                {/each}
            </div>
        {:else}
            <div class={large ? "grid grid-cols-1 gap-3" : "grid grid-cols-1 gap-3 sm:grid-cols-2"}>
                {#each display.members as member (member.name + member.photoUrl)}
                    <div
                        class="flex items-center gap-3 border border-white/5 bg-white/[0.03] rounded-xl p-2.5 transition hover:bg-white/[0.06]"
                    >
                        {#if member.photoUrl}
                            <img
                                src={member.photoUrl}
                                alt={member.name}
                                loading="lazy"
                                referrerpolicy="no-referrer"
                                class="{large
                                    ? 'w-16 h-20 sm:w-20 sm:h-24 shadow-md'
                                    : 'size-13'} shrink-0 rounded-xl object-cover ring-1 ring-white/10"
                            />
                        {:else}
                            <span
                                class="{large
                                    ? 'w-16 h-20 sm:w-20 sm:h-24 shadow-md'
                                    : 'size-13'} flex shrink-0 items-center justify-center rounded-xl bg-surface/60 text-muted ring-1 ring-white/10"
                                ><User size={15} /></span
                            >
                        {/if}
                        <div class="min-w-0 flex-1">
                            <p
                                class="{large
                                    ? 'text-sm leading-snug line-clamp-2'
                                    : 'truncate text-xs'} font-bold text-white"
                                title={member.name}
                            >
                                {member.name}
                            </p>
                            {#if member.sub}
                                <p
                                    class="{large
                                        ? 'text-xs font-medium mt-1'
                                        : 'truncate text-[11px]'} text-muted"
                                    title={member.sub}
                                >
                                    {member.sub}
                                </p>
                            {/if}
                        </div>
                    </div>
                {/each}
            </div>
        {/if}
    </section>
{/if}
