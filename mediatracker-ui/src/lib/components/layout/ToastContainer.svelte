<script lang="ts">
  import AlertCircle from 'lucide-svelte/icons/alert-circle'
  import AlertTriangle from 'lucide-svelte/icons/alert-triangle'
  import CheckCircle2 from 'lucide-svelte/icons/check-circle-2'
  import X from 'lucide-svelte/icons/x'
  import { dismissToast, toastStore, type ToastType } from '$lib/stores/toast.svelte'

  function getStyles(type: ToastType) {
    switch (type) {
      case 'success':
        return {
          container: 'border-emerald-500/30 bg-[color-mix(in_oklab,var(--color-success-surface)_90%,transparent)] text-emerald-200 shadow-emerald-950/40',
          icon: CheckCircle2,
          iconColor: 'text-emerald-400',
        }
      case 'warning':
        return {
          container: 'border-amber-500/30 bg-[color-mix(in_oklab,var(--color-warning-surface)_90%,transparent)] text-amber-200 shadow-amber-950/40',
          icon: AlertTriangle,
          iconColor: 'text-amber-400',
        }
      case 'error':
        return {
          container: 'border-rose-500/30 bg-[color-mix(in_oklab,var(--color-danger-surface)_90%,transparent)] text-rose-200 shadow-rose-950/40',
          icon: AlertCircle,
          iconColor: 'text-rose-400',
        }
    }
  }
</script>

<div
  class="pointer-events-none fixed bottom-5 right-5 z-50 flex max-w-sm flex-col gap-2"
  aria-live="polite"
  aria-atomic="false"
>
  {#each toastStore.items as toast (toast.id)}
    {@const style = getStyles(toast.type)}
    {@const Icon = style.icon}
    <div
      class={`pointer-events-auto flex items-start gap-3 rounded-lg border p-3.5 shadow-xl backdrop-blur transition-all duration-200 ${style.container}`}
      role="alert"
    >
      <Icon size={18} class={`shrink-0 mt-0.5 ${style.iconColor}`} aria-hidden="true" />
      <p class="flex-1 text-xs font-medium leading-relaxed break-words">{toast.message}</p>
      <button
        type="button"
        class="shrink-0 -mr-1 -mt-1 rounded p-1 text-white/60 transition hover:bg-white/10 hover:text-white"
        aria-label="Close notification"
        onclick={() => dismissToast(toast.id)}
      >
        <X size={14} aria-hidden="true" />
      </button>
    </div>
  {/each}
</div>
