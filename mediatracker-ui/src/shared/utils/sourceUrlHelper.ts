/**
 * AnimeLib lives on a versioned subdomain with mandatory /ru/anime/ path prefixes. A stored slug
 * that already carries them ("ru/anime/8231--x") is stripped before substitution, so the result is
 * always canonical: https://v5.animelib.org/ru/anime/8231--noragami-anime.
 */
export function buildAnimelibUrl(id: string): string {
  const cleanSlug = id.trim().replace(/^(?:ru\/)?(?:anime\/)?/i, "");
  return `https://v5.animelib.org/ru/anime/${encodeURIComponent(cleanSlug)}`;
}

/**
 * Builds the real web page of a title for a bound external source. Unknown or offline sources
 * return null — the panel then renders the card without the "open" action.
 */
export function buildSourceUrl(
  source: string,
  externalId: string,
  mediaType?: string,
): string | null {
  const key = source.toLowerCase();
  const id = encodeURIComponent(externalId.trim());
  if (!id) return null;

  // LibSocial ecosystem: the stored id is the site's slug_url ("35160--slug").
  if (key.includes("mangalib")) return `https://mangalib.me/ru/${id}`;
  if (key.includes("ranobelib")) return `https://ranobelib.me/ru/${id}`;
  if (key.includes("animelib")) return buildAnimelibUrl(id);
  if (key.includes("slashlib")) return `https://slashlib.me/ru/${id}`;
  if (key.includes("hentailib")) return `https://hentailib.me/ru/${id}`;

  if (key.includes("anilist")) {
    const kind = mediaType === "anime" ? "anime" : "manga";
    return `https://anilist.co/${kind}/${id}`;
  }
  if (key.includes("shikimori")) {
    // The site moved off shikimori.one (it stopped answering); .io is the live domain.
    return mediaType === "anime"
      ? `https://shikimori.io/animes/${id}`
      : `https://shikimori.io/mangas/${id}`;
  }
  if (key.includes("mangadex")) return `https://mangadex.org/title/${id}`;
  if (key.includes("steam")) return `https://store.steampowered.com/app/${id}`;
  if (key.includes("tmdb") || key.includes("movie database")) {
    const kind = mediaType === "tvshow" ? "tv" : "movie";
    return `https://www.themoviedb.org/${kind}/${id}`;
  }
  if (key.includes("kinopoisk")) return `https://www.kinopoisk.ru/film/${id}/`;
  if (key.includes("rawg")) return `https://rawg.io/games/${id}`;
  if (key.includes("imdb")) return `https://www.imdb.com/title/${id}/`;
  if (key.includes("openlibrary")) {
    return `https://openlibrary.org${id.startsWith("/") ? id : `/${id}`}`;
  }
  if (key.includes("kitsu")) {
    // Kitsu keeps novels and manga in one /manga tree; only anime gets its own section.
    return mediaType === "anime" ? `https://kitsu.io/anime/${id}` : `https://kitsu.io/manga/${id}`;
  }
  if (key.includes("simkl")) return `https://simkl.com/${id}`;

  return null;
}
