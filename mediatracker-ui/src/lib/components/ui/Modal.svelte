<script lang="ts">
  import type { Snippet } from 'svelte'
  import { fade, scale } from 'svelte/transition'

  interface Props {
    isOpen: boolean
    onClose: () => void
    labelledBy?: string
    children: Snippet
  }

  let { isOpen, onClose, labelledBy, children }: Props = $props()

  let dialogElement = $state<HTMLDialogElement | null>(null)
  let closingProgrammatically = false

  $effect(() => {
    const dialog = dialogElement
    if (!dialog) return

    if (isOpen && !dialog.open) {
      dialog.showModal()
    } else if (!isOpen && dialog.open) {
      closingProgrammatically = true
      dialog.close()
      closingProgrammatically = false
    }
  })

  function handleCancel(event: Event) {
    event.preventDefault()
    onClose()
  }

  function handleNativeClose() {
    if (closingProgrammatically) return
    onClose()
  }

  function handleClick(event: MouseEvent) {
    if (event.target === dialogElement) onClose()
  }
</script>

<dialog
  bind:this={dialogElement}
  aria-labelledby={labelledBy}
  class="z-40 m-auto w-full max-w-2xl overflow-visible border-0 bg-transparent p-4 text-ink backdrop:bg-black/70 backdrop:backdrop-blur-sm"
  onclose={handleNativeClose}
  oncancel={handleCancel}
  onclick={handleClick}
>
  <!-- Fully opaque panel: only the ::backdrop carries the dim/blur, never the dialog
       surface itself, otherwise page content bleeds through the text. -->
  <div
    class="overflow-hidden rounded-xl border border-white/[0.08] bg-[#151a26] shadow-2xl shadow-black/60"
    transition:fade={{ duration: 150 }}
  >
    <div transition:scale={{ start: 0.98, duration: 150 }}>
      {@render children()}
    </div>
  </div>
</dialog>