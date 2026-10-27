using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

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

        var release = await response.Content.ReadFromJsonAsync<GitHubReleaseDto>(cancellationToken: ct);
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
        await dbContext.Database.ExecuteSqlRawAsync($"VACUUM INTO '{backupPath}'");

        // 2. Download and Extract
        var tempDir = Path.Combine(Path.GetTempPath(), $"tsundoku_update_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        var zipPath = Path.Combine(tempDir, "update.zip");
        
        var client = httpClientFactory.CreateClient();
        var response = await client.GetAsync(check.DownloadUrl, ct);
        await using var fs = File.Create(zipPath);
        await response.Content.CopyToAsync(fs, ct);
        fs.Close();
        
        ZipFile.ExtractToDirectory(zipPath, tempDir);

        // 3. Move files
        var exeName = OperatingSystem.IsWindows() ? "Tsundoku.exe" : "Tsundoku";
        var oldExe = Path.Combine(AppContext.BaseDirectory, exeName + ".old");
        var currentExe = Path.Combine(AppContext.BaseDirectory, exeName);
        
        if (File.Exists(oldExe)) File.Delete(oldExe);
        File.Move(currentExe, oldExe, overwrite: true);
        
        File.Copy(Path.Combine(tempDir, exeName), currentExe, overwrite: true);
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(currentExe, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        }

        // Copy wwwroot
        var newWwwroot = Path.Combine(tempDir, "wwwroot");
        var destWwwroot = Path.Combine(AppContext.BaseDirectory, "wwwroot");
        if (Directory.Exists(newWwwroot))
        {
            if (Directory.Exists(destWwwroot)) Directory.Delete(destWwwroot, true);
            Directory.Move(newWwwroot, destWwwroot);
        }

        // 4. Restart
        Task.Run(() =>
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

public sealed record GitHubReleaseDto(string tag_name, string name, string body, string published_at, string html_url, List<GitHubAssetDto> assets);
public sealed record GitHubAssetDto(string name, string browser_download_url, long size);
