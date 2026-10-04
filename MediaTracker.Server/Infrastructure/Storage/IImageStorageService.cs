namespace MediaTracker.Server.Infrastructure.Storage;

public interface IImageStorageService
{
    Task<string?> SaveCoverAsync(string externalUrl, Guid itemId, CancellationToken ct = default);

    void DeleteCover(string? localCoverUrl);

    void DeleteMediaFolder(Guid mediaId);
}
