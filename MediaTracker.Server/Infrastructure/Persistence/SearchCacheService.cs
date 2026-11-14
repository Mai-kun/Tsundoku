using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// Snapshot of the search cache for the Settings → Storage panel. Sizes cover both parts of the
/// search cache: the SQLite database and the cached preview-image files.
/// </summary>
public sealed record SearchCacheInfoDto(
    long EntryCount,
    long FileSizeBytes,
    long ImageFileCount,
    long ImageFileSizeBytes,
    string DatabasePath);

/// <summary>A cached preview image: raw bytes plus the MIME type detected from its signature.</summary>
public sealed record CachedSearchImage(byte[] Data, string ContentType);

/// <summary>
/// Persistent cache of external search results in a dedicated lightweight SQLite database
/// (<c>data/search_cache.db</c>) plus a disk cache of the search preview images
/// (<c>data/search_cache_images/</c>), both fully isolated from <c>tracker.db</c> and the
/// permanent media library (<c>data/media/</c>). Only successful non-empty provider answers and
/// successfully downloaded images are stored; everything carries a three-day TTL and is swept
/// strictly in passing during a real search request (on write, throttled) — the service owns no
/// background timers, so while the app idles nothing touches the database or the disk.
/// Connections use <c>Pooling=False;Cache=Private;</c> so SQLite does not hold cache pages in
/// RAM while the app idles (same policy as the offline database manager).
/// </summary>
public sealed class SearchCacheService : IDisposable
{
    public const string CreateTableSql = @"
        CREATE TABLE IF NOT EXISTS SearchCache (
            CacheKey TEXT PRIMARY KEY,
            PayloadJson TEXT NOT NULL,
            CreatedAtUtc INTEGER NOT NULL,
            ExpiresAtUtc INTEGER NOT NULL
        );
    ";

    /// <summary>Default lifetime of a cached search answer or preview image: three days (72 hours).</summary>
    public static readonly TimeSpan DefaultTtl = TimeSpan.FromHours(72);

    /// <summary>
    /// Throttle for the expired-row sweep that rides a real search write: at most one pass per
    /// interval, always inline inside <see cref="SetAsync"/>, never from a background timer.
    /// </summary>
    private static readonly TimeSpan SweepInterval = TimeSpan.FromHours(4);

    /// <summary>
    /// Every cached image gets this one extension: the MIME type is detected from the file
    /// signature on read, so the same URL never duplicates across extension variants.
    /// </summary>
    private const string ImageFileExtension = ".img";

    private const string ConnectionStringSuffix = ";Mode=ReadWriteCreate;Pooling=False;Cache=Private;";

    private readonly AppPaths? _appPaths;
    private readonly ILogger<SearchCacheService>? _logger;
    private readonly SemaphoreSlim _initLock = new(1, 1);
    private bool _initialized;
    private long _lastSweepTicks;

    public SearchCacheService(
        AppPaths? appPaths = null,
        ILogger<SearchCacheService>? logger = null)
    {
        _appPaths = appPaths;
        _logger = logger;
    }

    /// <summary>
    /// Normalized cache key: <c>{source}:{type}:{query.Trim().ToLowerInvariant()}</c>, with a
    /// <c>:creator</c> suffix when the query targets the upstream creator index. "all" stands in
    /// for the unspecified source so the key is always non-empty and stable.
    /// </summary>
    public static string BuildKey(string? source, string type, string query, bool byCreator = false) =>
        $"{(string.IsNullOrWhiteSpace(source) ? "all" : source.Trim().ToLowerInvariant())}"
        + $":{type.Trim().ToLowerInvariant()}:{query.Trim().ToLowerInvariant()}"
        + (byCreator ? ":creator" : string.Empty);

    /// <summary>
    /// The cache file name for an image URL: SHA-256 of the trimmed URL plus a fixed extension.
    /// Hex output carries no path separators or traversal characters, so the file name can never
    /// escape <see cref="SearchImageCacheDirectory"/> regardless of the URL content.
    /// </summary>
    public static string GetImageFileName(string url) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(url.Trim()))).ToLowerInvariant()
        + ImageFileExtension;

    private static readonly byte[] PngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    private static readonly byte[] JpegSignature = [0xFF, 0xD8, 0xFF];

    /// <summary>
    /// MIME type sniffed from the file signature. Covers from the supported CDNs are
    /// webp/jpeg/png/gif; anything else reports an honest octet-stream.
    /// </summary>
    public static string DetectImageContentType(byte[] data)
    {
        if (data.AsSpan().StartsWith("RIFF"u8) && data.AsSpan(8).StartsWith("WEBP"u8)) return "image/webp";
        if (data.AsSpan().StartsWith(JpegSignature)) return "image/jpeg";
        if (data.AsSpan().StartsWith(PngSignature)) return "image/png";
        if (data.AsSpan().StartsWith("GIF87a"u8) || data.AsSpan().StartsWith("GIF89a"u8)) return "image/gif";
        return "application/octet-stream";
    }

    private string DatabasePath =>
        _appPaths?.SearchCacheDbPath ?? Path.Combine(AppPaths.GetAppDirectory(), "data", "search_cache.db");

    private string SearchImageCacheDirectory =>
        _appPaths?.SearchImageCacheDirectory
        ?? Path.Combine(AppPaths.GetAppDirectory(), "data", "search_cache_images");

    /// <summary>
    /// Reads a still-fresh answer for <paramref name="cacheKey"/>, or null when the key is unknown
    /// or expired (an expired row is deleted on sight). Every failure degrades to a miss: the
    /// cache is an optimization, never a dependency of the search pipeline.
    /// </summary>
    public async Task<IReadOnlyList<ExternalMediaDto>?> TryGetAsync(string cacheKey, CancellationToken ct = default)
    {
        try
        {
            await EnsureInitializedAsync(ct);

            await using var conn = OpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT PayloadJson, ExpiresAtUtc FROM SearchCache WHERE CacheKey = @key;";
            cmd.Parameters.AddWithValue("@key", cacheKey);

            await using var reader = await cmd.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct))
            {
                return null;
            }

            var payload = reader.GetString(0);
            var expiresAtUtc = DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(1));
            if (expiresAtUtc <= DateTimeOffset.UtcNow)
            {
                await DeleteExpiredAsync(conn, cacheKey, ct);
                return null;
            }

            return JsonSerializer.Deserialize(payload, AppJsonSerializerContext.Default.ListExternalMediaDto);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Read failed for '{CacheKey}': {Message}", cacheKey, ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Stores a successful search answer under <paramref name="cacheKey"/> for
    /// <paramref name="ttl"/> (three days by default). Callers only cache non-empty provider
    /// results, so a dry search keeps hitting the upstream until it produces something.
    /// </summary>
    public async Task SetAsync(
        string cacheKey,
        IReadOnlyList<ExternalMediaDto> results,
        CancellationToken ct = default,
        TimeSpan? ttl = null)
    {
        try
        {
            await EnsureInitializedAsync(ct);

            var payload = JsonSerializer.Serialize(results, AppJsonSerializerContext.Default.ListExternalMediaDto);
            var now = DateTimeOffset.UtcNow;
            var expiresAt = now + (ttl ?? DefaultTtl);

            await using var conn = OpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                INSERT INTO SearchCache (CacheKey, PayloadJson, CreatedAtUtc, ExpiresAtUtc)
                VALUES (@key, @payload, @created, @expires)
                ON CONFLICT(CacheKey) DO UPDATE SET
                    PayloadJson = @payload, CreatedAtUtc = @created, ExpiresAtUtc = @expires;
            ";
            cmd.Parameters.AddWithValue("@key", cacheKey);
            cmd.Parameters.AddWithValue("@payload", payload);
            cmd.Parameters.AddWithValue("@created", now.ToUnixTimeMilliseconds());
            cmd.Parameters.AddWithValue("@expires", expiresAt.ToUnixTimeMilliseconds());
            await cmd.ExecuteNonQueryAsync(ct);

            await RunSweepIfDueAsync(ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Write failed for '{CacheKey}': {Message}", cacheKey, ex.Message);
        }
    }

    /// <summary>
    /// Reads a cached preview image for <paramref name="url"/> whose file was written within the
    /// TTL. Returns null on a miss, an expired file (which is deleted on sight) or any I/O
    /// problem — the proxy then downloads from the CDN as before.
    /// </summary>
    public async Task<CachedSearchImage?> TryGetImageAsync(string url, CancellationToken ct = default)
    {
        try
        {
            var path = Path.Combine(SearchImageCacheDirectory, GetImageFileName(url));
            var file = new FileInfo(path);
            if (!file.Exists || file.LastWriteTimeUtc <= DateTimeOffset.UtcNow - DefaultTtl)
            {
                if (file.Exists)
                {
                    file.Delete();
                }

                return null;
            }

            var data = await File.ReadAllBytesAsync(path, ct);
            if (data.Length == 0)
            {
                return null;
            }

            return new CachedSearchImage(data, DetectImageContentType(data));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Image read failed for '{Url}': {Message}", url, ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Stores a successfully downloaded image. The write is atomic: bytes land in a uniquely
    /// named temp file that is renamed over the target, so a parallel reader of the same URL
    /// never sees a half-written image and two racing writers cannot corrupt each other — the
    /// rename either wins as a whole or the other writer's identical-or-newer bytes do.
    /// </summary>
    public async Task SetImageAsync(string url, byte[] data, CancellationToken ct = default)
    {
        try
        {
            if (data.Length == 0) return;

            var dir = SearchImageCacheDirectory;
            Directory.CreateDirectory(dir);

            var path = Path.Combine(dir, GetImageFileName(url));
            var tempPath = $"{path}.{Guid.NewGuid():N}.tmp";
            await File.WriteAllBytesAsync(tempPath, data, ct);
            try
            {
                File.Move(tempPath, path, overwrite: true);
            }
            catch (IOException)
            {
                // A parallel writer renamed its copy first; ours is redundant. Clean the temp up.
                TryDelete(tempPath);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Image write failed for '{Url}': {Message}", url, ex.Message);
        }
    }

    /// <summary>Deletes every cached answer, every cached image and compacts the file. Manual reset from Settings.</summary>
    public async Task ClearAsync(CancellationToken ct = default)
    {
        try
        {
            await EnsureInitializedAsync(ct);

            await using (var conn = OpenConnection())
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "DELETE FROM SearchCache;";
                await cmd.ExecuteNonQueryAsync(ct);
            }

            // VACUUM cannot run inside a transaction; the connection above is already closed,
            // so the file actually shrinks here instead of leaving free pages behind.
            await using (var vacuumConn = OpenConnection())
            {
                await using var vacuum = vacuumConn.CreateCommand();
                vacuum.CommandText = "VACUUM;";
                await vacuum.ExecuteNonQueryAsync(ct);
            }

            ClearImageCacheDirectory();

            _logger?.LogInformation("[SearchCache] Cleared ({DbPath})", DatabasePath);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "[SearchCache] Clear failed: {Message}", ex.Message);
        }
    }

    /// <summary>
    /// Entry count and on-disk sizes for the Settings panel: the SQLite database plus the cached
    /// preview images, reported separately so the UI can show the total.
    /// </summary>
    public async Task<SearchCacheInfoDto> GetInfoAsync(CancellationToken ct = default)
    {
        var count = 0L;
        try
        {
            await EnsureInitializedAsync(ct);

            await using var conn = OpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(1) FROM SearchCache;";
            count = Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Count failed: {Message}", ex.Message);
        }

        var (imageCount, imageBytes) = MeasureImageCacheDirectory();
        var file = new FileInfo(DatabasePath);
        return new SearchCacheInfoDto(
            count,
            file.Exists ? file.Length : 0L,
            imageCount,
            imageBytes,
            DatabasePath);
    }

    /// <summary>
    /// Unthrottled expired pass, used only where a caller is already inside a real search
    /// (the first-touch initialization) and by the tests. The periodic path is the throttled
    /// <see cref="RunSweepIfDueAsync"/> that rides every write.
    /// </summary>
    public async Task RemoveExpiredAsync(CancellationToken ct = default)
    {
        try
        {
            await EnsureInitializedAsync(ct);

            await using var conn = OpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM SearchCache WHERE ExpiresAtUtc < @now;";
            cmd.Parameters.AddWithValue("@now", DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            await cmd.ExecuteNonQueryAsync(ct);

            SweepImageCache();
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Expired-entry sweep failed: {Message}", ex.Message);
        }
    }

    private async Task EnsureInitializedAsync(CancellationToken ct)
    {
        if (_initialized) return;

        await _initLock.WaitAsync(ct);
        try
        {
            if (_initialized) return;

            var dir = Path.GetDirectoryName(DatabasePath);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            await using var conn = OpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = CreateTableSql;
            await cmd.ExecuteNonQueryAsync(ct);

            _initialized = true;
        }
        finally
        {
            _initLock.Release();
        }

        // First touch is also the one guaranteed sweep: rows and image files left over from the
        // previous run are dropped without any startup-side work (initialization only happens on
        // a real search request).
        await RemoveExpiredAsync(ct);
    }

    /// <summary>
    /// The inline expired-entry sweep that rides a real search write. The throttle check runs
    /// lock-free first, so a plain cache write never pays for the sweep; when the interval has
    /// elapsed, the deletion executes under <see cref="_initLock"/> — the same (1,1) semaphore
    /// that guards lazy initialization — so a sweep never interleaves with another init or
    /// sweep. No timers exist anywhere: while nobody searches, this code never runs.
    /// </summary>
    private async Task RunSweepIfDueAsync(CancellationToken ct)
    {
        var nowTicks = DateTimeOffset.UtcNow.Ticks;
        var lastTicks = Interlocked.Read(ref _lastSweepTicks);
        if (nowTicks - lastTicks < SweepInterval.Ticks) return;
        if (Interlocked.CompareExchange(ref _lastSweepTicks, nowTicks, lastTicks) != lastTicks) return;

        await _initLock.WaitAsync(ct);
        try
        {
            await using var conn = OpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM SearchCache WHERE ExpiresAtUtc < @now;";
            cmd.Parameters.AddWithValue("@now", DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            await cmd.ExecuteNonQueryAsync(ct);

            SweepImageCache();
        }
        finally
        {
            _initLock.Release();
        }
    }

    /// <summary>
    /// Deletes image files past the TTL, including orphaned ".tmp" leftovers from an interrupted
    /// atomic write (their fresh timestamp keeps them alive only for the TTL window, so a write
    /// in flight is never deleted under itself).
    /// </summary>
    private void SweepImageCache()
    {
        var dir = SearchImageCacheDirectory;
        if (!Directory.Exists(dir)) return;

        var cutoff = DateTimeOffset.UtcNow - DefaultTtl;
        foreach (var file in Directory.EnumerateFiles(dir))
        {
            try
            {
                if (new FileInfo(file).LastWriteTimeUtc < cutoff)
                {
                    File.Delete(file);
                }
            }
            catch (Exception ex)
            {
                _logger?.LogDebug(ex, "[SearchCache] Failed to sweep image '{File}': {Message}", file, ex.Message);
            }
        }
    }

    private void ClearImageCacheDirectory()
    {
        var dir = SearchImageCacheDirectory;
        if (!Directory.Exists(dir)) return;

        foreach (var file in Directory.EnumerateFiles(dir))
        {
            TryDelete(file);
        }
    }

    private (long Count, long Bytes) MeasureImageCacheDirectory()
    {
        var dir = SearchImageCacheDirectory;
        if (!Directory.Exists(dir)) return (0, 0);

        try
        {
            var count = 0L;
            var bytes = 0L;
            foreach (var file in Directory.EnumerateFiles(dir))
            {
                var info = new FileInfo(file);
                count++;
                bytes += info.Length;
            }

            return (count, bytes);
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Failed to measure image cache: {Message}", ex.Message);
            return (0, 0);
        }
    }

    private void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[SearchCache] Failed to delete '{Path}': {Message}", path, ex.Message);
        }
    }

    private async Task DeleteExpiredAsync(SqliteConnection conn, string cacheKey, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM SearchCache WHERE CacheKey = @key;";
        cmd.Parameters.AddWithValue("@key", cacheKey);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private SqliteConnection OpenConnection()
    {
        var conn = new SqliteConnection($"Data Source={DatabasePath}{ConnectionStringSuffix}");
        conn.Open();
        return conn;
    }

    /// <summary>DI singletons dispose this at shutdown; the semaphore is the only held resource.</summary>
    public void Dispose()
    {
        _initLock.Dispose();
    }
}
