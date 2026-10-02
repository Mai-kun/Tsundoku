<script lang="ts">
    import type { MediaCardProps } from "./cardTypes";
    import BookCard from "./BookCard.svelte";
    import GameCard from "./GameCard.svelte";
    import MangaCard from "./MangaCard.svelte";
    import MovieCard from "./MovieCard.svelte";
    import TvShowCard from "./TvShowCard.svelte";

    let { item, ...rest }: MediaCardProps = $props();
</script>

{#if item.type === "game"}
    <GameCard {item} {...rest} />
{:else if item.type === "book"}
    <BookCard {item} {...rest} />
{:else if item.type === "manga"}
    <MangaCard {item} {...rest} />
{:else if item.type === "movie"}
    <MovieCard {item} {...rest} />
{:else}
    <TvShowCard {item} {...rest} />
{/if}
