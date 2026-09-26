namespace MediaTracker.Server.Services.External;

public interface IMetadataProvider
{
    Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct);
    Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct);
}
