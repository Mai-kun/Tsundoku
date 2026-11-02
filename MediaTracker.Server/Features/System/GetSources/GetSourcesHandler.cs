using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Offline;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Features.System.GetSources;

public sealed class GetSourcesHandler(
    IEnumerable<IMetadataProvider> providers,
    IOptions<ExternalApiOptions> options,
    ISourcePriorityService priorityService,
    OfflineDatabaseManager? dbManager = null) : IGetSourcesHandler
{
    public async Task<Result<IReadOnlyList<SourceInfo>>> HandleAsync(CancellationToken ct)
    {
        var disabled = await priorityService.GetDisabledSourcesAsync(ct);

        var sources = providers
            .DistinctBy(provider => provider.Id)
            .Select(provider =>
            {
                var key = options.Value.GetKey(provider.Id);
                // A provider that works without a key is always configured; HasKey only reflects
                // whether an (optional) key was actually saved.
                var hasKey = !string.IsNullOrWhiteSpace(key);
                var isConfigured = !provider.RequiresApiKey || hasKey;
                if (provider is UniversalOfflineMetadataProvider offline)
                {
                    isConfigured = offline.IsDatabaseAvailable;
                }

                return new SourceInfo(
                    Id: provider.Id,
                    Name: provider.Name,
                    Description: provider.Description,
                    MediaTypes: [.. provider.MediaTypes],
                    RequiresApiKey: provider.RequiresApiKey,
                    OptionalApiKey: provider.OptionalApiKey,
                    IsConfigured: isConfigured,
                    HasKey: hasKey,
                    MaskedKey: ApiKeyMask.Mask(key),
                    IsEnabled: (!disabled.Contains(provider.Id)
                        && !disabled.Contains(MediaMerger.NormalizeSourceKey(provider.Id)))
                        && isConfigured);
            })
            .OrderByDescending(source => source.IsEnabled)
            .ToList();

        if (dbManager is not null && dbManager.HasAnyDatabase)
        {
            var summary = await dbManager.GetSummaryAsync(ct);
            foreach (var db in summary.Databases)
            {
                if (!db.IsActive && db.TotalTitles <= 0) continue;

                var shortName = db.Type switch
                {
                    "movie" => "IMDb",
                    "anime" => "Anime",
                    "game" => "OpenVGDB",
                    _ => Path.GetFileNameWithoutExtension(db.FileName)
                };

                var mediaTypes = db.Type switch
                {
                    "movie" => new[] { "movie", "tvshow" },
                    "anime" => new[] { "anime" },
                    "game" => new[] { "game" },
                    _ => new[] { "anime", "movie", "tvshow", "game" }
                };

                sources.Add(new SourceInfo(
                    Id: $"offline:{db.FileName}",
                    Name: $"[Офлайн] {shortName}",
                    Description: $"Локальная база ({db.Name})",
                    MediaTypes: mediaTypes,
                    RequiresApiKey: false,
                    OptionalApiKey: false,
                    IsConfigured: true,
                    HasKey: false,
                    MaskedKey: null,
                    IsEnabled: true
                ));
            }
        }

        return Result<IReadOnlyList<SourceInfo>>.Success(sources);
    }
}
