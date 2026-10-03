<script lang="ts">
    import type { MediaItem } from "$shared/types";
import type { RecommendationItem } from "../detailTypes";
import RecommendationsPanel from "../panels/RecommendationsPanel.svelte";

    interface Props {
        media: MediaItem;
        items: readonly RecommendationItem[];
        loading: boolean;
        error: unknown;
        /** The source comes from the user's dropdown pick; `force` skips the 30-day cache. */
        onLoad: (source: string, force?: boolean) => void;
    }

    let { media, items, loading, error, onLoad }: Props = $props();
</script>

<RecommendationsPanel {media} {items} {loading} {error} {onLoad} />
