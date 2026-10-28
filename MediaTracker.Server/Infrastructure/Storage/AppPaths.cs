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
    public bool IsFirstRunSetupRequired { get; }

    public AppPaths(string dataDirectory, bool isDevelopment = false)
    {
        DataDirectory = dataDirectory;
        IsDevelopment = isDevelopment;

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

        IsFirstRunSetupRequired = !isDevelopment && !CommandLineOptions.IsRunningInContainer &&
                                  !File.Exists(Path.Combine(AppContext.BaseDirectory, "storage.json")) &&
                                  !File.Exists(DatabaseFilePath);
    }

    public bool IsDevelopment { get; }

    public string DataDirectory { get; }

    /// <summary>Legacy flat cover folder; kept mounted at /covers so stored URLs keep resolving.</summary>
    public string CoversDirectory { get; }

    /// <summary>Root of the per-title folders, served at /media-assets.</summary>
    public string MediaDirectory { get; }

    public string LogsDirectory { get; }

    public string DatabaseFilePath { get; }

    public static AppPaths Create(CommandLineOptions options, bool isDevelopment)
    {
        string dataDirectory;
        var appDir = AppContext.BaseDirectory;
        var storageConfigPath = Path.Combine(appDir, "storage.json");

        if (options.DataDirectory is { Length: > 0 } configuredDirectory)
        {
            dataDirectory = Path.GetFullPath(configuredDirectory);
        }
        else if (!isDevelopment && !CommandLineOptions.IsRunningInContainer && File.Exists(storageConfigPath))
        {
            var config = JsonSerializer.Deserialize(File.ReadAllText(storageConfigPath), AppJsonSerializerContext.Default.StorageConfig) ?? new();
            var mode = config.Mode?.ToLowerInvariant() switch
            {
                "p" or "portable" => "portable",
                "c" or "custom" => "custom",
                _ => "default"
            };
            if (mode == "portable") dataDirectory = Path.Combine(appDir, "data");
            else if (mode == "custom" && !string.IsNullOrEmpty(config.CustomPath)) dataDirectory = Path.GetFullPath(config.CustomPath);
            else dataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tsundoku");
        }
        else if (!isDevelopment && !CommandLineOptions.IsRunningInContainer && File.Exists(Path.Combine(appDir, ".portable")))
        {
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

        return new AppPaths(dataDirectory, isDevelopment);
    }
}
