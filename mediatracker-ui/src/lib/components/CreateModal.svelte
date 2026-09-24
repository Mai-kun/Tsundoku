<script lang="ts">
  import { i18n } from '$lib/i18n/index.svelte'
  import { createMedia, errorMessage } from '../api'
  import type { CreateMediaPayload, MediaItem } from '$lib/types'

  type FormType = 'Game' | 'Movie' | 'TvShow' | 'Book' | 'Manga'
  type TypeKey = 'game' | 'movie' | 'tvshow' | 'book' | 'manga'
  type StatusKey = 'planned' | 'inProgress' | 'completed' | 'paused' | 'dropped'

  interface CreateForm {
    type: FormType
    title: string
    coverUrl: string
    status: number
    notes: string
    platform: string
    hoursPlayed: number
    author: string
    totalPages: number | null
    totalChapters: number | null
    currentVolume: number | null
    isAnime: boolean
    studio: string
    durationMinutes: number | null
    network: string
  }

  interface Props {
    onClose: () => void
    onCreated: (media: MediaItem) => void
  }

  const inputClass = 'w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 outline-none transition placeholder:text-slate-500 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/20'

  const typeOptions: Array<{ value: FormType; key: TypeKey }> = [
    { value: 'Game', key: 'game' },
    { value: 'Movie', key: 'movie' },
    { value: 'TvShow', key: 'tvshow' },
    { value: 'Book', key: 'book' },
    { value: 'Manga', key: 'manga' },
  ]

  const statusOptions: Array<{ value: number; key: StatusKey }> = [
    { value: 0, key: 'planned' },
    { value: 1, key: 'inProgress' },
    { value: 2, key: 'completed' },
    { value: 3, key: 'paused' },
    { value: 4, key: 'dropped' },
  ]

  let { onClose, onCreated }: Props = $props()

  let form = $state<CreateForm>(createEmptyForm())
  let submitting = $state(false)
  let validationFailed = $state(false)
  let error = $state<unknown>(null)

  let errorText = $derived(validationFailed ? i18n.t.createModal.validation.titleRequired : error !== null ? errorMessage(error) : '')

  function createEmptyForm(): CreateForm {
    return {
      type: 'Game',
      title: '',
      coverUrl: '',
      status: 0,
      notes: '',
      platform: '',
      hoursPlayed: 0,
      author: '',
      totalPages: null,
      totalChapters: null,
      currentVolume: null,
      isAnime: false,
      studio: '',
      durationMinutes: null,
      network: '',
    }
  }

  function optionalText(value: string): string | null {
    return value.trim() || null
  }

  function optionalNumber(value: number | string | null | undefined): number | null {
    return value === '' || value === null || value === undefined ? null : Number(value)
  }

  function apiType(type: FormType): string {
    return type === 'TvShow' ? 'tvshow' : type.toLowerCase()
  }

  function buildPayload(): CreateMediaPayload {
    const payload = {
      type: apiType(form.type),
      title: form.title.trim(),
      coverUrl: optionalText(form.coverUrl),
      status: Number(form.status),
      notes: optionalText(form.notes),
    }

    if (form.type === 'Game') {
      return {
        ...payload,
        platform: optionalText(form.platform),
        hoursPlayed: optionalNumber(form.hoursPlayed),
      }
    }

    if (form.type === 'Book') {
      return {
        ...payload,
        author: optionalText(form.author),
        totalPages: optionalNumber(form.totalPages),
      }
    }

    if (form.type === 'Manga') {
      return {
        ...payload,
        totalChapters: optionalNumber(form.totalChapters),
        currentVolume: optionalNumber(form.currentVolume),
      }
    }

    if (form.type === 'Movie') {
      return {
        ...payload,
        isAnime: form.isAnime,
        studio: optionalText(form.studio),
        durationMinutes: optionalNumber(form.durationMinutes),
      }
    }

    return {
      ...payload,
      isAnime: form.isAnime,
      studio: optionalText(form.studio),
      network: optionalText(form.network),
    }
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault()
    error = null
    validationFailed = false

    if (!form.title.trim()) {
      validationFailed = true
      return
    }

    submitting = true

    try {
      const created = await createMedia(buildPayload())
      onCreated(created)
    } catch (requestError) {
      error = requestError
    } finally {
      submitting = false
    }
  }

  function closeOnBackdrop(event: MouseEvent) {
    if (event.target === event.currentTarget && !submitting) {
      onClose()
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape' && !submitting) {
      onClose()
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-slate-950/80 p-4 backdrop-blur-sm" role="presentation" onclick={closeOnBackdrop}>
  <div class="w-full max-w-2xl rounded-2xl border border-slate-700 bg-slate-900 p-5 shadow-2xl shadow-slate-950/60 sm:p-6" role="dialog" aria-modal="true" aria-labelledby="create-title">
    <div class="mb-6 flex items-start justify-between gap-4">
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.2em] text-blue-300">{i18n.t.createModal.eyebrow}</p>
        <h2 id="create-title" class="mt-1 text-xl font-semibold text-white">{i18n.t.createModal.title}</h2>
      </div>
      <button
        type="button"
        class="inline-flex h-9 w-9 items-center justify-center rounded-lg text-slate-400 transition hover:bg-slate-800 hover:text-white focus:outline-none focus:ring-2 focus:ring-blue-400 disabled:opacity-50"
        aria-label={i18n.t.common.close}
        disabled={submitting}
        onclick={onClose}
      >
        <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="m6 6 12 12M18 6 6 18" />
        </svg>
      </button>
    </div>

    <form class="space-y-5" onsubmit={submit}>
      <div class="grid gap-4 sm:grid-cols-2">
        <label class="space-y-1.5 text-sm font-medium text-slate-300">
          <span>{i18n.t.createModal.fields.type}</span>
          <select class={inputClass} bind:value={form.type}>
            {#each typeOptions as option}
              <option value={option.value}>{i18n.t.types[option.key]}</option>
            {/each}
          </select>
        </label>

        <label class="space-y-1.5 text-sm font-medium text-slate-300">
          <span>{i18n.t.status.label}</span>
          <select class={inputClass} bind:value={form.status}>
            {#each statusOptions as option}
              <option value={option.value}>{i18n.t.status[option.key]}</option>
            {/each}
          </select>
        </label>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <label class="space-y-1.5 text-sm font-medium text-slate-300">
          <span>{i18n.t.createModal.fields.title}</span>
          <input class={inputClass} type="text" placeholder={i18n.t.createModal.placeholders.title} required bind:value={form.title} />
        </label>

        <label class="space-y-1.5 text-sm font-medium text-slate-300">
          <span>{i18n.t.createModal.fields.coverUrl}</span>
          <input class={inputClass} type="url" placeholder="https://..." bind:value={form.coverUrl} />
        </label>
      </div>

      {#if form.type === 'Game'}
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="space-y-1.5 text-sm font-medium text-slate-300">
            <span>{i18n.t.createModal.fields.platform}</span>
            <input class={inputClass} type="text" placeholder={i18n.t.createModal.placeholders.platform} bind:value={form.platform} />
          </label>
          <label class="space-y-1.5 text-sm font-medium text-slate-300">
            <span>{i18n.t.createModal.fields.hoursPlayed}</span>
            <input class={inputClass} type="number" min="0" step="1" bind:value={form.hoursPlayed} />
          </label>
        </div>
      {:else if form.type === 'Book'}
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="space-y-1.5 text-sm font-medium text-slate-300">
            <span>{i18n.t.createModal.fields.author}</span>
            <input class={inputClass} type="text" placeholder={i18n.t.createModal.placeholders.author} bind:value={form.author} />
          </label>
          <label class="space-y-1.5 text-sm font-medium text-slate-300">
            <span>{i18n.t.createModal.fields.totalPages}</span>
            <input class={inputClass} type="number" min="0" step="1" bind:value={form.totalPages} />
          </label>
        </div>
      {:else if form.type === 'Manga'}
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="space-y-1.5 text-sm font-medium text-slate-300">
            <span>{i18n.t.createModal.fields.totalChapters}</span>
            <input class={inputClass} type="number" min="0" step="1" bind:value={form.totalChapters} />
          </label>
          <label class="space-y-1.5 text-sm font-medium text-slate-300">
            <span>{i18n.t.createModal.fields.currentVolume}</span>
            <input class={inputClass} type="number" min="0" step="1" bind:value={form.currentVolume} />
          </label>
        </div>
      {:else}
        <div class="space-y-4">
          <label class="flex items-center gap-3 rounded-lg border border-slate-700 bg-slate-800/60 px-3 py-2.5 text-sm font-medium text-slate-200">
            <input type="checkbox" class="h-4 w-4 rounded border-slate-600 bg-slate-800 text-blue-500 focus:ring-blue-400" bind:checked={form.isAnime} />
            {i18n.t.createModal.fields.isAnime}
          </label>

          <div class="grid gap-4 sm:grid-cols-2">
            <label class="space-y-1.5 text-sm font-medium text-slate-300">
              <span>{i18n.t.createModal.fields.studio}</span>
              <input class={inputClass} type="text" placeholder={i18n.t.createModal.placeholders.studio} bind:value={form.studio} />
            </label>

            {#if form.type === 'Movie'}
              <label class="space-y-1.5 text-sm font-medium text-slate-300">
                <span>{i18n.t.createModal.fields.durationMinutes}</span>
                <input class={inputClass} type="number" min="0" step="1" bind:value={form.durationMinutes} />
              </label>
            {:else}
              <label class="space-y-1.5 text-sm font-medium text-slate-300">
                <span>{i18n.t.createModal.fields.network}</span>
                <input class={inputClass} type="text" placeholder={i18n.t.createModal.placeholders.network} bind:value={form.network} />
              </label>
            {/if}
          </div>
        </div>
      {/if}

      <label class="block space-y-1.5 text-sm font-medium text-slate-300">
        <span>{i18n.t.createModal.fields.notes}</span>
        <textarea class={inputClass} rows="3" placeholder={i18n.t.createModal.placeholders.notes} bind:value={form.notes}></textarea>
      </label>

      {#if errorText}
        <p class="rounded-lg border border-rose-500/40 bg-rose-500/10 px-3 py-2 text-sm text-rose-200" role="alert">{errorText}</p>
      {/if}

      <div class="flex justify-end gap-3 border-t border-slate-800 pt-5">
        <button type="button" class="rounded-lg px-4 py-2 text-sm font-medium text-slate-300 transition hover:bg-slate-800 hover:text-white disabled:opacity-50" disabled={submitting} onclick={onClose}>{i18n.t.common.cancel}</button>
        <button type="submit" class="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white shadow-lg shadow-blue-950/40 transition hover:bg-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-300 disabled:cursor-wait disabled:opacity-60" disabled={submitting}>
          {submitting ? i18n.t.common.adding : i18n.t.common.add}
        </button>
      </div>
    </form>
  </div>
</div>
