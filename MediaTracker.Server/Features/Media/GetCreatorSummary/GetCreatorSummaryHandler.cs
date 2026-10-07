using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetCreatorSummary;

public sealed record CreatorSummaryDto(
    string Name,
    string Role,
    int TotalCount,
    int CompletedCount,
    double? AverageScore,
    IReadOnlyList<MediaListDto> OtherItems);

public interface IGetCreatorSummaryHandler
{
    Task<CreatorSummaryDto> HandleAsync(string name, string role, Guid? excludeId, CancellationToken ct);
}

public sealed class GetCreatorSummaryHandler(AppDbContext db) : IGetCreatorSummaryHandler
{
    public async Task<CreatorSummaryDto> HandleAsync(
        string name,
        string role,
        Guid? excludeId,
        CancellationToken ct)
    {
        var query = db.MediaItems.AsNoTracking().Include(item => item.Franchise);

        IQueryable<MediaItem> matchingItems = role switch
        {
            "director" => query.Where(item => ((Movie)item).Director == name),
            "author" => query.Where(item =>
                item is Book && ((Book)item).Author == name
                || item is Manga && ((Manga)item).Author == name),
            "studio" => query
                .Include(item => (item as TvShow)!.Seasons)
                .Where(item =>
                    item is Movie && ((Movie)item).Studio == name
                    || item is TvShow && (((TvShow)item).Studio == name || ((TvShow)item).Network == name)),
            _ => query.Where(_ => false),
        };

        var items = await matchingItems.ToListAsync(ct);
        var scores = items.Where(item => item.Score.HasValue).Select(item => (double)item.Score!.Value).ToArray();
        var others = items
            .Where(item => item.Id != excludeId)
            .OrderByDescending(item => item.Score.HasValue)
            .ThenByDescending(item => item.Score)
            .ThenBy(item => item.Title)
            .Take(8)
            .Select(MediaResponseMapper.ToListDto)
            .ToArray();

        return new CreatorSummaryDto(
            name,
            role,
            items.Count,
            items.Count(item => item.Status == MediaStatus.Completed),
            scores.Length > 0 ? Math.Round(scores.Average(), 1) : null,
            others);
    }
}
