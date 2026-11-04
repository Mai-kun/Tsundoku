<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import FormField from "./FormField.svelte";
  import Select from "$shared/ui/Select.svelte";

  interface Props {
    author: string;
    totalPages: string;
    format?: string;
    totalChapters?: string;
    totalVolumes?: string;
  }

  let {
    author = $bindable(),
    totalPages = $bindable(),
    format = $bindable("book"),
    totalChapters = $bindable(""),
    totalVolumes = $bindable(""),
  }: Props = $props();

  const formatOptions = $derived([
    { value: "book", label: i18n.t.createModal.fields.bookFormats.book },
    { value: "light_novel", label: i18n.t.createModal.fields.bookFormats.light_novel },
    { value: "web_novel", label: i18n.t.createModal.fields.bookFormats.web_novel },
  ]);

  const isNovel = $derived(format === "light_novel" || format === "web_novel");
</script>

<div class="space-y-4">
  <div class="grid gap-4 sm:grid-cols-2">
    <FormField label={i18n.t.createModal.fields.author}>
      <input
        class="bg-field placeholder:text-muted h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
        bind:value={author}
        placeholder={i18n.t.createModal.placeholders.author}
      />
    </FormField>

    <FormField label={i18n.t.createModal.fields.format}>
      <Select
        id="book-format-select"
        value={format || "book"}
        options={formatOptions}
        onChange={(val) => {
          format = val;
        }}
      />
    </FormField>
  </div>

  {#if isNovel}
    <div class="grid gap-4 sm:grid-cols-2">
      <FormField label={i18n.t.createModal.fields.totalChapters}>
        <input
          class="bg-field h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          type="number"
          min="0"
          bind:value={totalChapters}
        />
      </FormField>

      <FormField label={i18n.t.createModal.fields.totalVolumes}>
        <input
          class="bg-field h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          type="number"
          min="0"
          bind:value={totalVolumes}
        />
      </FormField>
    </div>
  {:else}
    <div class="grid gap-4 sm:grid-cols-2">
      <FormField label={i18n.t.createModal.fields.totalPages}>
        <input
          class="bg-field h-10 w-full rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
          type="number"
          min="0"
          bind:value={totalPages}
        />
      </FormField>
    </div>
  {/if}
</div>
