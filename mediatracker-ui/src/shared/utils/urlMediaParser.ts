import type { SearchMediaType } from "$shared/types";

export interface ParsedMediaUrl {
  source: string;
  id: string;
  type: SearchMediaType;
}

const FORBIDDEN_SLUGS = new Set([
  "user",
  "users",
  "catalog",
  "bookmarks",
  "folder",
  "login",
  "register",
  "settings",
  "faq",
  "rules",
  "team",
  "teams",
  "latest",
]);

interface MatchRule {
  pattern: RegExp;
  source: string;
  type: SearchMediaType;
  extractId: (match: RegExpMatchArray) => string | null;
}

const RULES: MatchRule[] = [
  // AniList
  {
    pattern: /anilist\.co\/anime\/(\d+)/i,
    source: "anilist",
    type: "anime",
    extractId: (m) => m[1],
  },
  {
    pattern: /anilist\.co\/manga\/(\d+)/i,
    source: "anilist",
    type: "manga",
    extractId: (m) => m[1],
  },

  // Shikimori
  {
    pattern: /shikimori\.(?:one|me|io)\/animes\/(?:z?(\d+)|(\d+))/i,
    source: "shikimori",
    type: "anime",
    extractId: (m) => m[1] || m[2],
  },
  {
    pattern: /shikimori\.(?:one|me|io)\/mangas\/(?:z?(\d+)|(\d+))/i,
    source: "shikimori",
    type: "manga",
    extractId: (m) => m[1] || m[2],
  },

  // MangaDex
  {
    pattern: /mangadex\.org\/title\/([a-f0-9\-]+)/i,
    source: "mangadex",
    type: "manga",
    extractId: (m) => m[1],
  },

  // TMDb
  {
    pattern: /themoviedb\.org\/movie\/(\d+)/i,
    source: "tmdb",
    type: "movie",
    extractId: (m) => m[1],
  },
  {
    pattern: /themoviedb\.org\/tv\/(\d+)/i,
    source: "tmdb",
    type: "tvshow",
    extractId: (m) => m[1],
  },

  // IMDb
  {
    pattern: /imdb\.com\/title\/(tt\d+)/i,
    source: "imdb",
    type: "movie",
    extractId: (m) => m[1],
  },

  // Steam
  {
    pattern: /store\.steampowered\.com\/app\/(\d+)/i,
    source: "steam",
    type: "game",
    extractId: (m) => m[1],
  },

  // RAWG
  {
    pattern: /rawg\.io\/games\/([a-z0-9\-]+)/i,
    source: "rawg",
    type: "game",
    extractId: (m) => m[1],
  },

  // RanobeLib / MangaLib
  {
    pattern: /ranobelib\.me\/(?:ru\/)?([a-z0-9\-]+)/i,
    source: "ranobelib",
    type: "book",
    extractId: (m) => {
      const id = m[1].toLowerCase();
      return FORBIDDEN_SLUGS.has(id) ? null : m[1];
    },
  },
  {
    pattern: /mangalib\.me\/(?:ru\/)?([a-z0-9\-]+)/i,
    source: "mangalib",
    type: "manga",
    extractId: (m) => {
      const id = m[1].toLowerCase();
      return FORBIDDEN_SLUGS.has(id) ? null : m[1];
    },
  },
  {
    pattern: /animelib\.(?:me|org)\/(?:ru\/)?([a-z0-9\-]+)/i,
    source: "animelib",
    type: "anime",
    extractId: (m) => {
      const id = m[1].toLowerCase();
      return FORBIDDEN_SLUGS.has(id) ? null : m[1];
    },
  },

  // Kitsu
  {
    pattern: /kitsu\.(?:app|io)\/anime\/([a-z0-9\-]+)/i,
    source: "kitsu",
    type: "anime",
    extractId: (m) => m[1],
  },
  {
    pattern: /kitsu\.(?:app|io)\/manga\/([a-z0-9\-]+)/i,
    source: "kitsu",
    type: "manga",
    extractId: (m) => m[1],
  },
];

/**
 * Parses a media URL and returns the detected source, external ID, and media type.
 * Returns null if the URL is not recognized or not a valid media link.
 */
export function parseMediaUrl(input: string): ParsedMediaUrl | null {
  if (!input || typeof input !== "string") return null;
  const trimmed = input.trim();
  if (!trimmed) return null;

  for (const rule of RULES) {
    const match = trimmed.match(rule.pattern);
    if (match) {
      const id = rule.extractId(match);
      if (id) {
        return {
          source: rule.source,
          id,
          type: rule.type,
        };
      }
    }
  }

  return null;
}
