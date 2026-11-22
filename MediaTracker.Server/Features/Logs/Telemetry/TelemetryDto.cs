namespace MediaTracker.Server.Features.Logs.Telemetry;

/// <summary>
/// Строго типизированный ответ <c>/api/logs/telemetry</c>. Анонимные объекты не попадают
/// в AppJsonSerializerContext и падают с NotSupportedException под NativeAOT.
/// </summary>
public sealed record TelemetryDto(
    double ProcessRamMb,
    double GcHeapMb,
    string LocalIp,
    string Uptime,
    string Os,
    int Pid,
    int Threads,
    double DbSizeMb,
    string Architecture,
    string? Gpu = null);
