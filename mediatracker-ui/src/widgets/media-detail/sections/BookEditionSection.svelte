<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Library } from "$shared/ui/Icons.svelte";
  import type { BookMedia, MediaDetailFields } from "$shared/types";

  interface Props {
    media: BookMedia & MediaDetailFields;
  }

  let { media }: Props = $props();
  const isRu = $derived(i18n.current === "ru");

  interface Row {
    label: string;
    value: string;
  }
  const rows = $derived.by((): Row[] => {
    const result: Row[] = [];
    if (media.totalPages > 0) {
      result.push({
        label: isRu ? "Всего страниц" : "Total pages",
        value: `${media.totalPages} ${isRu ? "стр." : "pages"}`,
      });
    }
    if (media.releaseYear) {
      result.push({
        label: isRu ? "Год публикации" : "Published",
        value: String(media.releaseYear),
      });
    }
    if (media.originalLanguage) {
      result.push({
        label: isRu ? "Язык" : "Language",
        value: media.originalLanguage.toUpperCase(),
      });
    }
    // Format: userPlatform if set (e.g., Paperback, Hardcover, Kindle, etc.), otherwise smart default
    const formatValue =
      media.userPlatform?.trim() || (isRu ? "Электронная книга" : "E-book / Print");
    result.push({
      label: isRu ? "Формат" : "Format",
      value: formatValue,
    });

    return result;
  });
</script>

<section
  class="space-y-3 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
>
  <div class="flex items-center gap-2">
    <Library size={16} class="text-accent-soft shrink-0" />
    <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
      {isRu ? "Об издании" : "Publication"}
    </h2>
  </div>
  <div class="grid grid-cols-2 gap-2">
    {#each rows as row (row.label)}
      <div
        class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2"
      >
        <span class="text-muted text-[11px] font-medium">{row.label}</span>
        <span class="text-xs font-semibold text-white">{row.value}</span>
      </div>
    {/each}
  </div>
</section>
