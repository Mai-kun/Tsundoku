<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";

    interface Props {
        label?: string;
        class?: string;
    }

    let { label = i18n.t.activity.coverMissing, class: className = "" }: Props = $props();
</script>

<div
    class="relative flex h-full w-full items-center justify-center overflow-hidden bg-gradient-to-br from-[#12151c] to-[#1a1e28] {className}"
>
    <img
        src="/placeholder-404.jpg"
        alt={label || "Обложка не найдена"}
        class="h-full w-full object-cover opacity-90 transition duration-300 hover:scale-105"
        loading="lazy"
    />
    <div
        class="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 via-black/40 to-transparent p-2 text-center"
    >
        <span class="text-[10px] font-semibold text-slate-300 drop-shadow">{label || "Обложка не найдена"}</span>
    </div>
</div>
