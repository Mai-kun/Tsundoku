using MediaTracker.Server.Domain.Common;

namespace MediaTracker.Server.Infrastructure.Storage;

public interface IBackupService
{
    Task<Result<Stream>> CreateBackupArchiveAsync(CancellationToken ct = default);
    Task<Result> RestoreBackupArchiveAsync(Stream zipStream, CancellationToken ct = default);
}
