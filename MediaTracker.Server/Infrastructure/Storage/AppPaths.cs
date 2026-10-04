namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class AppPaths
{
    public AppPaths(string dataDirectory)
    {
        DataDirectory = dataDirectory;
        CoversDirectory = Path.Combine(dataDirectory, "data", "covers");
        MediaDirectory = Path.Combine(dataDirectory, "data", "media");
        LogsDirectory = Path.Combine(dataDirectory, "data", "logs");

        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(CoversDirectory);
        Directory.CreateDirectory(MediaDirectory);
        Directory.CreateDirectory(LogsDirectory);
    }

    public string DataDirectory { get; }

    /// <summary>Legacy flat cover folder; kept mounted at /covers so stored URLs keep resolving.</summary>
    public string CoversDirectory { get; }

    /// <summary>Root of the per-title folders, served at /media-assets.</summary>
    public string MediaDirectory { get; }

    public string LogsDirectory { get; }

    public string DatabaseFilePath => Path.Combine(DataDirectory, "tracker.db");
}
