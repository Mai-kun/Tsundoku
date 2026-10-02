namespace MediaTracker.Server.Services.Storage;

public sealed class AppPaths
{
    public AppPaths(string dataDirectory)
    {
        DataDirectory = dataDirectory;
        CoversDirectory = Path.Combine(dataDirectory, "data", "covers");
        LogsDirectory = Path.Combine(dataDirectory, "data", "logs");

        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(CoversDirectory);
        Directory.CreateDirectory(LogsDirectory);
    }

    public string DataDirectory { get; }

    public string CoversDirectory { get; }

    public string LogsDirectory { get; }

    public string DatabaseFilePath => Path.Combine(DataDirectory, "tracker.db");
}