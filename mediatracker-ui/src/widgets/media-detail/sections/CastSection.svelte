<script lang="ts">
  import { slide } from "svelte/transition";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { CastMember, MediaDetail } from "$shared/types";
  import { ChevronDown, ChevronUp, User } from "$shared/ui/Icons";
  import { openLightbox } from "$shared/ui/lightbox.svelte";
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

  /** One rendered person, mode-independent: a character (optionally with their seiyu as `sub`). */
  interface CastEntry {
    key: string;
    name: string;
    photoUrl: string | null;
    /** The seiyu's own photo; null for flat (non-voice) payloads. */
    voicePhotoUrl: string | null;
    role: string | null;
    isMain: boolean;
    sub: string | null;
  }

  let supportingCollapsed = $state(false);
  /** Key of the portrait card whose seiyu avatar is hovered: drives the radial reveal. */
  let revealedVoice = $state<string | null>(null);

  // Portrait grid columns. The anti-orphan rule: only whole rows become portrait cards, any
  // remainder flows into the horizontal rows below, so the grid never ends with an empty slot.
  const PORTRAIT_COLS = 3;

  const voiceEntry = (voiceName: string, voicePhotoUrl: string | null, character: CharacterCard): CastEntry => ({
    key: `${voiceName}:${character.name}`,
    name: character.name,
    photoUrl: character.photoUrl,
    voicePhotoUrl,
    role: character.role,
    isMain: character.isMain,
    sub: voiceName,
  });

  const memberEntry = (member: CastDisplay["members"][number]): CastEntry => ({
    key: `${member.name}:${member.photoUrl ?? ""}`,
    name: member.name,
    photoUrl: member.photoUrl,
    voicePhotoUrl: null,
    role: member.role,
    isMain: member.isMain,
    // A flat row already shows the part as the role badge; repeating it as text is noise.
    sub: member.sub && member.sub !== member.role ? member.sub : null,
  });

  // Main characters first, largest: voice mode takes the mains of every seiyu (the seiyu name
  // rides along as the secondary line), flat modes take the members flagged MAIN.
  const mainPool = $derived.by((): CastEntry[] => {
    if (!display) return [];
    if (display.voiceMode) {
      const entries: CastEntry[] = [];
      for (const voice of display.voices) {
        for (const character of voice.characters) {
          if (character.isMain) entries.push(voiceEntry(voice.name, voice.photoUrl, character));
        }
      }
      for (const member of display.members) {
        if (member.isMain) entries.push(memberEntry(member));
      }
      return entries;
    }
    return display.members.filter((member) => member.isMain).map(memberEntry);
  });

  const portraitEntries = $derived(
    mainPool.slice(0, Math.floor(mainPool.length / PORTRAIT_COLS) * PORTRAIT_COLS),
  );
  const overflowEntries = $derived(mainPool.slice(portraitEntries.length));

  // Everything secondary: supporting characters (with their seiyu in voice mode) and the
  // not-marked-main members of flat payloads. This is what the chevron collapses.
  const supportingEntries = $derived.by((): CastEntry[] => {
    if (!display) return [];
    const entries: CastEntry[] = [];
    if (display.voiceMode) {
      for (const voice of display.voices) {
        for (const character of voice.characters) {
          if (!character.isMain) entries.push(voiceEntry(voice.name, voice.photoUrl, character));
        }
      }
    }
    for (const member of display.members) {
      if (!member.isMain) entries.push(memberEntry(member));
    }
    return entries;
  });

  const hasSupporting = $derived(supportingEntries.length > 0);
  /** Voice payload present: rows render as balanced character↔seiyu pairs. */
  const hasVoiceActors = $derived(display?.voiceMode === true);

  // Role chips: the main role gets the accent treatment so "Главный" stops blending in.
  const badgeClass = (isMain: boolean): string =>
    isMain
      ? "inline-flex items-center rounded-md border border-accent/30 bg-accent/15 px-1.5 py-0.5 text-[10px] font-semibold text-accent-soft"
      : "inline-flex items-center rounded-md border border-white/10 bg-white/[0.04] px-1.5 py-0.5 text-[10px] font-medium text-slate-400";
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
      <div class="flex items-center gap-1.5">
        {#if hasSupporting}
          <!-- Bare collapse chevron: no background, no border, no fill — just the icon. -->
          <button
            type="button"
            class="grid size-7 cursor-pointer place-items-center rounded-md text-slate-300 transition hover:text-white"
            title={supportingCollapsed
              ? i18n.t.detail.showSupporting
              : i18n.t.detail.hideSupporting}
            aria-label={supportingCollapsed
              ? i18n.t.detail.showSupporting
              : i18n.t.detail.hideSupporting}
            aria-expanded={!supportingCollapsed}
            onclick={() => (supportingCollapsed = !supportingCollapsed)}
          >
            <ChevronUp
              size={15}
              class="transition-transform duration-200 {supportingCollapsed ? 'rotate-180' : ''}"
              aria-hidden="true"
            />
          </button>
        {/if}
        <PeopleSizeToggle category={categoryKey} block="cast" />
      </div>
    </div>

    {#if portraitEntries.length}
      <!-- Main characters as vertical portrait cards, whole rows only (anti-orphan rule).
           The seiyu's own photo rides in the portrait's bottom-right corner. -->
      <div class="grid grid-cols-3 gap-3">
        {#each portraitEntries as entry (entry.key)}
          <div
            class="flex flex-col overflow-hidden rounded-xl border border-white/[0.06] bg-white/[0.03] transition hover:border-white/10 hover:bg-white/[0.05]"
          >
            <div class="relative">
              {#if entry.photoUrl}
                <button
                  type="button"
                  class="block aspect-[2/3] w-full cursor-pointer border-0 bg-transparent p-0 text-left"
                  onclick={() => openLightbox(entry.photoUrl, entry.name)}
                  aria-label={`Увеличить фото: ${entry.name}`}
                >
                  <img
                    src={entry.photoUrl}
                    alt={entry.name}
                    loading="lazy"
                    referrerpolicy="no-referrer"
                    class="h-full w-full object-cover object-top"
                  />
                </button>
              {:else}
                <span
                  class="bg-surface/60 text-muted flex aspect-[2/3] w-full items-center justify-center"
                  ><User size={20} /></span
                >
              {/if}
              {#if entry.voicePhotoUrl}
                <!-- Radial reveal of the seiyu's own photo: unfolds from the avatar corner
                     while hovered. The overlay never catches the pointer, the avatar itself
                     is the trigger and opens the actor's photo in the lightbox. -->
                <img
                  src={entry.voicePhotoUrl}
                  alt={entry.sub ?? ""}
                  loading="lazy"
                  referrerpolicy="no-referrer"
                  class={`seiyu-reveal pointer-events-none absolute inset-0 h-full w-full object-cover ${
                    revealedVoice === entry.key ? "revealed" : ""
                  }`}
                />
                <button
                  type="button"
                  class="absolute right-2 bottom-2 z-20 size-9 cursor-pointer rounded-full ring-2 ring-[#12151c] transition-transform hover:scale-105"
                  title={entry.sub ?? ""}
                  aria-label={`Увеличить фото: ${entry.sub ?? ""}`}
                  onpointerenter={() => (revealedVoice = entry.key)}
                  onpointerleave={() => (revealedVoice = null)}
                  onfocus={() => (revealedVoice = entry.key)}
                  onblur={() => (revealedVoice = null)}
                  onclick={(e) => {
                    e.stopPropagation();
                    openLightbox(entry.voicePhotoUrl, entry.sub);
                  }}
                >
                  <img
                    src={entry.voicePhotoUrl}
                    alt={entry.sub ?? ""}
                    loading="lazy"
                    referrerpolicy="no-referrer"
                    class="pointer-events-none size-full rounded-full object-cover"
                  />
                </button>
              {:else if entry.sub}
                <span
                  class="bg-surface text-muted absolute right-2 bottom-2 grid size-9 place-items-center rounded-full ring-2 ring-[#12151c]"
                  title={entry.sub}><User size={14} /></span
                >
              {/if}
            </div>
            <div class="min-w-0 space-y-1 p-2">
              <p
                class="line-clamp-2 text-xs {large ? 'sm:text-[13px]' : ''} leading-snug font-bold text-white"
                title={entry.name}
              >
                {entry.name}
              </p>
              {#if entry.sub}
                <p class="text-muted truncate text-[10px]" title={entry.sub}>{entry.sub}</p>
              {/if}
              {#if entry.role}
                <span class={badgeClass(entry.isMain)}>{entry.role}</span>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}

    {#snippet rowEntry(entry: CastEntry)}
      <div class="flex items-center gap-3 {large ? 'py-2.5' : 'py-2'}">
        {#if entry.photoUrl}
          <button
            type="button"
            class="shrink-0 cursor-pointer border-0 bg-transparent p-0 text-left"
            onclick={() => openLightbox(entry.photoUrl, entry.name)}
            aria-label={`Увеличить фото: ${entry.name}`}
          >
            <img
              src={entry.photoUrl}
              alt={entry.name}
              loading="lazy"
              referrerpolicy="no-referrer"
              class="{large
                ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                : 'size-13 sm:size-14'} shrink-0 rounded-lg object-cover ring-1 ring-white/10"
            />
          </button>
        {:else}
          <span
            class="{large
              ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
              : 'size-13 sm:size-14'} bg-surface/60 text-muted flex shrink-0 items-center justify-center rounded-lg ring-1 ring-white/10"
            ><User size={15} /></span
          >
        {/if}
        <div class="min-w-0 flex-1">
          <p
            class="{large
              ? 'text-sm'
              : 'text-xs sm:text-[13px]'} line-clamp-2 leading-snug font-bold text-white"
            title={entry.name}
          >
            {entry.name}
          </p>
          {#if entry.role}
            <span class="mt-1 max-w-full {badgeClass(entry.isMain)}">{entry.role}</span>
          {/if}
        </div>
        {#if entry.sub}
          <!-- Balanced pair: the seiyu rides on the right with their own portrait. -->
          <div class="ml-auto flex shrink-0 items-center gap-3 text-right">
            <div class="min-w-0">
              <p
                class="{large
                  ? 'text-sm'
                  : 'text-xs sm:text-[13px]'} line-clamp-2 leading-snug font-bold text-white"
                title={entry.sub}
              >
                {entry.sub}
              </p>
              <p class="text-muted text-[10px] font-semibold tracking-wider uppercase">
                {i18n.current === "ru" ? "сэйю" : "voice"}
              </p>
            </div>
            {#if entry.voicePhotoUrl}
              <button
                type="button"
                class="shrink-0 cursor-pointer border-0 bg-transparent p-0 text-left"
                onclick={(e) => {
                  e.stopPropagation();
                  openLightbox(entry.voicePhotoUrl, entry.sub);
                }}
                aria-label={`Увеличить фото: ${entry.sub ?? ""}`}
              >
                <img
                  src={entry.voicePhotoUrl}
                  alt={entry.sub ?? ""}
                  loading="lazy"
                  referrerpolicy="no-referrer"
                  class="{large
                    ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                    : 'size-13 sm:size-14'} shrink-0 rounded-lg object-cover ring-1 ring-white/10"
                />
              </button>
            {:else}
              <span
                class="{large
                  ? 'h-20 w-16 shadow-md sm:h-24 sm:w-20'
                  : 'size-13 sm:size-14'} bg-surface/60 text-muted flex shrink-0 items-center justify-center rounded-lg ring-1 ring-white/10"
                title={entry.sub}><User size={15} /></span
              >
            {/if}
          </div>
        {/if}
      </div>
    {/snippet}

    {#if overflowEntries.length || supportingEntries.length}
      {#if hasVoiceActors}
        <!-- Anime rows: balanced character (left) and seiyu (right) pair, hairline dividers. -->
        <div class="divide-y divide-white/[0.05]">
          {#each overflowEntries as entry (entry.key)}
            {@render rowEntry(entry)}
          {/each}
        </div>
        {#if !supportingCollapsed}
          <div
            transition:slide={{ duration: 220 }}
            class={`divide-y divide-white/[0.05] ${overflowEntries.length ? 'border-t border-white/[0.05]' : ''}`}
          >
            {#each supportingEntries as entry (entry.key)}
              {@render rowEntry(entry)}
            {/each}
          </div>
        {/if}
      {:else}
        <!-- Flat payloads (manga, books): two compact columns, no dead space on the right. -->
        <div class="grid grid-cols-1 gap-x-6 gap-y-2 md:grid-cols-2">
          {#each overflowEntries as entry (entry.key)}
            {@render rowEntry(entry)}
          {/each}
          {#if !supportingCollapsed}
            <div
              transition:slide={{ duration: 220 }}
              class="grid grid-cols-1 gap-x-6 gap-y-2 md:col-span-2 md:grid-cols-2"
            >
              {#each supportingEntries as entry (entry.key)}
                {@render rowEntry(entry)}
              {/each}
            </div>
          {/if}
        </div>
      {/if}
    {/if}
  </section>
{/if}

<style>
  /* Radial clip-path reveal of the seiyu photo on portrait cards: unfolds from the
     avatar corner. Composited properties only (clip-path + opacity), no shadows. */
  .seiyu-reveal {
    clip-path: circle(0% at calc(100% - 28px) calc(100% - 28px));
    opacity: 0;
    transition:
      clip-path 320ms cubic-bezier(0.16, 1, 0.3, 1),
      opacity 200ms ease;
  }

  .seiyu-reveal.revealed {
    clip-path: circle(150% at calc(100% - 28px) calc(100% - 28px));
    opacity: 1;
  }
</style>
