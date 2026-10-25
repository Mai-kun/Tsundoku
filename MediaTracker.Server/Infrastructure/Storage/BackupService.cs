using System.IO.Compression;
using System.Text;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class BackupService(
    AppDbContext db,
    AppPaths appPaths,
    IMemoryCache cache,
    StoredSettingsLoader storedSettingsLoader,
    ILogger<BackupService> logger) : IBackupService
{
    private static readonly byte[] SqliteHeader = "SQLite format 3\0"u8.ToArray();

    public async Task<Result<Stream>> CreateBackupArchiveAsync(CancellationToken ct = default)
    {
        var tempDbPath = Path.Combine(Path.GetTempPath(), $"tsundoku_backup_{Guid.NewGuid():N}.db");
        var tempZipPath = Path.Combine(Path.GetTempPath(), $"tsundoku_backup_{Guid.NewGuid():N}.zip");

        try
        {
            if (File.Exists(tempDbPath))
            {
                File.Delete(tempDbPath);
            }

            var escapedPath = tempDbPath.Replace("'", "''");
            await db.Database.ExecuteSqlRawAsync(string.Format("VACUUM INTO '{0}';", escapedPath), ct);

            using (var zipArchive = ZipFile.Open(tempZipPath, ZipArchiveMode.Create))
            {
                zipArchive.CreateEntryFromFile(tempDbPath, "database.db", CompressionLevel.Optimal);

                if (Directory.Exists(appPaths.MediaDirectory))
                {
                    AddDirectoryToZip(zipArchive, appPaths.MediaDirectory, "media");
                }

                if (Directory.Exists(appPaths.CoversDirectory))
                {
                    AddDirectoryToZip(zipArchive, appPaths.CoversDirectory, "covers");
                }
            }

            var fileStream = new FileStream(
                tempZipPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 4096,
                FileOptions.DeleteOnClose);

            return Result<Stream>.Success(fileStream);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to create backup archive");
            if (File.Exists(tempZipPath))
            {
                try { File.Delete(tempZipPath); } catch { /* ignore */ }
            }
            return Result<Stream>.Failure(Error.Validation($"Не удалось создать резервную копию: {ex.Message}"));
        }
        finally
        {
            if (File.Exists(tempDbPath))
            {
                try { File.Delete(tempDbPath); } catch { /* ignore */ }
            }
        }
    }

    public async Task<Result> RestoreBackupArchiveAsync(Stream zipStream, CancellationToken ct = default)
    {
        var extractDir = Path.Combine(Path.GetTempPath(), $"tsundoku_restore_{Guid.NewGuid():N}");

        try
        {
            Directory.CreateDirectory(extractDir);

            using (var zipArchive = new ZipArchive(zipStream, ZipArchiveMode.Read, leaveOpen: true))
            {
                zipArchive.ExtractToDirectory(extractDir, overwriteFiles: true);
            }

            var extractedDbPath = Path.Combine(extractDir, "database.db");
            if (!File.Exists(extractedDbPath))
            {
                return Result.Failure(Error.Validation("Неверный формат архива бэкапа."));
            }

            var headerBuffer = new byte[16];
            await using (var dbStream = File.OpenRead(extractedDbPath))
            {
                var bytesRead = await dbStream.ReadAsync(headerBuffer.AsMemory(0, 16), ct);
                if (bytesRead < 16 || !headerBuffer.AsSpan().SequenceEqual(SqliteHeader))
                {
                    return Result.Failure(Error.Validation("Неверный формат архива бэкапа."));
                }
            }

            SqliteConnection.ClearAllPools();

            var dbDir = Path.GetDirectoryName(appPaths.DatabaseFilePath)!;
            var dbFileName = Path.GetFileName(appPaths.DatabaseFilePath);
            var walFile = Path.Combine(dbDir, $"{dbFileName}-wal");
            var shmFile = Path.Combine(dbDir, $"{dbFileName}-shm");

            if (File.Exists(walFile))
            {
                try { File.Delete(walFile); } catch (Exception ex) { logger.LogWarning(ex, "Failed to delete WAL file: {Path}", walFile); }
            }

            if (File.Exists(shmFile))
            {
                try { File.Delete(shmFile); } catch (Exception ex) { logger.LogWarning(ex, "Failed to delete SHM file: {Path}", shmFile); }
            }

            File.Copy(extractedDbPath, appPaths.DatabaseFilePath, overwrite: true);

            var extractedMediaDir = Path.Combine(extractDir, "media");
            if (Directory.Exists(extractedMediaDir))
            {
                if (Directory.Exists(appPaths.MediaDirectory))
                {
                    Directory.Delete(appPaths.MediaDirectory, recursive: true);
                }
                Directory.CreateDirectory(appPaths.MediaDirectory);
                CopyDirectory(extractedMediaDir, appPaths.MediaDirectory);
            }

            var extractedCoversDir = Path.Combine(extractDir, "covers");
            if (Directory.Exists(extractedCoversDir))
            {
                if (Directory.Exists(appPaths.CoversDirectory))
                {
                    Directory.Delete(appPaths.CoversDirectory, recursive: true);
                }
                Directory.CreateDirectory(appPaths.CoversDirectory);
                CopyDirectory(extractedCoversDir, appPaths.CoversDirectory);
            }

            if (cache is MemoryCache memoryCache)
            {
                memoryCache.Clear();
            }
            else
            {
                AdvancedStatsCalculator.InvalidateCache(cache);
                TasteProfileCalculator.InvalidateCache(cache);
                cache.Remove(SourcePriorityService.PriorityCacheKey);
                cache.Remove(SourcePriorityService.DisabledSourcesCacheKey);
            }

            await storedSettingsLoader.LoadAsync(ct);

            return Result.Success();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to restore backup archive");
            return Result.Failure(Error.Validation($"Ошибка при восстановлении резервной копии: {ex.Message}"));
        }
        finally
        {
            if (Directory.Exists(extractDir))
            {
                try { Directory.Delete(extractDir, recursive: true); } catch { /* ignore */ }
            }
        }
    }

    private static void AddDirectoryToZip(ZipArchive archive, string sourceDir, string entryPrefix)
    {
        var files = Directory.GetFiles(sourceDir, "*", SearchOption.AllDirectories);
        foreach (var file in files)
        {
            var relativePath = Path.GetRelativePath(sourceDir, file).Replace('\\', '/');
            var entryName = $"{entryPrefix}/{relativePath}";
            archive.CreateEntryFromFile(file, entryName, CompressionLevel.Optimal);
        }
    }

    private static void CopyDirectory(string sourceDir, string targetDir)
    {
        Directory.CreateDirectory(targetDir);

        foreach (var file in Directory.GetFiles(sourceDir))
        {
            var targetFilePath = Path.Combine(targetDir, Path.GetFileName(file));
            File.Copy(file, targetFilePath, overwrite: true);
        }

        foreach (var directory in Directory.GetDirectories(sourceDir))
        {
            var targetSubDir = Path.Combine(targetDir, Path.GetFileName(directory));
            CopyDirectory(directory, targetSubDir);
        }
    }
}
