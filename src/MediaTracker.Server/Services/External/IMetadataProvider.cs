namespace MediaTracker.Server.Services.External;

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
}
