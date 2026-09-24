<script lang="ts">
  import { List } from 'lucide-svelte'
  import { i18n } from '$lib/i18n/index.svelte'
</script>

<div class="mx-auto flex min-h-[60vh] max-w-3xl flex-col items-center justify-center rounded-2xl border border-dashed border-border bg-surface/60 p-8 text-center">
  <div class="grid h-14 w-14 place-items-center rounded-2xl bg-elevated text-accent-soft"><List size={24} aria-hidden="true" /></div>
  <p class="mt-5 text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.common.comingSoon}</p>
  <h2 class="mt-2 text-2xl font-bold tracking-tight text-ink">{i18n.t.views.listsTitle}</h2>
  <p class="mt-3 max-w-md text-sm leading-6 text-muted">{i18n.t.views.listsHint}</p>
</div>
