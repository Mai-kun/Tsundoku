using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Features.System.GetSources;

public sealed class GetSourcesHandler(
    IEnumerable<IMetadataProvider> providers,
    IOptions<ExternalApiOptions> options,
    ISourcePriorityService priorityService) : IGetSourcesHandler
{
    public async Task<Result<IReadOnlyList<SourceInfo>>> HandleAsync(CancellationToken ct)
    {
        var disabled = await priorityService.GetDisabledSourcesAsync(ct);

        var sources = providers
            .DistinctBy(provider => provider.Id)
            .Select(provider =>
            {
                var key = options.Value.GetKey(provider.Id);
                var hasKey = !provider.RequiresApiKey || !string.IsNullOrWhiteSpace(key);

                return new SourceInfo(
                    Id: provider.Id,
                    Name: provider.Name,
                    Description: provider.Description,
                    MediaTypes: [.. provider.MediaTypes],
                    RequiresApiKey: provider.RequiresApiKey,
                    IsConfigured: hasKey,
                    HasKey: hasKey,
                    MaskedKey: ApiKeyMask.Mask(key),
                    IsEnabled: !disabled.Contains(provider.Id)
                        && !disabled.Contains(MediaMerger.NormalizeSourceKey(provider.Id)));
            })
            .OrderByDescending(source => source.IsEnabled)
            .ToList();

        return Result<IReadOnlyList<SourceInfo>>.Success(sources);
    }
}
