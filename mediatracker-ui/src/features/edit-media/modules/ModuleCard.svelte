<script lang="ts">
  import type { Snippet } from "svelte";

  /**
   * Shared chrome for the editor's modular cards: an icon, a title, an optional counter chip and
   * the body. Purely presentational — no state, no API — so any of the six editor modules can be
   * reused outside the big editor with the same look.
   *
   * `flat` strips the frame and the headline bar: the host (e.g. a workspace window) already
   * draws its own border and title, so the module renders only a small section label plus body.
   * `showLabel` hides even that label when the host's own title says the same thing.
   */
  interface Props {
    icon: Snippet;
    title: string;
    /** Optional badge next to the title (item count). */
    count?: number;
    flat?: boolean;
    showLabel?: boolean;
    children: Snippet;
  }

  let { icon, title, count, flat = false, showLabel = true, children }: Props = $props();
</script>

{#if flat}
  <section class="flex h-full min-h-0 flex-col gap-2.5">
    {#if showLabel}
      <div class="flex items-center gap-1.5">
        <span class="text-muted">{@render icon()}</span>
        <h4 class="text-muted text-[10px] font-bold tracking-[0.14em] uppercase">{title}</h4>
        {#if typeof count === "number" && count > 0}
          <span class="text-muted/70 text-[10px] font-semibold">{count}</span>
        {/if}
      </div>
    {/if}
    {@render children()}
  </section>
{:else}
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
{/if}
