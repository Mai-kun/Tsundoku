using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.OpenLibrary;
using MediaTracker.Server.Infrastructure.Persistence;
using Xunit;

namespace MediaTracker.Tests;

public sealed class OpenLibraryProviderTests
{
    [Fact]
    public void DescriptionConverter_HandlesStringAndObjectFormat()
    {
        var jsonWithString = """{"description": "A classic novella about a prince."}""";
        var work1 = JsonSerializer.Deserialize<OpenLibraryWork>(jsonWithString, AppJsonSerializerContext.Default.OpenLibraryWork);
        Assert.NotNull(work1);
        Assert.Equal("A classic novella about a prince.", work1.Description);

        var jsonWithObject = """{"description": {"type": "/type/text", "value": "A deep philosophical tale."}}""";
        var work2 = JsonSerializer.Deserialize<OpenLibraryWork>(jsonWithObject, AppJsonSerializerContext.Default.OpenLibraryWork);
        Assert.NotNull(work2);
        Assert.Equal("A deep philosophical tale.", work2.Description);

        var jsonWithNull = """{"description": null}""";
        var work3 = JsonSerializer.Deserialize<OpenLibraryWork>(jsonWithNull, AppJsonSerializerContext.Default.OpenLibraryWork);
        Assert.NotNull(work3);
        Assert.Null(work3.Description);
    }

    [Fact]
    public void MapPhysicalFormat_MapsCorrectly()
    {
        Assert.Equal("Мягкая обложка", OpenLibraryMetadataProvider.MapPhysicalFormat("Paperback"));
        Assert.Equal("Мягкая обложка", OpenLibraryMetadataProvider.MapPhysicalFormat("Pocket book"));
        Assert.Equal("Твёрдый переплёт", OpenLibraryMetadataProvider.MapPhysicalFormat("Hardcover"));
        Assert.Equal("Твёрдый переплёт", OpenLibraryMetadataProvider.MapPhysicalFormat("Hardback"));
        Assert.Equal("Электронная книга", OpenLibraryMetadataProvider.MapPhysicalFormat("ebook"));
        Assert.Equal("Аудиокнига", OpenLibraryMetadataProvider.MapPhysicalFormat("Audiobook"));
        Assert.Null(OpenLibraryMetadataProvider.MapPhysicalFormat(null));
        Assert.Null(OpenLibraryMetadataProvider.MapPhysicalFormat("   "));
    }

    [Fact]
    public void ExtractIsbn_Prefers13Digits_Then10Digits()
    {
        var isbns = new List<string> { "0140328726", "978-0-14-032872-1" };
        var result = OpenLibraryMetadataProvider.ExtractIsbn(isbns);
        Assert.Equal("978-0-14-032872-1", result);

        var only10 = new List<string> { "0140328726" };
        Assert.Equal("0140328726", OpenLibraryMetadataProvider.ExtractIsbn(only10));
    }

    [Fact]
    public void NormalizeSubjects_FiltersOutNonGenreTropes()
    {
        var subjects = new List<string> { "friendship", "love", "loss", "Fantasy", "Adventure" };
        var normalized = OpenLibraryMetadataProvider.NormalizeSubjects(subjects);

        Assert.NotNull(normalized);
        Assert.DoesNotContain("friendship", normalized, StringComparer.OrdinalIgnoreCase);
        Assert.DoesNotContain("love", normalized, StringComparer.OrdinalIgnoreCase);
        Assert.DoesNotContain("loss", normalized, StringComparer.OrdinalIgnoreCase);
        Assert.Contains(normalized, s => s.Equals("Фэнтези", StringComparison.OrdinalIgnoreCase) || s.Equals("Fantasy", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(normalized, s => s.Equals("Приключения", StringComparison.OrdinalIgnoreCase) || s.Equals("Adventure", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void MediaItemRow_MapsIsbnAndPublisherForBook()
    {
        var book = new Book
        {
            Id = Guid.NewGuid(),
            Title = "The Little Prince",
            Author = "Antoine de Saint-Exupéry",
            Publisher = "Reynal & Hitchcock",
            Isbn = "978-0156012195",
            TotalPages = 96,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            SyncStatus = SyncStatus.Ready,
        };

        var row = MediaItemRow.FromEntity(book);
        Assert.Equal("978-0156012195", row.Isbn);
        Assert.Equal("Reynal & Hitchcock", row.Studio);

        var reconstructed = (Book)row.ToEntity();
        Assert.Equal("978-0156012195", reconstructed.Isbn);
        Assert.Equal("Reynal & Hitchcock", reconstructed.Publisher);
    }
}
