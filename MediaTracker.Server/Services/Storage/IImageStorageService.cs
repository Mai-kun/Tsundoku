namespace MediaTracker.Server.Services.Storage;

public interface IImageStorageService
{
    Task<string?> SaveCoverAsync(string externalUrl, Guid itemId, CancellationToken ct = default);

    void DeleteCover(string? localCoverUrl);
}
