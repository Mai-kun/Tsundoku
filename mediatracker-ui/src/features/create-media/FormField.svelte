<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    label: string;
    children: Snippet;
  }

  let { label, children }: Props = $props();
</script>

<label class="text-ink space-y-1.5 text-sm font-medium">
  <span>{label}</span>
  {@render children()}
</label>
