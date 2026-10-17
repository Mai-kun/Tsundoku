using System.Globalization;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.ReadingSettings;

public interface IGetReadingSettingsHandler
{
    Task<Result<ReadingSettingsDto>> HandleAsync(CancellationToken ct);
}

public sealed class GetReadingSettingsHandler(AppDbContext db) : IGetReadingSettingsHandler
{
    public const string BookPageMinutesKey = "Reading_BookPageMinutes";
    public const string MangaChapterMinutesKey = "Reading_MangaChapterMinutes";
    public const double DefaultBookPageMinutes = 1.5;
    public const double DefaultMangaChapterMinutes = 6.0;

    public async Task<Result<ReadingSettingsDto>> HandleAsync(CancellationToken ct)
    {
        var bookVal = await AppSettingStore.ReadAsync(db, BookPageMinutesKey, ct);
        var mangaVal = await AppSettingStore.ReadAsync(db, MangaChapterMinutesKey, ct);

        var bookMinutes = double.TryParse(bookVal, CultureInfo.InvariantCulture, out var b) && b >= 0.2 && b <= 10.0
            ? b
            : DefaultBookPageMinutes;

        var mangaMinutes = double.TryParse(mangaVal, CultureInfo.InvariantCulture, out var m) && m >= 0.5 && m <= 30.0
            ? m
            : DefaultMangaChapterMinutes;

        return Result<ReadingSettingsDto>.Success(new ReadingSettingsDto(bookMinutes, mangaMinutes));
    }
}
