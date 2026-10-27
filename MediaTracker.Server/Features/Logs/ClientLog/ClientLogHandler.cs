using MediaTracker.Server.Domain.Common;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.Logs.ClientLog;

/// <summary>Accepts an error report from the browser and files it in the server log.</summary>
public sealed class ClientLogHandler(ILogger<ClientLogHandler> logger) : IClientLogHandler
{
    public Result Handle(ClientLogRequest request)
    {
        var stack = string.IsNullOrWhiteSpace(request.Stack) ? string.Empty : $"\n{request.Stack}";

        logger.LogError(
            "[Frontend Error] {Message} at {Url}{Stack}",
            request.Message,
            request.Url ?? "unknown",
            stack);

        return Result.Success();
    }
}
