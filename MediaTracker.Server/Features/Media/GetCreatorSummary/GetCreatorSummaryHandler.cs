using System.Data;
using Dapper;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;

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
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        IEnumerable<MediaItemRow> rows = role switch
        {
            "director" => await conn.QueryAsync<MediaItemRow>(
                "SELECT * FROM MediaItems WHERE Movie_Director = @name", new { name }),
            "author" => await conn.QueryAsync<MediaItemRow>(
                "SELECT * FROM MediaItems WHERE (MediaType = 'Book' AND Author = @name) OR (MediaType = 'Manga' AND Manga_Author = @name)", new { name }),
            "studio" => await conn.QueryAsync<MediaItemRow>(
                "SELECT * FROM MediaItems WHERE (MediaType = 'Movie' AND Movie_Studio = @name) OR (MediaType = 'TvShow' AND (TvShow_Studio = @name OR TvShow_RomajiTitle = @name OR Network = @name)) OR (MediaType = 'Game' AND Studio = @name)", new { name }),
            _ => []
        };

        var items = rows.Select(r => r.ToEntity()).ToList();
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
