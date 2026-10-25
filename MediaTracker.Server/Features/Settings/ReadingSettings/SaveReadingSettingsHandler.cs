using System.Globalization;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Settings.ReadingSettings;

public interface ISaveReadingSettingsHandler
{
    Task<Result<ReadingSettingsDto>> HandleAsync(ReadingSettingsDto command, CancellationToken ct);
}

public sealed class SaveReadingSettingsHandler(AppDbContext db, IMemoryCache cache) : ISaveReadingSettingsHandler
{
    public async Task<Result<ReadingSettingsDto>> HandleAsync(ReadingSettingsDto command, CancellationToken ct)
    {
        if (double.IsNaN(command.BookPageMinutes) || double.IsInfinity(command.BookPageMinutes) ||
            command.BookPageMinutes < 0.2 || command.BookPageMinutes > 10.0)
        {
            return Result<ReadingSettingsDto>.Failure(
                Error.Validation("Скорость чтения книг должна быть от 0.2 до 10.0 минут на страницу."));
        }

        if (double.IsNaN(command.MangaChapterMinutes) || double.IsInfinity(command.MangaChapterMinutes) ||
            command.MangaChapterMinutes < 0.5 || command.MangaChapterMinutes > 30.0)
        {
            return Result<ReadingSettingsDto>.Failure(
                Error.Validation("Скорость чтения манги должна быть от 0.5 до 30.0 минут на главу."));
        }

        await AppSettingStore.SetAsync(
            db,
            GetReadingSettingsHandler.BookPageMinutesKey,
            command.BookPageMinutes.ToString("0.0#", CultureInfo.InvariantCulture),
            ct);

        await AppSettingStore.SetAsync(
            db,
            GetReadingSettingsHandler.MangaChapterMinutesKey,
            command.MangaChapterMinutes.ToString("0.0#", CultureInfo.InvariantCulture),
            ct);

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);

        return Result<ReadingSettingsDto>.Success(command);
    }
}
