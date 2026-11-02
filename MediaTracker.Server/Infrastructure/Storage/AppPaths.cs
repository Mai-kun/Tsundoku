using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class StorageConfig
{
    public string Mode { get; set; } = "default";
    public string? CustomPath { get; set; }
}

public sealed class AppPaths
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };
    private readonly bool _hasExplicitDataDir;

    public bool IsFirstRunSetupRequired => !IsDevelopment &&
                                           !CommandLineOptions.IsRunningInContainer &&
                                           !_hasExplicitDataDir &&
                                           !File.Exists(Path.Combine(GetAppDirectory(), "storage.json")) &&
                                           !File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tsundoku", "storage.json"));

    public AppPaths(string dataDirectory, bool isDevelopment = false, bool hasExplicitDataDir = false, string mode = "default", string? customPath = null)
    {
        DataDirectory = dataDirectory;
        IsDevelopment = isDevelopment;
        _hasExplicitDataDir = hasExplicitDataDir;
        StorageMode = mode;
        CustomPath = customPath;

        var dbFileName = isDevelopment ? "tracker.dev.db" : "tracker.db";
        DatabaseFilePath = Path.Combine(dataDirectory, dbFileName);

        if (isDevelopment)
        {
            CoversDirectory = Path.Combine(dataDirectory, "covers");
            MediaDirectory = Path.Combine(dataDirectory, "media");
            LogsDirectory = Path.Combine(dataDirectory, "logs");
        }
        else
        {
            var subDir = Path.GetFileName(dataDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
                .Equals("data", StringComparison.OrdinalIgnoreCase)
                ? dataDirectory
                : Path.Combine(dataDirectory, "data");

            CoversDirectory = Path.Combine(subDir, "covers");
            MediaDirectory = Path.Combine(subDir, "media");
            LogsDirectory = Path.Combine(subDir, "logs");
        }

        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(CoversDirectory);
        Directory.CreateDirectory(MediaDirectory);
        Directory.CreateDirectory(LogsDirectory);
    }

    public bool IsDevelopment { get; }

    public string DataDirectory { get; }

    public string StorageMode { get; }

    public string? CustomPath { get; }

    public FileLockGuard? LockGuard { get; set; }

    /// <summary>Legacy flat cover folder; kept mounted at /covers so stored URLs keep resolving.</summary>
    public string CoversDirectory { get; }

    /// <summary>Root of the per-title folders, served at /media-assets.</summary>
    public string MediaDirectory { get; }

    public string LogsDirectory { get; }

    public string DatabaseFilePath { get; }

    public string OfflineDirectory => Path.Combine(DataDirectory, "offline");

    public string OfflineDatabasePath
    {
        get
        {
            var primary = Path.Combine(OfflineDirectory, "anime_offline.db");
            if (File.Exists(primary)) return primary;
            var secondary = Path.Combine(GetAppDirectory(), "data", "offline", "anime_offline.db");
            if (File.Exists(secondary)) return secondary;
            return primary;
        }
    }

    public StorageConfig GetOrRecreateStorageConfig()
    {
        var configPath = GetStorageConfigPath();
        try
        {
            if (File.Exists(configPath))
            {
                var text = File.ReadAllText(configPath);
                var config = JsonSerializer.Deserialize(text, AppJsonSerializerContext.Default.StorageConfig);
                if (config != null)
                {
                    return config;
                }
            }
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException or IOException)
        {
            // Missing or deleted externally
        }

        // Recreate storage.json from active AppPaths parameters
        var recreated = new StorageConfig
        {
            Mode = StorageMode,
            CustomPath = CustomPath
        };

        try
        {
            var targetPath = GetWritableStorageConfigPath(StorageMode);
            SaveStorageConfig(targetPath, recreated);
        }
        catch (Exception ex)
        {
            Serilog.Log.Warning(ex, "Failed to regenerate storage.json: {Message}", ex.Message);
        }

        return recreated;
    }

    public void SaveStorageConfig(string configPath, StorageConfig config)
    {
        LockGuard?.ReleaseStorageLock();
        var dir = Path.GetDirectoryName(configPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(configPath, JsonSerializer.Serialize(config, AppJsonSerializerContext.Default.StorageConfig));
        LockGuard?.TryAcquireStorageLock(configPath);
    }

    /// <summary>
    /// Returns the directory where the application binary lives.
    /// Under Linux AppImage, this resolves to the directory containing the .AppImage file
    /// rather than the temporary mount directory in /tmp/.mount_xxx/.
    /// </summary>
    public static string GetAppDirectory()
    {
        var appImage = Environment.GetEnvironmentVariable("APPIMAGE");
        if (!string.IsNullOrWhiteSpace(appImage))
        {
            try
            {
                var fullAppImage = Path.GetFullPath(appImage);
                var dir = Path.GetDirectoryName(fullAppImage);
                if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
                {
                    return dir;
                }
            }
            catch
            {
                // Fall back
            }
        }

        return AppContext.BaseDirectory;
    }

    /// <summary>
    /// Returns the executable path for launching or restarting.
    /// Under Linux AppImage, this returns the .AppImage file path rather than the extracted binary.
    /// </summary>
    public static string GetExecutablePath()
    {
        var appImage = Environment.GetEnvironmentVariable("APPIMAGE");
        if (!string.IsNullOrWhiteSpace(appImage))
        {
            try
            {
                var fullAppImage = Path.GetFullPath(appImage);
                if (File.Exists(fullAppImage))
                {
                    return fullAppImage;
                }
            }
            catch
            {
                // Fall back
            }
        }

        return Environment.ProcessPath ?? Environment.GetCommandLineArgs()[0];
    }

    public static string GetStorageConfigPath()
    {
        var appDir = GetAppDirectory();
        var localConfig = Path.Combine(appDir, "storage.json");
        if (File.Exists(localConfig)) return localConfig;

        var systemConfig = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Tsundoku",
            "storage.json");
        if (File.Exists(systemConfig)) return systemConfig;

        return localConfig;
    }

    public static string GetWritableStorageConfigPath(string mode)
    {
        var appDir = GetAppDirectory();
        var appDirConfig = Path.Combine(appDir, "storage.json");

        if (string.Equals(mode, "portable", StringComparison.OrdinalIgnoreCase))
        {
            return appDirConfig;
        }

        try
        {
            var testFile = Path.Combine(appDir, ".test_write_" + Guid.NewGuid().ToString("N"));
            File.WriteAllText(testFile, "test");
            File.Delete(testFile);
            return appDirConfig;
        }
        catch
        {
            var systemDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Tsundoku");
            Directory.CreateDirectory(systemDir);
            return Path.Combine(systemDir, "storage.json");
        }
    }

    public static AppPaths Create(CommandLineOptions options, bool isDevelopment)
    {
        string dataDirectory;
        var appDir = GetAppDirectory();
        var storageConfigPath = GetStorageConfigPath();
        var hasExplicitDir = false;
        var mode = "default";
        string? customPath = null;

        if (options.DataDirectory is { Length: > 0 } configuredDirectory)
        {
            dataDirectory = Path.GetFullPath(configuredDirectory);
            hasExplicitDir = true;
            mode = "custom";
            customPath = dataDirectory;
        }
        else if (!isDevelopment && !CommandLineOptions.IsRunningInContainer && File.Exists(storageConfigPath))
        {
            StorageConfig? config = null;
            try
            {
                config = JsonSerializer.Deserialize(File.ReadAllText(storageConfigPath), AppJsonSerializerContext.Default.StorageConfig);
            }
            catch
            {
                // Fallback if missing or malformed
            }

            mode = config?.Mode?.ToLowerInvariant() switch
            {
                "p" or "portable" => "portable",
                "c" or "custom" => "custom",
                _ => "default"
            };
            customPath = config?.CustomPath;
            if (mode == "portable") dataDirectory = Path.Combine(appDir, "data");
            else if (mode == "custom" && !string.IsNullOrEmpty(customPath)) dataDirectory = Path.GetFullPath(customPath);
            else dataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tsundoku");
        }
        else if (!isDevelopment && !CommandLineOptions.IsRunningInContainer && (File.Exists(Path.Combine(appDir, ".portable")) || File.Exists(Path.Combine(AppContext.BaseDirectory, ".portable"))))
        {
            mode = "portable";
            dataDirectory = Path.Combine(appDir, "data");
        }
        else if (isDevelopment)
        {
            var currentDir = Directory.GetCurrentDirectory();
            if (File.Exists(Path.Combine(currentDir, "MediaTracker.Server.csproj")) && Directory.GetParent(currentDir) != null)
            {
                dataDirectory = Path.Combine(Directory.GetParent(currentDir)!.FullName, "data");
            }
            else
            {
                dataDirectory = Path.Combine(currentDir, "data");
            }
        }
        else if (CommandLineOptions.IsRunningInContainer)
        {
            dataDirectory = Path.Combine(Directory.GetCurrentDirectory(), "data");
        }
        else
        {
            dataDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Tsundoku"
            );
        }

        return new AppPaths(dataDirectory, isDevelopment, hasExplicitDir, mode, customPath);
    }
}

public sealed class FileLockGuard : IDisposable
{
    private readonly object _sync = new();
    private FileStream? _storageLockStream;
    private FileStream? _dataLockStream;
    private bool _disposed;

    public FileLockGuard(AppPaths paths)
    {
        AcquireDataLock(paths.DataDirectory);
        var configPath = AppPaths.GetStorageConfigPath();
        if (File.Exists(configPath))
        {
            TryAcquireStorageLock(configPath);
        }
    }

    public FileLockGuard(string dataDirectory, string? storageConfigPath = null)
    {
        AcquireDataLock(dataDirectory);
        if (!string.IsNullOrEmpty(storageConfigPath) && File.Exists(storageConfigPath))
        {
            TryAcquireStorageLock(storageConfigPath);
        }
    }

    private void AcquireDataLock(string dataDirectory)
    {
        try
        {
            Directory.CreateDirectory(dataDirectory);
            var sentinelPath = Path.Combine(dataDirectory, ".data.lock");
            _dataLockStream = new FileStream(
                sentinelPath,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.Read);

            if (OperatingSystem.IsLinux())
            {
                MediaTracker.Server.Infrastructure.Desktop.LinuxFlock.TryLockExclusive(_dataLockStream);
            }
        }
        catch (Exception ex)
        {
            Serilog.Log.Warning(ex, "Failed to acquire lock guard on data directory: {DataDir}", dataDirectory);
        }
    }

    public void TryAcquireStorageLock(string storageConfigPath)
    {
        lock (_sync)
        {
            if (_disposed) return;
            if (!File.Exists(storageConfigPath)) return;

            try
            {
                _storageLockStream?.Dispose();
                _storageLockStream = new FileStream(
                    storageConfigPath,
                    FileMode.OpenOrCreate,
                    FileAccess.ReadWrite,
                    FileShare.Read);
            }
            catch (Exception ex)
            {
                Serilog.Log.Warning(ex, "Failed to acquire lock guard on storage config: {Path}", storageConfigPath);
            }
        }
    }

    public void ReleaseStorageLock()
    {
        lock (_sync)
        {
            _storageLockStream?.Dispose();
            _storageLockStream = null;
        }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;

            try { _storageLockStream?.Dispose(); } catch { }
            _storageLockStream = null;

            try { _dataLockStream?.Dispose(); } catch { }
            _dataLockStream = null;
        }
    }
}
