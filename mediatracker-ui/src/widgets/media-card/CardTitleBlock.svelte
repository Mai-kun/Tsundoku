<script lang="ts">
    import { titleTooltip } from "$entities/media/model/mediaLabels";

    interface Props {
        title: string;
        /** Platform, author, media type — the single muted line under the title. */
        subtitle: string;
    }

    let { title, subtitle }: Props = $props();
</script>

<div class="min-w-0">
    <h2
        class="truncate break-words text-sm font-semibold text-ink"
        title={titleTooltip(title)}
    >
        {title}
    </h2>
    <p class="mt-1 truncate text-xs text-muted @max-[13rem]:hidden">
        {subtitle}
    </p>
</div>