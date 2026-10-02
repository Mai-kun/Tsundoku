namespace MediaTracker.Server.Services.External;

public sealed record ConnectionTestResult(bool Success, int LatencyMs, string Message);

public interface IMetadataProvider
{
    string Id { get; }
    string Name { get; }
    string Description { get; }
    IReadOnlyList<string> MediaTypes { get; }
    bool RequiresApiKey => false;
    bool IsDefault => false;

    Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct);
    Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct);

    async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(5));
            _ = await SearchAsync("test", timeoutCts.Token);
            sw.Stop();
            return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                "Таймаут — сервис не отвечает (проверьте доступность из своей сети)");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }
}
