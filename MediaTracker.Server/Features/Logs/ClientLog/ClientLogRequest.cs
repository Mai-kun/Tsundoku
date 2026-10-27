namespace MediaTracker.Server.Features.Logs.ClientLog;

public sealed record ClientLogRequest(
    string Message,
    string? Stack = null,
    string? Url = null);
