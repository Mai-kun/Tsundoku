<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Check, Copy, Library } from "$shared/ui/Icons";
  import { showToast } from "$shared/ui/toast.svelte";
  import type { BookMedia, MediaDetailFields } from "$shared/types";

  interface Props {
    media: BookMedia & MediaDetailFields;
  }

  let { media }: Props = $props();
  const isRu = $derived(i18n.current === "ru");

  let copied = $state(false);
  let copyTimeout: ReturnType<typeof setTimeout> | null = null;

  function copyIsbn() {
    if (!media.isbn) return;
    navigator.clipboard.writeText(media.isbn).then(() => {
      copied = true;
      showToast({ title: isRu ? "ISBN скопирован" : "ISBN copied to clipboard", description: i18n.t.toast.descCopied });
      if (copyTimeout) clearTimeout(copyTimeout);
      copyTimeout = setTimeout(() => {
        copied = false;
      }, 2000);
    });
  }

  $effect(() => {
    return () => {
      if (copyTimeout) clearTimeout(copyTimeout);
    };
  });

  interface Row {
    label: string;
    value: string;
  }
  const rows = $derived.by((): Row[] => {
    const result: Row[] = [];
    const publisher = media.studio?.trim();
    if (publisher) {
      result.push({
        label: isRu ? "Издатель" : "Publisher",
        value: publisher,
      });
    }
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
    const rawFormat =
      media.userPlatform?.trim() || (media.format && media.format !== "book" ? media.format : null);
    const formatValue = rawFormat || (isRu ? "Электронная книга" : "E-book / Print");
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

    {#if media.isbn}
      <div
        class="col-span-2 flex items-center justify-between rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2"
      >
        <div class="flex flex-col gap-0.5">
          <span class="text-muted text-[11px] font-medium">ISBN</span>
          <span class="font-mono text-xs font-semibold tracking-wide text-white">{media.isbn}</span>
        </div>
        <button
          type="button"
          class="flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-white/[0.04] px-2.5 py-1 text-[11px] font-medium text-slate-300 transition-colors hover:bg-white/[0.08] hover:text-white"
          onclick={copyIsbn}
          title={isRu ? "Копировать ISBN" : "Copy ISBN"}
          aria-label={isRu ? "Копировать ISBN" : "Copy ISBN"}
        >
          {#if copied}
            <Check size={13} class="text-emerald-400" />
            <span class="text-emerald-400">{isRu ? "Скопировано" : "Copied"}</span>
          {:else}
            <Copy size={13} class="text-slate-400" />
            <span>{isRu ? "Копировать" : "Copy"}</span>
          {/if}
        </button>
      </div>
    {/if}
  </div>
</section>
