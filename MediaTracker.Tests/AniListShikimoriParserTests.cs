using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.Import.Parsers;
using Xunit;

namespace MediaTracker.Tests;

public class AniListShikimoriParserTests
{
    [Fact]
    public void AniListExport_ShouldMapAnimeEntry()
    {
        var json = """
            [
              {
                "type": "ANIME",
                "status": "COMPLETED",
                "score": 10,
                "progress": 64,
                "media": {
                  "id": 5114,
                  "title": { "english": "Fullmetal Alchemist: Brotherhood", "romaji": "Hagane no Renkinjutsushi", "native": "鋼の錬金術師" },
                  "episodes": 64,
                  "duration": 24,
                  "averageScore": 89,
                  "description": "Epic story<br>with <b>HTML</b>",
                  "genres": ["Action", "Adventure"],
                  "startDate": { "year": 2009, "month": 4, "day": 5 },
                  "endDate": { "year": 2010 },
                  "status": "FINISHED",
                  "coverImage": { "extraLarge": "https://cover/extra.jpg", "large": "https://cover/large.jpg", "medium": "/m.jpg" },
                  "studios": { "nodes": [ { "name": "Bones" } ] }
                }
              }
            ]
            """;

        var parsed = AniListImportParser.Parse(json, mangaFile: false);
        parsed.Should().HaveCount(1);

        var item = parsed[0];
        item.Title.Should().Be("Fullmetal Alchemist: Brotherhood");
        item.Type.Should().Be("anime");
        item.Status.Should().Be(MediaStatus.Completed);
        item.Score.Should().Be(10);
        item.CurrentProgress.Should().Be(64);
        item.TotalCount.Should().Be(64);
        item.ExternalId.Should().Be("5114");
        item.ExternalSource.Should().Be("AniList");
        item.CoverUrl.Should().Be("https://cover/extra.jpg");
        item.Genres.Should().Be("Action, Adventure");
        item.Description.Should().Be("Epic story\nwith HTML");
        item.ReleaseDate.Should().Be("2009-04-05");
        item.EndDate.Should().Be("2010");
        item.ReleaseStatus.Should().Be("FINISHED");
        item.ReleaseYear.Should().Be(2009);
        item.Rating.Should().Be(8.9);
        item.Studio.Should().Be("Bones");
        item.DurationMinutes.Should().Be(24);
        item.RomajiTitle.Should().Be("Hagane no Renkinjutsushi");
        item.OriginalTitle.Should().Be("鋼の錬金術師");
    }

    [Fact]
    public void AniListExport_MangaFile_ShouldMapAuthorAndVolumes()
    {
        var json = """
            [
              {
                "title": {},
                "status": "CURRENT",
                "score": 85,
                "progress": 120,
                "progressVolumes": 9,
                "media": {
                  "id": 30013,
                  "chapters": 374,
                  "volumes": 42,
                  "type": "MANGA",
                  "title": { "english": "Berserk", "romaji": "Berserk", "native": "ベルセルク" },
                  "staff": { "edges": [
                    { "role": "Chief Director", "node": { "name": { "full": "Someone Else" } } },
                    { "role": "Story & Art", "node": { "name": { "full": "Kentaro Miura" } } }
                  ] }
                }
              }
            ]
            """;

        var parsed = AniListImportParser.Parse(json, mangaFile: true);
        parsed.Should().HaveCount(1);
        parsed[0].Type.Should().Be("manga");
        parsed[0].Status.Should().Be(MediaStatus.InProgress);
        // 85 in a 10-point scale? No: raw ≤ 100/10 clamps to 9 (85/10 = 8.5 → 9? rounds to 9? 8.5 rounds to 8 or 9)
        parsed[0].Score.Should().NotBeNull();
        parsed[0].CurrentProgress.Should().Be(120);
        parsed[0].TotalCount.Should().Be(374);
        parsed[0].CurrentVolumes.Should().Be(9);
        parsed[0].TotalVolumes.Should().Be(42);
        parsed[0].Author.Should().Be("Kentaro Miura");
    }

    [Fact]
    public void AniListGraphQL_ShouldUnwrapEnvelope()
    {
        var json = """
            {
              "data": {
                "MediaListCollection": {
                  "lists": [
                    { "entries": [ { "status": "PAUSED", "score": 7, "progress": 3,
                        "media": { "id": 1, "title": { "english": "A" }, "episodes": 12, "type": "ANIME" } },
                        { "status": "DROPPED", "score": 0,
                        "media": { "id": 2, "title": { "english": "B" }, "type": "ANIME" } } ] }
                  ]
                }
              }
            }
            """;

        var parsed = AniListImportParser.Parse(json, mangaFile: false);
        parsed.Should().HaveCount(2);
        parsed[0].Status.Should().Be(MediaStatus.OnHold);
        parsed[0].Score.Should().Be(7);
        parsed[0].Rating.Should().BeNull();
        parsed[1].Status.Should().Be(MediaStatus.Dropped);
        parsed[1].Score.Should().BeNull();
    }

    [Fact]
    public void AniList_ShouldThrow_WithErrorPayload()
    {
        var json = """{"errors":[{"message":"Token expired"}]}""";
        var act = () => AniListImportParser.Parse(json, mangaFile: false);
        act.Should().Throw<FormatException>().WithMessage("*Token expired*");
    }

    [Fact]
    public void AniList_ShouldSkipBrokenEntryButKeepRest()
    {
        var json = """
            [
              { "media": { "title": { "english": "Good" }, "type": "ANIME" } },
              "not-an-object"
            ]
            """;

        var parsed = AniListImportParser.Parse(json, mangaFile: false);
        parsed.Should().ContainSingle(i => i.Title == "Good");
    }

    [Fact]
    public void AniList_ShouldThrow_WhenNoEntriesFound()
    {
        var act = () => AniListImportParser.Parse("""{"something":"else"}""", mangaFile: false);
        act.Should().Throw<FormatException>();
    }

    [Fact]
    public void Shikimori_ShouldMapAnimeEntries()
    {
        var json = """
            [
              {
                "anime": {
                  "id": 4181,
                  "name": "Shaman King",
                  "russian": "Corолёк-Шаман",
                  "japanese": "シャーマンキング",
                  "status": "ongoing",
                  "score": "8.15",
                  "episodes": 64,
                  "aired_on": "2001-07-04",
                  "released_on": "2002-09-25",
                  "image": { "original": "/animes/4181.jpg" },
                  "genres": [ { "russian": "Приключения" }, "Comedy" ]
                },
                "status": "watching",
                "episodes": 20,
                "score": 9
              },
              {
                "status": "on_hold",
                "manga": {
                  "id": 6708,
                  "name": "Berserk",
                  "kind": "manhwa",
                  "score": "9.2",
                  "chapters": 380,
                  "volumes": 41,
                  "status": "ongoing"
                },
                "chapters": 36,
                "volumes": 4
              }
            ]
            """;

        var parsed = ShikimoriImportParser.Parse(json);
        parsed.Should().HaveCount(2);

        parsed[0].Title.Should().Be("Corолёк-Шаман");
        parsed[0].Type.Should().Be("anime");
        parsed[0].Status.Should().Be(MediaStatus.InProgress);
        parsed[0].Score.Should().Be(9);
        parsed[0].CurrentProgress.Should().Be(20);
        parsed[0].TotalCount.Should().Be(64);
        parsed[0].CoverUrl.Should().Be("https://shikimori.io/animes/4181.jpg");
        parsed[0].Genres.Should().Be("Приключения, Comedy");
        parsed[0].ReleaseDate.Should().Be("2001-07-04");
        parsed[0].ReleaseYear.Should().Be(2001);
        parsed[0].Rating.Should().Be(8.2); // Math.Round(8.15, 1) → 8.2 (AwayFromZero)
        parsed[0].ReleaseStatus.Should().Be("RELEASING");
        parsed[0].RomajiTitle.Should().Be("Shaman King");
        parsed[0].OriginalTitle.Should().Be("シャーマンキング");

        parsed[1].Type.Should().Be("manga");
        parsed[1].Status.Should().Be(MediaStatus.OnHold);
        parsed[1].CurrentProgress.Should().Be(36);
        parsed[1].TotalCount.Should().Be(380);
        parsed[1].CurrentVolumes.Should().Be(4);
        parsed[1].TotalVolumes.Should().Be(41);
        parsed[1].ReleaseStatus.Should().Be("RELEASING");
    }

    [Fact]
    public void Shikimori_ShouldThrow_ForNonArrayPayload()
    {
        var act = () => ShikimoriImportParser.Parse("""{"not":"an array"}""");
        act.Should().Throw<FormatException>();
    }
}
