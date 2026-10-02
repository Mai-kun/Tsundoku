namespace MediaTracker.Server.Infrastructure;

public enum TsundokuRunMode
{
    Combined,
    Headless,
    GuiOnly
}

/// <summary>
/// Hand-rolled parser for the process arguments, so Program.cs only branches on the resolved
/// mode instead of sniffing raw strings. Container env vars still win when no explicit mode
/// flag is passed.
/// </summary>
public sealed class CommandLineOptions
{
    public const int DefaultPort = 5000;
    public const string DefaultServerUrl = "http://127.0.0.1:5000";

    public TsundokuRunMode Mode { get; private set; } = TsundokuRunMode.Combined;
    public int? Port { get; private set; }
    public string? ServerUrl { get; private set; }
    public string? DataDirectory { get; private set; }
    public bool MigrateOnly { get; private set; }
    public bool ShowHelp { get; private set; }
    public bool RunSelfCheck { get; private set; }
    public string? Error { get; private set; }

    public bool IsHeadless => Mode == TsundokuRunMode.Headless;

    public static bool IsRunningInContainer =>
        string.Equals(
            Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"),
            "true",
            StringComparison.OrdinalIgnoreCase);

    public static CommandLineOptions Parse(string[] args)
    {
        var options = new CommandLineOptions();
        TsundokuRunMode? requestedMode = null;

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];

            switch (arg)
            {
                case "--headless":
                case "--server-only":
                    requestedMode = TsundokuRunMode.Headless;
                    break;

                case "--gui":
                case "--client-only":
                    requestedMode = TsundokuRunMode.GuiOnly;
                    break;

                case "--migrate-only":
                    options.MigrateOnly = true;
                    break;

                case "--help":
                case "-h":
                case "-?":
                    options.ShowHelp = true;
                    break;

                case "--selfcheck":
                    options.RunSelfCheck = true;
                    break;

                case "--port":
                case "-p":
                {
                    if (!TryTakeValue(args, ref i, out var rawPort))
                    {
                        return options.WithError($"Missing value for '{arg}'.");
                    }

                    if (!int.TryParse(rawPort, out var port) || port is < 1 or > 65535)
                    {
                        return options.WithError($"Invalid port '{rawPort}'. Expected a number between 1 and 65535.");
                    }

                    options.Port = port;
                    break;
                }

                case "--server-url":
                {
                    if (!TryTakeValue(args, ref i, out var serverUrl))
                    {
                        return options.WithError($"Missing value for '{arg}'.");
                    }

                    if (!Uri.TryCreate(serverUrl, UriKind.Absolute, out var parsed)
                        || (parsed.Scheme != Uri.UriSchemeHttp && parsed.Scheme != Uri.UriSchemeHttps))
                    {
                        return options.WithError($"Invalid --server-url '{serverUrl}'. Expected an absolute http(s) URL.");
                    }

                    options.ServerUrl = serverUrl.TrimEnd('/');
                    break;
                }

                case "--data-dir":
                {
                    if (!TryTakeValue(args, ref i, out var dataDirectory))
                    {
                        return options.WithError($"Missing value for '{arg}'.");
                    }

                    options.DataDirectory = dataDirectory;
                    break;
                }

                default:
                    if (arg.StartsWith('-'))
                    {
                        return options.WithError($"Unknown option '{arg}'.");
                    }

                    break;
            }
        }

        var environmentForcesHeadless = IsRunningInContainer
            || string.Equals(
                Environment.GetEnvironmentVariable("HEADLESS"),
                "true",
                StringComparison.OrdinalIgnoreCase);

        options.Mode = requestedMode
                       ?? (environmentForcesHeadless ? TsundokuRunMode.Headless : TsundokuRunMode.Combined);
        options.ServerUrl ??= options.Port is { } kestrelPort
            ? $"http://127.0.0.1:{kestrelPort}"
            : DefaultServerUrl;

        return options;
    }

    public static string HelpText => """
        Tsundoku - MediaTracker.Server

        Usage:
          Tsundoku.exe [options]

        Options:
          --headless, --server-only    Run only the ASP.NET Core web server (Docker / service mode).
                                     No Photino window is created.
          --gui, --client-only         Run only the Photino desktop window. The embedded Kestrel
                                     server and the database migrations are not started.
          --server-url <url>           Address the --gui window connects to. Default: http://127.0.0.1:5000
          --port <number>, -p <number> Override the Kestrel listening port. Default: 5000
          --data-dir <path>            Base folder for tracker.db, logs and covers.
                                     Default: %LOCALAPPDATA%\Tsundoku (current directory in Docker)
          --migrate-only               Apply database migrations and exit with code 0.
          --help, -h                   Show this help and exit.

        Examples:
          Tsundoku.exe                                          Backend in background + desktop window
          Tsundoku.exe --headless -p 8080                       Web server only on port 8080
          Tsundoku.exe --gui --server-url http://192.168.1.50:5000
          Tsundoku.exe --port 5050 --data-dir D:\TsundokuData
          Tsundoku.exe --migrate-only                           CI/CD migration step

        Environment variables:
          DOTNET_RUNNING_IN_CONTAINER=true or HEADLESS=true  force --headless
          ASPNETCORE_URLS                                      used when --port is not given

        """;

    private static bool TryTakeValue(string[] args, ref int index, out string value)
    {
        if (index + 1 >= args.Length || args[index + 1].StartsWith('-'))
        {
            value = string.Empty;
            return false;
        }

        value = args[++index];
        return true;
    }

    private CommandLineOptions WithError(string error)
    {
        Error = error;
        return this;
    }
}
