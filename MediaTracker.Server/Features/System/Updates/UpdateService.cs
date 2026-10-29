using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Logging;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Features.System.Updates;

public interface IUpdateService
{
    Task<UpdateCheckResultDto> CheckForUpdatesAsync(CancellationToken ct);
    Task ApplyUpdateAsync(CancellationToken ct);
}

public sealed class UpdateService(
    IHttpClientFactory httpClientFactory,
    AppPaths appPaths,
    AppDbContext dbContext,
    IHostApplicationLifetime hostLifetime,
    ILogger<UpdateService> logger) : IUpdateService
{
    public async Task<UpdateCheckResultDto> CheckForUpdatesAsync(CancellationToken ct)
    {
        var repo = Environment.GetEnvironmentVariable("TSUNDOKU_GITHUB_REPO") ?? "mai-kun/tsundoku";
        var client = httpClientFactory.CreateClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Tsundoku-Updater");

        var response = await client.GetAsync($"https://api.github.com/repos/{repo}/releases/latest", ct);
        if (!response.IsSuccessStatusCode) return new UpdateCheckResultDto(Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.0.0", null, false, false, null, null, null, null, null, null);

        var release = await response.Content.ReadFromJsonAsync(AppJsonSerializerContext.Default.GitHubReleaseDto, cancellationToken: ct);
        if (release is null) return new UpdateCheckResultDto(Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.0.0", null, false, false, null, null, null, null, null, null);

        var currentVersion = Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0, 0, 0);
        var latestVersion = Version.TryParse(release.tag_name.TrimStart('v'), out var v) ? v : new Version(0, 0, 0);

        var isUpdateAvailable = latestVersion > currentVersion;

        var assetName = OperatingSystem.IsLinux() ? "tsundoku-linux-x64.zip" : "tsundoku-win-x64.zip";
        var asset = release.assets.FirstOrDefault(a => a.name == assetName);

        var canSelfUpdate = !CommandLineOptions.IsRunningInContainer && asset != null;

        return new UpdateCheckResultDto(
            currentVersion.ToString(),
            release.tag_name,
            isUpdateAvailable,
            canSelfUpdate,
            release.name,
            release.body,
            release.published_at,
            release.html_url,
            asset?.browser_download_url,
            asset?.size);
    }

    public async Task ApplyUpdateAsync(CancellationToken ct)
    {
        var check = await CheckForUpdatesAsync(ct);
        if (check.DownloadUrl is null) throw new InvalidOperationException("No update asset found.");

        // 1. Backup DB
        var backupDir = Path.Combine(appPaths.DataDirectory, "backups");
        Directory.CreateDirectory(backupDir);
        var backupPath = Path.Combine(backupDir, $"tracker_pre_update_{DateTime.UtcNow:yyyyMMdd_HHmmss}.db");
        var conn = dbContext.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = $"VACUUM INTO '{backupPath.Replace("'", "''")}';";
        await cmd.ExecuteNonQueryAsync();

        // 2. Download and Extract
        var tempDir = Path.Combine(Path.GetTempPath(), $"tsundoku_update_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        var zipPath = Path.Combine(tempDir, "update.zip");

        var client = httpClientFactory.CreateClient();
        var response = await client.GetAsync(check.DownloadUrl, ct);
        await using var fs = File.Create(zipPath);
        await response.Content.CopyToAsync(fs, ct);
        fs.Close();

        // 2 & 3. Install: binaries and wwwroot update, user data stays byte-for-byte intact.
        UpdatePayloadApplier.ApplyZip(zipPath, AppContext.BaseDirectory, OperatingSystem.IsWindows());

        logger.LogInformation("[Update] Applied release {Version}, restarting", check.LatestVersion);

        // 4. Restart
        _ = Task.Run(() =>
        {
            Thread.Sleep(1000);
            var startInfo = new ProcessStartInfo(Environment.ProcessPath!, string.Join(" ", Environment.GetCommandLineArgs().Skip(1)))
            {
                UseShellExecute = true
            };
            Process.Start(startInfo);
            hostLifetime.StopApplication();
        }, CancellationToken.None);
    }
}

/// <summary>
/// Installs an extracted release payload into the app directory. The rules are strict on purpose:
/// <list type="bullet">
/// <item>the executable, every native library and the whole <c>wwwroot</c> folder are replaced —
/// stale chunks must not survive inside wwwroot;</item>
/// <item>anything user-owned (<c>storage.json</c>, <c>.portable</c>, <c>data/</c>, databases, the
/// secret key) is never copied over and never deleted, even if the payload carried it.</item>
/// </list>
/// </summary>
internal static class UpdatePayloadApplier
{
    private static readonly string[] ProtectedFileNames =
    [
        "storage.json",
        ".portable",
        ".secret.key",
    ];

    private static readonly string[] ProtectedFileExtensions =
    [
        ".db",
        ".db-wal",
        ".db-shm",
    ];

    public static void ApplyZip(string zipPath, string baseDir, bool isWindows)
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_update_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);
        try
        {
            ZipFile.ExtractToDirectory(zipPath, tempDir);
            Apply(tempDir, baseDir, isWindows);
        }
        finally
        {
            try
            {
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, recursive: true);
                }
            }
            catch
            {
                // Best-effort cleanup of temp directory.
            }
        }
    }

    public static void Apply(string extractedDir, string baseDir, bool isWindows)
    {
        var exeName = isWindows ? "Tsundoku.exe" : "Tsundoku";

        // 1. Executable: a running process cannot overwrite its own binary on Windows, so the old
        //    one is renamed aside first and cleaned up on the next update.
        var oldExe = Path.Combine(baseDir, exeName + ".old");
        if (File.Exists(oldExe))
        {
            File.Delete(oldExe);
        }

        var newExe = Path.Combine(extractedDir, exeName);
        if (File.Exists(newExe))
        {
            var currentExe = Path.Combine(baseDir, exeName);
            if (File.Exists(currentExe))
            {
                File.Move(currentExe, oldExe, overwrite: true);
            }

            File.Copy(newExe, currentExe, overwrite: true);
            if (!isWindows)
            {
                File.SetUnixFileMode(
                    currentExe,
                    UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute
                    | UnixFileMode.GroupRead | UnixFileMode.GroupExecute
                    | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
            }
        }

        // 2. wwwroot is replaced wholesale: leftover asset chunks from the old build would keep
        //    being served forever. The copy stays inside wwwroot and touches nothing else.
        var newWwwroot = Path.Combine(extractedDir, "wwwroot");
        var destWwwroot = Path.Combine(baseDir, "wwwroot");
        if (Directory.Exists(newWwwroot))
        {
            if (Directory.Exists(destWwwroot))
            {
                Directory.Delete(destWwwroot, recursive: true);
            }

            CopyDirectory(newWwwroot, destWwwroot);
        }

        // 3. Everything else in the payload (native libraries, locales, configs) is copied over,
        //    except user-owned files which are skipped no matter what the payload claims.
        foreach (var source in Directory.EnumerateFiles(extractedDir, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(extractedDir, source);
            var normalized = relative.Replace('\\', '/');
            if (IsProtected(relative)
                || string.Equals(relative, exeName, StringComparison.OrdinalIgnoreCase)
                || string.Equals(relative, "update.zip", StringComparison.OrdinalIgnoreCase)
                || normalized.StartsWith("wwwroot/", StringComparison.OrdinalIgnoreCase)
                || string.Equals(normalized, "wwwroot", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var destination = Path.Combine(baseDir, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, overwrite: true);
        }
    }

    /// <summary>
    /// User-owned paths. Matched on the payload-relative name, so a release that accidentally
    /// packaged a <c>tracker.db</c> still cannot clobber the user's data.
    /// </summary>
    internal static bool IsProtected(string relativePath)
    {
        var normalized = relativePath.Replace('\\', '/').TrimStart('/');
        var segments = normalized.Split('/');

        if (string.Equals(segments[0], "data", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var fileName = segments[^1];
        if (ProtectedFileNames.Contains(fileName, StringComparer.OrdinalIgnoreCase))
        {
            return true;
        }

        return ProtectedFileExtensions.Any(ext => fileName.EndsWith(ext, StringComparison.OrdinalIgnoreCase));
    }

    private static void CopyDirectory(string sourceDir, string destDir)
    {
        Directory.CreateDirectory(destDir);

        foreach (var directory in Directory.EnumerateDirectories(sourceDir, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Combine(destDir, Path.GetRelativePath(sourceDir, directory)));
        }

        foreach (var file in Directory.EnumerateFiles(sourceDir, "*", SearchOption.AllDirectories))
        {
            File.Copy(file, Path.Combine(destDir, Path.GetRelativePath(sourceDir, file)), overwrite: true);
        }
    }
}

public sealed record GitHubReleaseDto(string tag_name, string name, string body, string published_at, string html_url, List<GitHubAssetDto> assets);
public sealed record GitHubAssetDto(string name, string browser_download_url, long size);
