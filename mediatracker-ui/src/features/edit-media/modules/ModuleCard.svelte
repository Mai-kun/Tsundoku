<script lang="ts">
  import type { Snippet } from "svelte";

  /**
   * Shared chrome for the editor's modular cards: an icon, a title, an optional counter chip and
   * the body. Purely presentational — no state, no API — so any of the six editor modules can be
   * reused outside the big modal with the same look.
   */
  interface Props {
    icon: Snippet;
    title: string;
    /** Optional badge next to the title (item count). */
    count?: number;
    children: Snippet;
  }

  let { icon, title, count, children }: Props = $props();
</script>

<section
  class="flex flex-col gap-3 rounded-xl border border-white/[0.06] bg-[#12151c] p-4 transition-[border-color] duration-200"
>
  <header class="flex items-center gap-2">
    <span class="text-accent-soft grid size-7 shrink-0 place-items-center rounded-lg bg-white/[0.04]">
      {@render icon()}
    </span>
    <h3 class="text-ink text-xs font-bold tracking-[0.14em] uppercase">{title}</h3>
    {#if typeof count === "number" && count > 0}
      <span
        class="rounded-full bg-white/[0.06] px-2 py-0.5 text-[11px] font-semibold text-slate-300"
      >
        {count}
      </span>
    {/if}
  </header>
  {@render children()}
</section>
