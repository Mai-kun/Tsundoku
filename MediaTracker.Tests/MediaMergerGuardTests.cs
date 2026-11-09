using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using Xunit;

namespace MediaTracker.Tests;

public class MediaMergerGuardTests
{
    [Fact]
    public void LittlePrinceClassic_Vs_CryptPrinceWebnovel_MustNotMatch()
    {
        var classicPrince = new Book
        {
            Title = "Маленький принц",
            Author = "Антуан де Сент-Экзюпери",
            ReleaseYear = 1943,
            Format = "Book",
            TotalPages = 96,
        };

        var cryptPrinceCandidate = new ExternalMediaDto
        {
            ExternalId = "ranobelib-prince-crypt",
            Title = "Маленький принц со склепа",
            Author = "산하 (San-ha)",
            ReleaseYear = 2010,
            Type = "book",
            MangaFormat = "novel",
            ExternalSource = "RanobeLib",
            Chapters = 185,
            Genres = ["Драма", "Фэнтези", "Хентай", "Эччи"],
        };

        var score = ImportMatchScorer.ScoreCandidate(classicPrince, cryptPrinceCandidate, out var hasContradiction);
        score.Should().Be(0);
        hasContradiction.Should().BeTrue();

        var verdict = ImportMatchScorer.EvaluateCandidates(classicPrince, [cryptPrinceCandidate]);
        verdict.Kind.Should().Be(MatchVerdictKind.NoMatch);

        var scored = new ScoredCandidate(cryptPrinceCandidate, score, hasContradiction);
        ImportMatchScorer.CanAutoMatch(classicPrince, scored).Should().BeFalse();

        var classicDto = new ExternalMediaDto
        {
            ExternalId = "livelib-prince",
            Title = "Маленький принц",
            Author = "Антуан де Сент-Экзюпери",
            ReleaseYear = 1943,
            Type = "book",
            ExternalSource = "LiveLib",
        };

        var strictMatch = MetadataAggregatorService.FindStrictEnrichmentMatch(
            classicDto,
            [cryptPrinceCandidate],
            "RanobeLib");

        strictMatch.Should().BeNull();
    }

    [Fact]
    public void AuthorGuard_DifferentAuthors_ShouldScoreZero()
    {
        var book = new Book
        {
            Title = "Война и мир",
            Author = "Лев Толстой",
            ReleaseYear = 1869,
        };

        var candidate = new ExternalMediaDto
        {
            ExternalId = "diff-author-1",
            Title = "Война и мир",
            Author = "Иван Иванов",
            ReleaseYear = 1869,
            Type = "book",
        };

        var score = ImportMatchScorer.ScoreCandidate(book, candidate, out var hasContradiction);
        score.Should().Be(0);
        hasContradiction.Should().BeTrue();

        var verdict = ImportMatchScorer.EvaluateCandidates(book, [candidate]);
        verdict.Kind.Should().Be(MatchVerdictKind.NoMatch);
    }

    [Fact]
    public void AuthorGuard_TransliteratedOrAliasedAuthor_ShouldMatch()
    {
        var book = new Book
        {
            Title = "The Little Prince",
            Author = "Antoine de Saint-Exupéry",
            ReleaseYear = 1943,
        };

        var candidate = new ExternalMediaDto
        {
            ExternalId = "saint-exupery-ru",
            Title = "The Little Prince",
            Author = "Антуан де Сент-Экзюпери",
            ReleaseYear = 1943,
            Type = "book",
            ExternalSource = "LiveLib",
        };

        var score = ImportMatchScorer.ScoreCandidate(book, candidate, out var hasContradiction);
        score.Should().BeGreaterThanOrEqualTo(75);
        hasContradiction.Should().BeFalse();

        var verdict = ImportMatchScorer.EvaluateCandidates(book, [candidate]);
        verdict.Kind.Should().Be(MatchVerdictKind.Confident);
    }

    [Fact]
    public void YearGuard_YearDiffGreaterThanThree_ZeroesScoreUnlessExactTitle()
    {
        var book = new Book
        {
            Title = "Приключения Тома Сойера",
            Author = "Марк Твен",
            ReleaseYear = 1876,
        };

        var distantYearCandidate = new ExternalMediaDto
        {
            ExternalId = "distant-1",
            Title = "Приключения Тома Сойера: Новые истории",
            Author = "Марк Твен",
            ReleaseYear = 2015,
            Type = "book",
        };

        var score = ImportMatchScorer.ScoreCandidate(book, distantYearCandidate, out var contradiction);
        score.Should().Be(0);
        contradiction.Should().BeTrue();
    }

    [Fact]
    public void SubstringMatching_NonNoiseDifference_RejectsMatch()
    {
        var book = new Book
        {
            Title = "Маленький принц",
            Author = null,
        };

        var longerCandidate = new ExternalMediaDto
        {
            ExternalId = "long-1",
            Title = "Маленький принц со склепа",
            Type = "book",
        };

        var score = ImportMatchScorer.ScoreCandidate(book, longerCandidate, out _);
        score.Should().Be(0);
    }

    [Fact]
    public void ClassicBookIsolation_AsianNovelProvider_BlockedWithoutExactTitleAndAuthor()
    {
        var classicDto = new ExternalMediaDto
        {
            ExternalId = "classic-1",
            Title = "Преступление и наказание",
            Author = "Фёдор Достоевский",
            ReleaseYear = 1866,
            Type = "book",
            ExternalSource = "LiveLib",
        };

        var ranobeCandidate = new ExternalMediaDto
        {
            ExternalId = "ranobe-1",
            Title = "Преступление и наказание в другом мире",
            Author = "Автор Ранобэ",
            ReleaseYear = 2020,
            Type = "book",
            ExternalSource = "RanobeLib",
        };

        var match = MetadataAggregatorService.FindStrictEnrichmentMatch(
            classicDto,
            [ranobeCandidate],
            "RanobeLib");

        match.Should().BeNull();
    }

    [Fact]
    public void MediaMerger_ClassicBook_CannotBeOverwrittenWithLightNovelOrChaptersOrAdultGenres()
    {
        var primaryClassic = new ExternalMediaDto
        {
            ExternalId = "1000000001",
            ExternalSource = "LiveLib",
            Title = "Маленький принц",
            Author = "Антуан де Сент-Экзюпери",
            Type = "book",
            TotalCount = 96,
            ReleaseYear = 1943,
            Genres = ["Сказка", "Классика"],
        };

        var secondaryRanobe = new ExternalMediaDto
        {
            ExternalId = "ranobelib-crypt-prince",
            ExternalSource = "RanobeLib",
            Title = "Маленький принц со склепа",
            Author = "산ха",
            Type = "book",
            Format = "light_novel",
            MangaFormat = "novel",
            Chapters = 250,
            TotalCount = 250,
            Genres = ["Фэнтези", "Хентай", "Эччи", "18+", "Драма"],
        };

        var merged = MediaMerger.Merge(primaryClassic, secondaryRanobe);

        merged.Title.Should().Be("Маленький принц");
        merged.Author.Should().Be("Антуан де Сент-Экзюпери");
        merged.TotalCount.Should().Be(96);
        merged.Chapters.Should().BeNull();
        merged.Format.Should().NotBe("light_novel");
        merged.MangaFormat.Should().BeNull();

        merged.Genres.Should().Contain("Fantasy");
        merged.Genres.Should().Contain("Drama");
        merged.Genres.Should().NotContain("Хентай");
        merged.Genres.Should().NotContain("Hentai");
        merged.Genres.Should().NotContain("Эччи");
        merged.Genres.Should().NotContain("Ecchi");
        merged.Genres.Should().NotContain("18+");
    }

    [Fact]
    public void MediaMetadataApplier_ClassicBook_DoesNotApplyLightNovelOrChapters()
    {
        var book = new Book
        {
            Title = "Маленький принц",
            Author = "Антуан де Сент-Экзюпери",
            TotalPages = 96,
            CurrentPage = 20,
            Format = "Book",
            ExternalSource = "LiveLib",
        };

        var ranobeCandidate = new ExternalMediaDto
        {
            ExternalId = "ranobelib-1",
            Title = "Маленький принц",
            Format = "light_novel",
            Chapters = 200,
            Type = "book",
            ExternalSource = "RanobeLib",
        };

        MediaMetadataApplier.ApplyIfMissing(book, ranobeCandidate);

        book.Format.Should().Be("Book");
        book.TotalPages.Should().Be(96);
        book.CurrentPage.Should().Be(20);
    }
}
