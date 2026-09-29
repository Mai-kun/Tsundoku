namespace MediaTracker.Server.Services.Storage;

public sealed class AppPaths
{
    public AppPaths(string dataDirectory)
    {
        DataDirectory = dataDirectory;
        CoversDirectory = Path.Combine(dataDirectory, "data", "covers");

        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(CoversDirectory);
    }

    public string DataDirectory { get; }

    public string CoversDirectory { get; }


    public string DatabaseFilePath => Path.Combine(DataDirectory, "tracker.db");
}