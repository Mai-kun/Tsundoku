using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.Settings.ToggleSource;

public sealed record ToggleSourceCommand(string SourceId, bool Enabled);

public sealed record ToggleSourceResponse(bool Success, bool IsEnabled);

public interface IToggleSourceHandler
{
    Task<Result<ToggleSourceResponse>> HandleAsync(ToggleSourceCommand command, CancellationToken ct);
}

/// <summary>Enables or disables a source in the cascade the aggregator walks.</summary>
public sealed class ToggleSourceHandler(ISourcePriorityService priorityService) : IToggleSourceHandler
{
    public async Task<Result<ToggleSourceResponse>> HandleAsync(
        ToggleSourceCommand command,
        CancellationToken ct)
    {
        await priorityService.SetSourceEnabledAsync(command.SourceId, command.Enabled, ct);
        return Result<ToggleSourceResponse>.Success(new ToggleSourceResponse(true, command.Enabled));
    }
}
