<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import type { CastMember, MediaDetail } from "$shared/types";
  import { User } from "$shared/ui/Icons";
  import ImageLightbox from "$shared/ui/ImageLightbox.svelte";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import PeopleSizeToggle from "./PeopleSizeToggle.svelte";

  let { media }: { media: MediaDetail } = $props();

  const cast = $derived(media.cast ?? []);
  // Anime live-action types count as the anime category: they share the same payload shape.
  const categoryKey = $derived(
    (media.type === "tvshow" || media.type === "movie") && media.isAnime ? "anime" : media.type,
  );
  const large = $derived(uiSettings.getCastSize(categoryKey) === "large");
  const isAnime = $derived((media.type === "movie" || media.type === "tvshow") && media.isAnime);
  const isManga = $derived(media.type === "manga");

  interface CharacterCard {
    name: string;
    photoUrl: string | null;
    role: string | null;
    isMain: boolean;
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
    members: Array<CharacterCard & { photoUrl: string | null; sub: string | null }>;
  }

  const display = $derived.by((): CastDisplay | null => {
    if (cast.length === 0) return null;

    const isMainRole = (raw?: string | null): boolean => raw?.trim().toUpperCase() === "MAIN";
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
          isMain: isMainRole(member.characterRole),
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
      return {
        title: i18n.t.detail.voiceActorsTitle,
        voiceMode: true,
        voices,
        members: headless.map((c) => ({ ...c, sub: c.role })),
      };
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
          isMain: isMainRole(member.characterRole),
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
        isMain: false,
        sub: member.character,
      })),
    };
  });

  // Role chips: the main role gets the accent treatment so "Главный" stops blending in.
  const badgeClass = (isMain: boolean): string =>
    isMain
      ? "inline-flex items-center rounded-md border border-accent/30 bg-accent/15 px-1.5 py-0.5 text-[10px] font-semibold text-accent-soft"
      : "inline-flex items-center rounded-md border border-white/10 bg-white/[0.04] px-1.5 py-0.5 text-[10px] font-medium text-slate-400";

  let activeLightboxUrl = $state<string | null>(null);
</script>

{#if display}
  <!-- Height follows content: the block is a grid cell of the overview ladder,
         never stretched to match its neighbour. -->
  <section
    class="space-y-3 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
  >
    <div class="flex items-center justify-between gap-2">
      <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
        {display.title}
      </h2>
      <PeopleSizeToggle category={categoryKey} block="cast" />
    </div>

    {#if display.voiceMode}
      <!-- Voice cards are already two people wide (voice left, characters right),
                 so one full-width column keeps both names unclipped. -->
      <div class="grid grid-cols-1 gap-3">
        {#each display.voices as voice (voice.name)}
          <div
            class="flex items-center justify-between gap-3 rounded-xl border border-white/[0.06] bg-white/[0.03] transition hover:border-white/10 hover:bg-white/[0.06] sm:gap-4 {large
              ? 'p-3.5'
              : 'p-2.5'}"
          >
            <!-- Voice actor, pinned to the left edge. -->
            <div class="flex min-w-0 flex-1 items-center gap-3">
              {#if voice.photoUrl}
                <button
                  type="button"
                  class="shrink-0 cursor-pointer border-0 bg-transparent p-0 text-left"
                  onclick={() => (activeLightboxUrl = voice.photoUrl)}
                  aria-label={`Увеличить фото: ${voice.name}`}
                >
                  <img
                    src={voice.photoUrl}
                    alt={voice.name}
                    loading="lazy"
                    referrerpolicy="no-referrer"
                    class="{large
                      ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                      : 'size-13 sm:size-14'} shrink-0 rounded-xl object-cover ring-1 ring-white/10"
                  />
                </button>
              {:else}
                <span
                  class="{large
                    ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                    : 'size-13 sm:size-14'} bg-surface/60 text-muted flex shrink-0 items-center justify-center rounded-xl ring-1 ring-white/10"
                  ><User size={15} /></span
                >
              {/if}
              <div class="min-w-0 flex-1">
                <p
                  class="{large
                    ? 'text-sm'
                    : 'text-xs sm:text-[13px]'} line-clamp-2 leading-snug font-bold text-white"
                  title={voice.name}
                >
                  {voice.name}
                </p>
                <p class="text-muted mt-1 block text-[10px] font-semibold tracking-wider uppercase">
                  {i18n.current === "ru" ? "Сэйю" : "Voice Actor"}
                </p>
              </div>
            </div>

            <!-- Middle arrow: the visual "dubs" mark between the two halves. -->
            <span
              class="text-muted grid shrink-0 place-items-center rounded-full border border-white/[0.08] bg-white/[0.04] text-xs {large
                ? 'size-8'
                : 'size-6'}"
              aria-hidden="true">→</span
            >

            <!-- Dubbed characters, pinned to the right edge. -->
            <div class="flex min-w-0 flex-1 flex-col items-end gap-2">
              {#each voice.characters as character (character.name)}
                <div class="flex w-full items-center justify-end gap-3 text-right">
                  <div class="min-w-0 flex-1">
                    <p
                      class="{large
                        ? 'text-sm'
                        : 'text-xs sm:text-[13px]'} line-clamp-2 leading-snug font-bold text-[var(--color-accent-soft)]"
                      title={character.name}
                    >
                      {character.name}
                    </p>
                    {#if character.role}
                      <span class="mt-1 max-w-full {badgeClass(character.isMain)}"
                        >{character.role}</span
                      >
                    {/if}
                  </div>
                  {#if character.photoUrl}
                    <button
                      type="button"
                      class="shrink-0 cursor-pointer border-0 bg-transparent p-0 text-left"
                      onclick={() => (activeLightboxUrl = character.photoUrl)}
                      aria-label={`Увеличить фото: ${character.name}`}
                    >
                      <img
                        src={character.photoUrl}
                        alt={character.name}
                        loading="lazy"
                        referrerpolicy="no-referrer"
                        class="{large
                          ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                          : 'size-13 sm:size-14'} shrink-0 rounded-xl object-cover ring-1 ring-white/10"
                      />
                    </button>
                  {:else}
                    <span
                      class="{large
                        ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                        : 'size-13 sm:size-14'} bg-surface/60 text-muted flex shrink-0 items-center justify-center rounded-xl ring-1 ring-white/10"
                      ><User size={13} /></span
                    >
                  {/if}
                </div>
              {/each}
            </div>
          </div>
        {/each}
      </div>
    {:else}
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        {#each display.members as member (member.name + member.photoUrl)}
          <div
            class="flex items-center gap-3.5 rounded-xl border border-white/[0.06] bg-white/[0.03] transition hover:border-white/10 hover:bg-white/[0.06] {large
              ? 'p-3.5'
              : 'p-2.5'}"
          >
            {#if member.photoUrl}
              <button
                type="button"
                class="shrink-0 cursor-pointer border-0 bg-transparent p-0 text-left"
                onclick={() => (activeLightboxUrl = member.photoUrl)}
                aria-label={`Увеличить фото: ${member.name}`}
              >
                <img
                  src={member.photoUrl}
                  alt={member.name}
                  loading="lazy"
                  referrerpolicy="no-referrer"
                  class="{large
                    ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                    : 'size-13 sm:size-14'} shrink-0 rounded-xl object-cover ring-1 ring-white/10"
                />
              </button>
            {:else}
              <span
                class="{large
                  ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                  : 'size-13 sm:size-14'} bg-surface/60 text-muted flex shrink-0 items-center justify-center rounded-xl ring-1 ring-white/10"
                ><User size={15} /></span
              >
            {/if}
            <div class="min-w-0 flex-1">
              <p
                class="{large
                  ? 'text-sm'
                  : 'text-xs sm:text-[13px]'} line-clamp-2 leading-snug font-bold text-white"
                title={member.name}
              >
                {member.name}
              </p>
              {#if member.sub}
                <span class="mt-1.5 max-w-full {badgeClass(member.isMain)}">{member.sub}</span>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
  </section>
{/if}

<ImageLightbox url={activeLightboxUrl} onclose={() => (activeLightboxUrl = null)} />
