namespace MediaTracker.Server.DTOs;

public sealed record ClientLogRequest(
    string Message,
    string? Stack = null,
    string? Url = null);
