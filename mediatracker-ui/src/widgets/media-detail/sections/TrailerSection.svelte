<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Film, Play } from "$shared/ui/Icons.svelte";

  interface Props {
    trailerVideoId: string | null;
    title: string;
  }

  let { trailerVideoId, title }: Props = $props();
  let playing = $state(false);
</script>

{#if trailerVideoId}
  <section
    class="group relative aspect-video w-full overflow-hidden rounded-xl border border-white/10 bg-black/60"
  >
    {#if playing}
      <iframe
        src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(trailerVideoId)}?autoplay=1`}
        title={`${title} trailer`}
        class="absolute inset-0 h-full w-full border-0"
        allow="autoplay; encrypted-media; picture-in-picture"
        allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"
      ></iframe>
    {:else}
      <img
        src={`https://img.youtube.com/vi/${encodeURIComponent(trailerVideoId)}/hqdefault.jpg`}
        alt=""
        loading="lazy"
        class="absolute inset-0 h-full w-full object-cover"
      />
      <div class="absolute inset-0 bg-black/25 transition group-hover:bg-black/40"></div>
      <button
        type="button"
        class="group absolute inset-0 flex items-center justify-center"
        aria-label={`${i18n.t.detail.trailerTitle}: ${title}`}
        onclick={() => (playing = true)}
      >
        <span
          class="grid size-14 place-items-center rounded-2xl bg-red-600 text-white shadow-xl transition group-hover:scale-[1.03] group-hover:bg-red-500"
        >
          <Play size={25} class="fill-current" />
        </span>
      </button>
      <span class="absolute bottom-3 left-3 text-xs font-semibold text-white drop-shadow"
        >{i18n.t.detail.trailerTitle}</span
      >
    {/if}
  </section>
{:else}
  <section
    class="text-muted flex aspect-video min-h-[190px] w-full flex-col items-center justify-center rounded-xl border border-white/5 bg-[var(--color-panel-line)]/40 p-5"
  >
    <Film size={26} class="mb-2 opacity-60" />
    <span class="text-sm">{i18n.t.detail.trailerNotFound}</span>
  </section>
{/if}
