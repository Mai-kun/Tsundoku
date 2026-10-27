using MediaTracker.Server.Domain.Common;

namespace MediaTracker.Server.Features.Logs.ClientLog;

public interface IClientLogHandler
{
    Result Handle(ClientLogRequest request);
}
