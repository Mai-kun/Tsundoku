<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    class?: string;
    children: Snippet;
  }

  let { class: className = "", children }: Props = $props();

  // Unified card container: replaces per-file
  // `rounded-lg/xl border border-white/[0.08] bg-...` hand-rolled boxes.
  // bg-panel-line resolves through --color-panel-line -> --bg-surface, so panels
  // repaint correctly under a future html[data-theme="..."] override.
  const baseClasses = "rounded-xl border border-subtle bg-panel-line p-4 shadow-md";
</script>

<div class="{baseClasses} {className}">
  {@render children()}
</div>
