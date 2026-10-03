<script lang="ts">
    import type { RecommendationItem } from "../detailTypes";
    import RecommendationsPanel from "../panels/RecommendationsPanel.svelte";

    interface Props {
        items: readonly RecommendationItem[];
        loading: boolean;
        error: unknown;
        /** `force` skips the 30-day cache. */
        onLoad: (force?: boolean) => void;
    }

    let { items, loading, error, onLoad }: Props = $props();
</script>

<RecommendationsPanel {items} {loading} {error} {onLoad} />
