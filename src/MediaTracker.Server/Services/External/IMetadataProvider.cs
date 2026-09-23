namespace MediaTracker.Server.Services.External;

public interface IMetadataProvider
{
    Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct);
}
