<script lang="ts">
  import Minus from 'lucide-svelte/icons/minus'
  import Plus from 'lucide-svelte/icons/plus'
  import X from 'lucide-svelte/icons/x'
  import { createMedia, errorMessage, updateMedia } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import {
    MEDIA_STATUS,
    type CreateMediaPayload,
    type CreateSeasonPayload,
    type MediaItem,
    type MediaStatus,
    type MediaType,
    type UpdateMediaPayload,
  } from '$lib/types'

  type CreateType = MediaType

  interface SeasonDraft {
    seasonNumber: string
    title: string
    totalEpisodes: string
  }

  interface Props {
    isOpen: boolean
    onClose: () => void
    onCreated: (media: MediaItem) => void
    editingItem?: MediaItem
  }

  let { isOpen, onClose, onCreated, editingItem }: Props = $props()

  const types: CreateType[] = ['game', 'movie', 'tvshow', 'book', 'manga']

  let type = $state<CreateType>('game')
  let title = $state('')
  let coverUrl = $state('')
  let notes = $state('')
  let platform = $state('')
  let hoursPlayed = $state('')
  let author = $state('')
  let totalPages = $state('')
  let totalChapters = $state('')
  let currentVolume = $state('')
  let durationMinutes = $state('')
  let isAnime = $state(false)
  let studio = $state('')
  let network = $state('')
  let seasons = $state<SeasonDraft[]>([])
  let submitting = $state(false)
  let submitError = $state<unknown>(null)
  let validationError = $state('')
  let score = $state('')
  let startedAt = $state('')
  let finishedAt = $state('')
  let status = $state<MediaStatus>(MEDIA_STATUS.planned)
  let editingInitialized = $state(false)
  let titleInput = $state<HTMLInputElement | null>(null)

  $effect(() => {
    if (isOpen && editingItem && !editingInitialized) {
      type = editingItem.type
      title = editingItem.title
      coverUrl = editingItem.coverUrl ?? ''
      notes = editingItem.notes ?? ''
      score = editingItem.score?.toString() ?? ''
      startedAt = editingItem.startedAt?.slice(0, 16) ?? ''
      finishedAt = editingItem.finishedAt?.slice(0, 16) ?? ''
      status = editingItem.status
      editingInitialized = true
    }
    if (isOpen) titleInput?.focus()
  })

  function numberOrNull(value: string): number | null {
    const parsed = Number(value)
    return value.trim() !== '' && Number.isFinite(parsed) ? parsed : null
  }

  function optionalText(value: string): string | null {
    return value.trim() || null
  }

  function buildSeasons(): CreateSeasonPayload[] {
    return seasons
      .filter((season) => season.title.trim() || season.totalEpisodes.trim())
      .map((season, index) => ({
        seasonNumber: numberOrNull(season.seasonNumber) ?? index + 1,
        title: season.title.trim() || `${i18n.t.createModal.fields.season} ${index + 1}`,
        totalEpisodes: Math.max(numberOrNull(season.totalEpisodes) ?? 0, 0),
        status: MEDIA_STATUS.planned,
      }))
  }

  function buildPayload(): CreateMediaPayload {
    const common = {
      title: title.trim(),
      status: MEDIA_STATUS.planned,
      coverUrl: optionalText(coverUrl),
      notes: optionalText(notes),
    }

    switch (type) {
      case 'game':
        return { ...common, type: 'game', platform: platform.trim(), hoursPlayed: numberOrNull(hoursPlayed) }
      case 'book':
        return { ...common, type: 'book', author: author.trim(), totalPages: numberOrNull(totalPages) }
      case 'manga':
        return {
          ...common,
          type: 'manga',
          author: author.trim() || undefined,
          totalChapters: numberOrNull(totalChapters),
          currentVolume: numberOrNull(currentVolume) ?? 1,
          totalVolumes: numberOrNull(totalPages) ?? 1,
        }
      case 'movie':
        return {
          ...common,
          type: 'movie',
          durationMinutes: numberOrNull(durationMinutes),
          isAnime,
          studio: optionalText(studio),
        }
      case 'tvshow':
        return {
          ...common,
          type: 'tvshow',
          isAnime,
          studio: optionalText(studio),
          network: optionalText(network),
          seasons: buildSeasons(),
        }
    }
  }

  function resetForm() {
    type = 'game'
    title = ''
    coverUrl = ''
    notes = ''
    platform = ''
    hoursPlayed = ''
    author = ''
    totalPages = ''
    totalChapters = ''
    currentVolume = ''
    durationMinutes = ''
    isAnime = false
    studio = ''
    network = ''
    seasons = []
    submitError = null
    status = MEDIA_STATUS.planned
    editingInitialized = false
    score = ''
    startedAt = ''
    finishedAt = ''
    validationError = ''
  }

  function close() {
    if (submitting) return
    resetForm()
    onClose()
  }

  async function submit() {
    validationError = ''
    submitError = null

    if (!title.trim()) {
      validationError = i18n.t.createModal.validation.titleRequired
      titleInput?.focus()
      return
    }

    submitting = true

    try {
    const saved = editingItem
        ? await updateMedia(editingItem.id, { title: title.trim(), score: numberOrNull(score), notes: optionalText(notes), coverUrl: optionalText(coverUrl), startedAt: startedAt ? new Date(startedAt).toISOString() : null, finishedAt: finishedAt ? new Date(finishedAt).toISOString() : null, status } satisfies UpdateMediaPayload)
        : await createMedia(buildPayload())
      resetForm()
      onCreated(saved)
      onClose()
    } catch (error) {
      submitError = error
    } finally {
      submitting = false
    }
  }

  function closeOnBackdrop(event: MouseEvent) {
    if (event.target === event.currentTarget) {
      close()
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (isOpen && event.key === 'Escape') {
      close()
    }
  }

  function addSeason() {
    seasons = [...seasons, { seasonNumber: String(seasons.length + 1), title: '', totalEpisodes: '' }]
  }

  function removeSeason(index: number) {
    seasons = seasons.filter((_, seasonIndex) => seasonIndex !== index)
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if isOpen}
  <div class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-canvas/85 p-4 backdrop-blur-sm sm:items-center" role="presentation" onclick={closeOnBackdrop}>
    <div class="my-auto w-full max-w-2xl overflow-hidden rounded-lg border border-border bg-surface shadow-2xl shadow-black/50" role="dialog" aria-modal="true" aria-labelledby="create-media-title">
      <header class="flex items-start justify-between gap-4 border-b border-border px-5 py-5 sm:px-6">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.createModal.eyebrow}</p>
          <h2 id="create-media-title" class="mt-1 text-xl font-bold tracking-tight text-ink">
            {editingItem ? (i18n.current === 'ru' ? 'Редактировать медиа' : 'Edit Media') : i18n.t.createModal.title}
          </h2>
        </div>
        <button type="button" class="grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink" aria-label={i18n.t.common.close} onclick={close}><X size={18} aria-hidden="true" /></button>
      </header>

      <form class="max-h-[75vh] space-y-5 overflow-y-auto p-5 sm:p-6" onsubmit={(event) => { event.preventDefault(); void submit() }}>
        {#if validationError}
          <p class="rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200" role="alert">{validationError}</p>
        {/if}
        {#if submitError}
          <p class="rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200" role="alert">{errorMessage(submitError)}</p>
        {/if}

        <div class="grid gap-4 sm:grid-cols-2">
          <label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.type}</span><select class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={type}>{#each types as mediaType}<option value={mediaType}>{i18n.t.types[mediaType]}</option>{/each}</select></label>
          <label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.title}</span><input bind:this={titleInput} class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={title} placeholder={i18n.t.createModal.placeholders.title} required /></label>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.score}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="1" max="10" bind:value={score} /></label>
          <label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.status.label}</span><select class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent" bind:value={status}>{#each Object.values(MEDIA_STATUS) as value}<option value={value}>{i18n.t.status[value === 0 ? 'planned' : value === 1 ? 'inProgress' : value === 2 ? 'completed' : value === 3 ? 'paused' : 'dropped']}</option>{/each}</select></label>
          <label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.startedAt}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent" type="datetime-local" bind:value={startedAt} /></label>
          <label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.finishedAt}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent" type="datetime-local" bind:value={finishedAt} /></label>
        </div>

        <div>
          <label class="block space-y-1.5 text-sm font-medium text-ink">
            <span>{i18n.t.createModal.fields.coverUrl}</span>
            <input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" type="url" bind:value={coverUrl} />
          </label>
        </div>

        <div>
          <label class="block space-y-1.5 text-sm font-medium text-ink">
            <span>{i18n.t.createModal.fields.notes}</span>
            <textarea
              class="min-h-[140px] w-full resize-y rounded-lg border border-border bg-elevated p-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30"
              rows={5}
              bind:value={notes}
              placeholder={i18n.t.createModal.placeholders.notes}
            ></textarea>
          </label>
        </div>

        {#if type === 'game'}
          <div class="grid gap-4 sm:grid-cols-2"><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.platform}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={platform} placeholder={i18n.t.createModal.placeholders.platform} /></label><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.hoursPlayed}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="0" bind:value={hoursPlayed} /></label></div>
        {:else if type === 'book'}
          <div class="grid gap-4 sm:grid-cols-2"><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.author}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={author} placeholder={i18n.t.createModal.placeholders.author} /></label><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.totalPages}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="0" bind:value={totalPages} /></label></div>
        {:else if type === 'manga'}
          <div class="grid gap-4 sm:grid-cols-2"><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.author}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={author} placeholder={i18n.t.createModal.placeholders.author} /></label><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.totalChapters}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="0" bind:value={totalChapters} /></label></div>
          <div class="grid gap-4 sm:grid-cols-2"><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.currentVolume}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="0" bind:value={currentVolume} /></label><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.detail.tabVolumes}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="0" bind:value={totalPages} placeholder="1" /></label></div>
        {:else if type === 'movie'}
          <div class="grid gap-4 sm:grid-cols-2"><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.durationMinutes}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none focus:border-accent focus:ring-2 focus:ring-accent/30" type="number" min="0" bind:value={durationMinutes} /></label><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.studio}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={studio} placeholder={i18n.t.createModal.placeholders.studio} /></label></div>
          <label class="inline-flex items-center gap-2 text-sm text-muted"><input class="h-4 w-4 accent-accent" type="checkbox" bind:checked={isAnime} />{i18n.t.createModal.fields.isAnime}</label>
        {:else}
          <div class="grid gap-4 sm:grid-cols-2"><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.studio}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={studio} placeholder={i18n.t.createModal.placeholders.studio} /></label><label class="space-y-1.5 text-sm font-medium text-ink"><span>{i18n.t.createModal.fields.network}</span><input class="h-10 w-full rounded-lg border border-border bg-elevated px-3 text-sm font-normal outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" bind:value={network} placeholder={i18n.t.createModal.placeholders.network} /></label></div>
          <label class="inline-flex items-center gap-2 text-sm text-muted"><input class="h-4 w-4 accent-accent" type="checkbox" bind:checked={isAnime} />{i18n.t.createModal.fields.isAnime}</label>
          <div class="space-y-3 rounded-xl border border-border bg-elevated/50 p-3">
            <div class="flex items-center justify-between"><p class="text-sm font-semibold text-ink">{i18n.t.navigation.seasons}</p><button type="button" class="inline-flex items-center gap-1.5 text-xs font-semibold text-accent-soft transition hover:text-ink" onclick={addSeason}><Plus size={14} aria-hidden="true" />{i18n.t.createModal.addSeason}</button></div>
            {#each seasons as season, index (index)}
              <div class="grid gap-2 sm:grid-cols-[5rem_1fr_7rem_auto]"><input class="h-9 rounded-lg border border-border bg-surface px-2 text-sm outline-none focus:border-accent" type="number" min="1" bind:value={season.seasonNumber} aria-label={i18n.t.createModal.fields.season} /><input class="h-9 rounded-lg border border-border bg-surface px-2 text-sm outline-none placeholder:text-muted focus:border-accent" bind:value={season.title} placeholder={i18n.t.createModal.placeholders.season} /><input class="h-9 rounded-lg border border-border bg-surface px-2 text-sm outline-none placeholder:text-muted focus:border-accent" type="number" min="0" bind:value={season.totalEpisodes} placeholder={i18n.t.createModal.fields.episodes} /><button type="button" class="grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-rose-400/10 hover:text-rose-300" aria-label={i18n.t.common.delete} onclick={() => removeSeason(index)}><Minus size={16} aria-hidden="true" /></button></div>
            {/each}
          </div>
        {/if}

        <footer class="flex justify-end gap-3 border-t border-border pt-5">
          <button type="button" class="rounded-md px-3 py-2 text-sm font-semibold text-muted transition hover:text-ink" onclick={close}>{i18n.t.common.cancel}</button>
          <button type="submit" class="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:bg-accent-hover disabled:cursor-wait disabled:opacity-70" disabled={submitting}>
            {submitting ? i18n.t.common.saving : (editingItem ? i18n.t.common.save : i18n.t.common.add)}
          </button>
        </footer>
      </form>
    </div>
  </div>
{/if}
