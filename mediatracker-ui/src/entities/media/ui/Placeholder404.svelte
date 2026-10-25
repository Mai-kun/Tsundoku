<script lang="ts">
    import MediaCoverPlaceholder from "$shared/ui/MediaCoverPlaceholder.svelte";

    interface Props {
        label?: string;
    }
    let { label }: Props = $props();
</script>

<MediaCoverPlaceholder {label} />
