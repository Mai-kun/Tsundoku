using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using FluentAssertions;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Backup/restore endpoints touch real files (AppPaths.DatabaseFilePath, Media/Covers dirs).
/// This factory redirects AppPaths to an isolated temp directory so restore never deletes or
/// overwrites the real repo data directory while still running 100% production code over a
/// real SQLite database (temp file via ConnectionStrings__DefaultConnection).
/// </summary>
public class BackupTestWebApplicationFactory : CustomWebApplicationFactory
{
    public string TestDataDirectory { get; } =
        Path.Combine(Path.GetTempPath(), $"tsundoku_backup_test_{Guid.NewGuid():N}");

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.ConfigureServices(services =>
        {
            services.AddSingleton(new AppPaths(TestDataDirectory, isDevelopment: true));
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            try
            {
                if (Directory.Exists(TestDataDirectory))
                {
                    Directory.Delete(TestDataDirectory, recursive: true);
                }
            }
            catch
            {
                // Best-effort cleanup
            }
        }
    }
}

public class BackupServiceTests : IClassFixture<BackupTestWebApplicationFactory>
{
    private readonly BackupTestWebApplicationFactory _factory;
    private readonly HttpClient _client;
    private readonly AppPaths _appPaths;
    private static readonly byte[] SqliteHeader = "SQLite format 3\0"u8.ToArray();

    public BackupServiceTests(BackupTestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _appPaths = factory.Services.GetRequiredService<AppPaths>();
    }

    [Fact]
    public async Task Export_ShouldReturnZipWithDatabaseAndMediaFiles()
    {
        await File.WriteAllTextAsync(Path.Combine(_appPaths.MediaDirectory, "probe.txt"), "media-probe");
        await File.WriteAllTextAsync(Path.Combine(_appPaths.CoversDirectory, "cover-probe.txt"), "cover-probe");

        var response = await _client.GetAsync("/api/settings/backup/export");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType?.MediaType.Should().Be("application/zip");

        var bytes = await response.Content.ReadAsByteArrayAsync();
        using var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);

        var dbEntry = archive.GetEntry("database.db");
        dbEntry.Should().NotBeNull();
        await using var dbStream = dbEntry!.Open();
        using var dbBytes = new MemoryStream();
        await dbStream.CopyToAsync(dbBytes);
        dbBytes.ToArray().AsSpan().StartsWith(SqliteHeader).Should().BeTrue();

        ReadEntry(archive, "media/probe.txt").Should().Be("media-probe");
        ReadEntry(archive, "covers/cover-probe.txt").Should().Be("cover-probe");
    }

    [Fact]
    public async Task Restore_ValidArchive_ShouldRestoreDatabaseMediaAndCovers()
    {
        // Pre-create WAL/SHM so the service has to clean them up.
        await File.WriteAllTextAsync(_appPaths.DatabaseFilePath + "-wal", "stale");
        await File.WriteAllTextAsync(_appPaths.DatabaseFilePath + "-shm", "stale");

        var zipBytes = BuildZip(
            ("database.db", CreateSqliteDatabase()),
            ("media/restore-item.txt", "restored media"u8.ToArray()),
            ("covers/cover.png", new byte[] { 1, 2, 3 }));

        var response = await PostBackup(zipBytes);

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        (await File.ReadAllTextAsync(Path.Combine(_appPaths.MediaDirectory, "restore-item.txt")))
            .Should().Be("restored media");
        (await File.ReadAllTextAsync(Path.Combine(_appPaths.CoversDirectory, "cover.png")))
            .Should().Be("\u0001\u0002\u0003");
        File.Exists(_appPaths.DatabaseFilePath + "-wal").Should().BeFalse();
        File.Exists(_appPaths.DatabaseFilePath + "-shm").Should().BeFalse();

        var marker = ReadRestoredMarker();
        marker.Should().Be(1L, "restored tracker.db must be the archive's database");
    }

    [Fact]
    public async Task Restore_ArchiveWithoutDatabaseEntry_ShouldReturn400()
    {
        var response = await PostBackup(BuildZip(("junk.txt", "nothing useful"u8.ToArray())));

        await ShouldBeBadRequestWithFormatError(response);
    }

    [Fact]
    public async Task Restore_DatabaseEntryNotSqlite_ShouldReturn400()
    {
        var response = await PostBackup(BuildZip(("database.db", "not a database"u8.ToArray())));

        await ShouldBeBadRequestWithFormatError(response);
    }

    [Fact]
    public async Task Restore_EmptyFile_ShouldReturn400()
    {
        var response = await PostBackup([]);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Restore_MaliciousTraversalEntry_ShouldReturn400()
    {
        // '../' entry makes ZipArchive.ExtractToDirectory throw, exercising the catch path.
        var zipBytes = BuildZip(("../evil.txt", new byte[] { 1 }),
            ("database.db", CreateSqliteDatabase()));

        var response = await PostBackup(zipBytes);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    /// <summary>
    /// Covers the non-MemoryCache eviction branch (AdvancedStatsCalculator/TasteProfileCalculator/
    /// SourcePriority cache keys) which the DI-backed endpoint cannot reach, using real DB code.
    /// </summary>
    [Fact]
    public void Restore_WithNonMemoryCache_ShouldInvalidateCachesAndSucceed()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var loader = scope.ServiceProvider.GetRequiredService<StoredSettingsLoader>();
        var service = new BackupService(
            db, _appPaths, new FakeCache(), loader, NullLogger<BackupService>.Instance);

        var result = service.RestoreBackupArchiveAsync(
            new MemoryStream(BuildZip(("database.db", CreateSqliteDatabase())))).GetAwaiter().GetResult();

        result.IsSuccess.Should().BeTrue();
    }

    private async Task<HttpResponseMessage> PostBackup(byte[] zipBytes)
    {
        using var content = new MultipartFormDataContent
        {
            { new ByteArrayContent(zipBytes), "backupFile", "backup.zip" },
        };
        return await _client.PostAsync("/api/settings/backup/restore", content);
    }

    private static async Task ShouldBeBadRequestWithFormatError(HttpResponseMessage response)
    {
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType?.MediaType.Should().Be("application/problem+json");
        var problem = await response.Content.ReadAsStringAsync();
        problem.Should().Contain("Неверный формат");
    }

    private long ReadRestoredMarker()
    {
        using var conn = new SqliteConnection(
            new SqliteConnectionStringBuilder { DataSource = _appPaths.DatabaseFilePath, Mode = SqliteOpenMode.ReadOnly }.ToString());
        conn.Open();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT id FROM marker";
        return cmd.ExecuteScalar() is long id ? id : 0;
    }

    private static string ReadEntry(ZipArchive archive, string entryName)
    {
        using var entry = archive.GetEntry(entryName)!.Open();
        using var reader = new StreamReader(entry);
        return reader.ReadToEnd();
    }

    private static byte[] CreateSqliteDatabase()
    {
        var path = Path.Combine(Path.GetTempPath(), $"tsundoku_restore_src_{Guid.NewGuid():N}.db");
        try
        {
            using var conn = new SqliteConnection($"Data Source={path}");
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "CREATE TABLE marker(id INTEGER); INSERT INTO marker VALUES (1);";
            cmd.ExecuteNonQuery();
            return File.ReadAllBytes(path);
        }
        finally
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
    }

    private static byte[] BuildZip(params (string Name, byte[] Data)[] entries)
    {
        using var stream = new MemoryStream();
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
        {
            foreach (var (name, data) in entries)
            {
                var entry = zip.CreateEntry(name);
                using var entryStream = entry.Open();
                entryStream.Write(data);
            }
        }
        return stream.ToArray();
    }

    private sealed class FakeCache : IMemoryCache
    {
        public bool TryGetValue(object key, out object? value)
        {
            value = null;
            return false;
        }

        public ICacheEntry CreateEntry(object key) => throw new NotSupportedException();

        public void Remove(object key)
        {
            // Synthetic cache: eviction is a no-op, the point is to exercise the else branch.
        }

        public void Dispose()
        {
        }
    }
}
