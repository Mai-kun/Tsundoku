using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.Import.Parsers;
using MediaTracker.Server.Infrastructure.ExternalApis;
using Xunit;

namespace MediaTracker.Tests;

public class AnixartCsvParserTests
{
    private const string SampleCsv = """
        #,Русское название,Оригинальное название,Альтернативные названия,Добавлено в избранное,Статус просмотра,Моя оценка
        1,Re:Zero. Жизнь с нуля в альтернативном мире,Re:Zero kara Hajimeru Isekai Seikatsu,Re: Life in a different world from zero,Добавлено,Просмотрено,5
        2,"Сто девушек, которые очень-очень-очень-очень-очень сильно любят тебя",Kimi no koto ga Daidaidaidaidaisuki na 100-nin no Kanojo,The 100 Girlfriends Who Really REALLY Love You,Добавлено,Не смотрю,Не оценено
        3,Магическая битва,Jujutsu Kaisen,Не указано,Не добавлено,Смотрю,4
        4,Атака титанов,Shingeki no Kyojin,Attack on Titan,Добавлено,Отложено,3
        5,Человек-бензопила,Chainsaw Man,CSM,Не добавлено,Брошено,2
        6,Клинок рассекающий демонов,Kimetsu no Yaiba,Demon Slayer,Добавлено,В планах,1
        7,Токийский гуль,Tokyo Ghoul,Tokyo Kushu,Не добавлено,Просмотрено,Не оценено
        8,Тайтл без оригинала,Не указано,Fate/Zero,Добавлено,Просмотрено,5
        9,Неизвестный тайтл,Не указаны,Не указаны,Не добавлено,Не смотрю,Не оценено
        """;

    [Fact]
    public void AnixartCsvParser_ShouldParseTitlesAndMapStatuses()
    {
        var items = AnixartCsvParser.Parse(SampleCsv, unwatchingStatus: MediaStatus.Planned, createFavoritesList: true);

        items.Should().HaveCount(9);

        // Item 1: Re:Zero - Completed, score 5 * 2 = 10, Favorites list, real status preserved
        var rezero = items[0];
        rezero.Title.Should().Be("Re:Zero. Жизнь с нуля в альтернативном мире");
        rezero.Type.Should().Be("anime");
        rezero.ExternalSource.Should().Be("Anixart");
        rezero.RomajiTitle.Should().Be("Re:Zero kara Hajimeru Isekai Seikatsu");
        rezero.OriginalTitle.Should().Be("Re: Life in a different world from zero");
        rezero.Status.Should().Be(MediaStatus.Completed);
        rezero.Score.Should().Be(10);
        rezero.FolderName.Should().Be("Избранное");
        rezero.IsCustomFolder.Should().BeTrue();

        // Item 2: 100 Girlfriends - "Не смотрю" mapped to unwatchingStatus (Planned), score null, in Favorites
        var girlfriends = items[1];
        girlfriends.Title.Should().Be("Сто девушек, которые очень-очень-очень-очень-очень сильно любят тебя");
        girlfriends.Status.Should().Be(MediaStatus.Planned);
        girlfriends.Score.Should().BeNull();
        girlfriends.FolderName.Should().Be("Избранное");
        girlfriends.IsCustomFolder.Should().BeTrue();

        // Item 3: Jujutsu Kaisen - "Не указано" for alt title becomes null, InProgress, score 4 * 2 = 8, not in favorites
        var jjk = items[2];
        jjk.Title.Should().Be("Магическая битва");
        jjk.RomajiTitle.Should().Be("Jujutsu Kaisen");
        jjk.OriginalTitle.Should().BeNull();
        jjk.Status.Should().Be(MediaStatus.InProgress);
        jjk.Score.Should().Be(8);
        jjk.FolderName.Should().BeNull();
        jjk.IsCustomFolder.Should().BeNull();

        // Item 4: Attack on Titan - OnHold, score 3 * 2 = 6, in Favorites
        var aot = items[3];
        aot.Status.Should().Be(MediaStatus.OnHold);
        aot.Score.Should().Be(6);
        aot.FolderName.Should().Be("Избранное");

        // Item 5: Chainsaw Man - Dropped, score 2 * 2 = 4
        var csm = items[4];
        csm.Status.Should().Be(MediaStatus.Dropped);
        csm.Score.Should().Be(4);

        // Item 6: Demon Slayer - Planned, score 1 * 2 = 2
        var kny = items[5];
        kny.Status.Should().Be(MediaStatus.Planned);
        kny.Score.Should().Be(2);

        // Item 8: Fallback to alt title when original is "Не указано"
        var fate = items[7];
        fate.Title.Should().Be("Тайтл без оригинала");
        fate.OriginalTitle.Should().Be("Fate/Zero");
        fate.RomajiTitle.Should().Be("Fate/Zero"); // Extracted Latin
    }

    [Fact]
    public void AnixartCsvParser_ShouldSkipUnwatching_WhenUnwatchingStatusIsNull()
    {
        // When unwatchingStatus is null (user chose "skip"), items with "Не смотрю" should be omitted
        var items = AnixartCsvParser.Parse(SampleCsv, unwatchingStatus: null, createFavoritesList: true);

        // Items 2 and 9 had "Не смотрю", so count should be 7
        items.Should().HaveCount(7);
        items.Should().NotContain(i => i.Title.Contains("Сто девушек"));
        items.Should().NotContain(i => i.Title == "Неизвестный тайтл");
    }

    [Fact]
    public void AnixartCsvParser_ShouldNotCreateFavorites_WhenDisabled()
    {
        var items = AnixartCsvParser.Parse(SampleCsv, unwatchingStatus: MediaStatus.Planned, createFavoritesList: false);

        items.Should().HaveCount(9);
        items.Should().OnlyContain(i => i.FolderName == null && i.IsCustomFolder == null);
    }

    [Fact]
    public void AnixartCsvParser_ShouldPreserve10PointScale_WhenMaxScoreExceeds5()
    {
        var csvWith10PointScale = """
            #,Русское название,Оригинальное название,Альтернативные названия,Добавлено в избранное,Статус просмотра,Моя оценка
            1,Врата Штейна,Steins;Gate,Steins Gate,Не добавлено,Просмотрено,10
            2,Ковбой Бибоп,Cowboy Bebop,Cowboy Bebop,Не добавлено,Просмотрено,9
            3,Тетрадь смерти,Death Note,Death Note,Не добавлено,Просмотрено,5
            """;

        var items = AnixartCsvParser.Parse(csvWith10PointScale);

        items[0].Score.Should().Be(10);
        items[1].Score.Should().Be(9);
        items[2].Score.Should().Be(5); // Not multiplied because max score is 10
    }

    [Fact]
    public void StrictCoverMatcher_ShouldRejectMismatchedSeasonOrLowScore()
    {
        var itemSeason1 = new TvShow
        {
            Title = "Re:Zero. Жизнь с нуля в альтернативном мире",
            RomajiTitle = "Re:Zero kara Hajimeru Isekai Seikatsu",
            ReleaseYear = 2016
        };

        var candSeason2 = new ExternalMediaDto
        {
            Type = "anime",
            Title = "Re:Zero kara Hajimeru Isekai Seikatsu 2nd Season",
            RomajiTitle = "Re:Zero kara Hajimeru Isekai Seikatsu 2nd Season",
            ExternalSource = "AniList",
            ExternalId = "108632",
            ReleaseYear = 2020,
            CoverUrl = "https://example.com/s2.jpg"
        };

        var candSeason1Shikimori = new ExternalMediaDto
        {
            Type = "anime",
            Title = "Re:Zero kara Hajimeru Isekai Seikatsu",
            RomajiTitle = "Re:Zero kara Hajimeru Isekai Seikatsu",
            ExternalSource = "Shikimori",
            ExternalId = "31240",
            ReleaseYear = 2016,
            CoverUrl = "https://example.com/s1.jpg"
        };

        // Season 2 cover must be rejected for Season 1 item
        StrictCoverMatcher.IsStrictMatch(itemSeason1, candSeason2).Should().BeFalse();

        // Exact season 1 match from Shikimori must be accepted
        StrictCoverMatcher.IsStrictMatch(itemSeason1, candSeason1Shikimori).Should().BeTrue();
    }

    [Fact]
    public void StrictCoverMatcher_ShouldRejectYearMismatch()
    {
        var movie = new Movie
        {
            Title = "Ghost in the Shell",
            RomajiTitle = "Ghost in the Shell",
            ReleaseYear = 1995
        };

        var remake = new ExternalMediaDto
        {
            Type = "movie",
            Title = "Ghost in the Shell",
            RomajiTitle = "Ghost in the Shell",
            ExternalSource = "TMDB",
            ExternalId = "12345",
            ReleaseYear = 2017,
            CoverUrl = "https://example.com/remake.jpg"
        };

        // Same title, but 1995 vs 2017 -> must be rejected
        StrictCoverMatcher.IsStrictMatch(movie, remake).Should().BeFalse();
    }
}
