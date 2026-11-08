import { describe, expect, it } from "vitest";
import { parseMediaUrl } from "../urlMediaParser";

describe("parseMediaUrl", () => {
  it("parses AniList anime and manga URLs", () => {
    expect(parseMediaUrl("https://anilist.co/anime/118408/")).toEqual({
      source: "anilist",
      id: "118408",
      type: "anime",
    });
    expect(parseMediaUrl("https://anilist.co/manga/118408/lydias-great-escape")).toEqual({
      source: "anilist",
      id: "118408",
      type: "manga",
    });
    expect(parseMediaUrl("anilist.co/manga/54321")).toEqual({
      source: "anilist",
      id: "54321",
      type: "manga",
    });
  });

  it("parses Shikimori anime and manga URLs across domains and with z prefix", () => {
    expect(parseMediaUrl("https://shikimori.one/animes/z12345-title")).toEqual({
      source: "shikimori",
      id: "12345",
      type: "anime",
    });
    expect(parseMediaUrl("https://shikimori.me/animes/54321")).toEqual({
      source: "shikimori",
      id: "54321",
      type: "anime",
    });
    expect(parseMediaUrl("https://shikimori.io/mangas/9999")).toEqual({
      source: "shikimori",
      id: "9999",
      type: "manga",
    });
    expect(parseMediaUrl("shikimori.me/mangas/z8888-manga-slug")).toEqual({
      source: "shikimori",
      id: "8888",
      type: "manga",
    });
    // Any future TLD parses too: the domain moves regularly, the mask must not care.
    expect(parseMediaUrl("https://shikimori.app/animes/777")).toEqual({
      source: "shikimori",
      id: "777",
      type: "anime",
    });
    expect(parseMediaUrl("https://shikimori.wtf/mangas/1234-some-title")).toEqual({
      source: "shikimori",
      id: "1234",
      type: "manga",
    });
  });

  it("parses MangaDex title URLs", () => {
    expect(
      parseMediaUrl(
        "https://mangadex.org/title/a9667631-b79e-4721-9749-cbf975a5a032/sousou-no-frieren",
      ),
    ).toEqual({
      source: "mangadex",
      id: "a9667631-b79e-4721-9749-cbf975a5a032",
      type: "manga",
    });
    expect(parseMediaUrl("mangadex.org/title/a9667631-b79e-4721-9749-cbf975a5a032")).toEqual({
      source: "mangadex",
      id: "a9667631-b79e-4721-9749-cbf975a5a032",
      type: "manga",
    });
  });

  it("parses TMDb movie and tv URLs", () => {
    expect(parseMediaUrl("https://www.themoviedb.org/movie/550-fight-club")).toEqual({
      source: "tmdb",
      id: "550",
      type: "movie",
    });
    expect(parseMediaUrl("https://www.themoviedb.org/tv/1399-game-of-thrones")).toEqual({
      source: "tmdb",
      id: "1399",
      type: "tvshow",
    });
  });

  it("parses IMDb title URLs", () => {
    expect(parseMediaUrl("https://www.imdb.com/title/tt0111161/")).toEqual({
      source: "imdb",
      id: "tt0111161",
      type: "movie",
    });
  });

  it("parses Steam app URLs", () => {
    expect(parseMediaUrl("https://store.steampowered.com/app/1086940/Baldurs_Gate_3/")).toEqual({
      source: "steam",
      id: "1086940",
      type: "game",
    });
  });

  it("parses RAWG game URLs", () => {
    expect(parseMediaUrl("https://rawg.io/games/the-witcher-3-wild-hunt")).toEqual({
      source: "rawg",
      id: "the-witcher-3-wild-hunt",
      type: "game",
    });
  });

  it("parses RanobeLib, MangaLib, and AnimeLib URLs", () => {
    expect(parseMediaUrl("https://ranobelib.me/ru/1234-some-novel")).toEqual({
      source: "ranobelib",
      id: "1234-some-novel",
      type: "book",
    });
    expect(parseMediaUrl("https://mangalib.me/some-manga")).toEqual({
      source: "mangalib",
      id: "some-manga",
      type: "manga",
    });
    expect(parseMediaUrl("https://animelib.org/some-anime")).toEqual({
      source: "animelib",
      id: "some-anime",
      type: "anime",
    });
    // The live AnimeLib shape: versioned subdomain, mandatory /ru/anime/ prefixes.
    expect(parseMediaUrl("https://v5.animelib.org/ru/anime/8231--noragami-anime")).toEqual({
      source: "animelib",
      id: "8231--noragami-anime",
      type: "anime",
    });
    // Future version bumps and unknown TLDs parse the same way.
    expect(parseMediaUrl("https://v6.animelib.app/ru/anime/8231--noragami-anime")).toEqual({
      source: "animelib",
      id: "8231--noragami-anime",
      type: "anime",
    });
    // System pages should return null
    expect(parseMediaUrl("https://mangalib.me/ru/catalog")).toBeNull();
    expect(parseMediaUrl("https://mangalib.me/bookmarks")).toBeNull();
    expect(parseMediaUrl("https://v5.animelib.org/ru/anime/catalog")).toBeNull();
  });

  it("parses Kitsu anime and manga URLs", () => {
    expect(parseMediaUrl("https://kitsu.app/anime/cowboy-bebop")).toEqual({
      source: "kitsu",
      id: "cowboy-bebop",
      type: "anime",
    });
    expect(parseMediaUrl("https://kitsu.io/manga/berserk")).toEqual({
      source: "kitsu",
      id: "berserk",
      type: "manga",
    });
  });

  it("returns null for non-URLs and regular search strings", () => {
    expect(parseMediaUrl("")).toBeNull();
    expect(parseMediaUrl("Naruto")).toBeNull();
    expect(parseMediaUrl("https://google.com/search?q=test")).toBeNull();
  });
});
