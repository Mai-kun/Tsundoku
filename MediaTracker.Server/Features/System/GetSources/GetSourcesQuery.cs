using MediaTracker.Server.Domain.Common;

namespace MediaTracker.Server.Features.System.GetSources;

public sealed record SourceInfo(
    string Id,
    string Name,
    string Description,
    string[] MediaTypes,
    bool RequiresApiKey,
    bool IsConfigured,
    bool HasKey,
    string? MaskedKey,
    bool IsEnabled);

/// <summary>
/// The settings screen's source list. It is produced by asking the container what providers exist,
/// so a new provider file shows up here without anyone maintaining a second list.
/// </summary>
public interface IGetSourcesHandler
{
    Task<Result<IReadOnlyList<SourceInfo>>> HandleAsync(CancellationToken ct);
}
