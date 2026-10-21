using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.Settings.TestSource;

public sealed record TestSourceQuery(string SourceId);

public interface ITestSourceHandler
{
    Task<Result<ConnectionTestResult>> HandleAsync(TestSourceQuery query, CancellationToken ct);
}

/// <summary>Pings one provider and reports the latency, so the settings screen can show reachability.</summary>
public sealed class TestSourceHandler(IEnumerable<IMetadataProvider> providers) : ITestSourceHandler
{
    public async Task<Result<ConnectionTestResult>> HandleAsync(TestSourceQuery query, CancellationToken ct)
    {
        var normalizedId = query.SourceId.Trim().ToLowerInvariant();
        var provider = providers.FirstOrDefault(p =>
            p.Id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase)
            || MediaMerger.NormalizeSourceKey(p.Id) == MediaMerger.NormalizeSourceKey(normalizedId));

        if (provider is null)
        {
            return Result<ConnectionTestResult>.Failure(
                Error.NotFound($"Source '{query.SourceId}' not found."));
        }

        var result = await provider.TestConnectionAsync(ct);
        return Result<ConnectionTestResult>.Success(result);
    }
}
