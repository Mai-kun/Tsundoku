namespace MediaTracker.Server.Common.Cli;

/// <summary>
/// Hand-rolled parser for the process arguments, so Program.cs only branches on the resolved
/// options instead of sniffing raw strings. The server is always a headless Kestrel service:
/// the legacy --headless / --gui mode flags are accepted as no-ops for backwards compatibility.
/// </summary>
public sealed class CommandLineOptions
{
    public const int DefaultPort = 5000;
    public const string DefaultServerUrl = "http://127.0.0.1:5000";

    public int? Port { get; private set; }
    public string? ServerUrl { get; private set; }
    public string? DataDirectory { get; private set; }
    public bool MigrateOnly { get; private set; }
    public bool ShowHelp { get; private set; }
    public bool RunSelfCheck { get; private set; }
    public bool IsDevMode { get; private set; }
    public string? Error { get; private set; }

    public static bool IsRunningInContainer =>
        string.Equals(
            Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER"),
            "true",
            StringComparison.OrdinalIgnoreCase
        );

    /// <summary>
    /// Host-provided arguments (WebApplicationFactory / dotnet test inject --environment, --applicationName,
    /// --contentRoot). They configure the generic host and are not Tsundoku options, so they are skipped.
    /// </summary>
    private static readonly string[] HostOnlyArgs = ["--environment", "--applicationName", "--contentRoot"];

    public static CommandLineOptions Parse(string[] args)
    {
        var options = new CommandLineOptions();

        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];

            if (HostOnlyArgs.Contains(arg.Split('=')[0], StringComparer.OrdinalIgnoreCase))
            {
                // Value may be attached (--environment=Development) or separate (--environment Development).
                if (!arg.Contains('=') && i + 1 < args.Length && !args[i + 1].StartsWith('-'))
                {
                    i++;
                }
                continue;
            }

            switch (arg)
            {
                // Legacy run-mode flags: the server is always headless, so they parse as no-ops.
                case "--headless":
                case "--server-only":
                case "--gui":
                case "--client-only":
                    break;

                case "--migrate-only":
                    options.MigrateOnly = true;
                    break;

                case "--dev":
                    options.IsDevMode = true;
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
                            return options.WithError(
                                $"Invalid port '{rawPort}'. Expected a number between 1 and 65535."
                            );
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

                        if (
                            !Uri.TryCreate(serverUrl, UriKind.Absolute, out var parsed)
                            || (
                                parsed.Scheme != Uri.UriSchemeHttp
                                && parsed.Scheme != Uri.UriSchemeHttps
                            )
                        )
                        {
                            return options.WithError(
                                $"Invalid --server-url '{serverUrl}'. Expected an absolute http(s) URL."
                            );
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

        options.ServerUrl ??= options.Port is { } kestrelPort
            ? $"http://127.0.0.1:{kestrelPort}"
            : DefaultServerUrl;

        return options;
    }

    public static string HelpText =>
        """
            Tsundoku - MediaTracker.Server

            Usage:
              Tsundoku.exe [options]

            Options:
              --headless, --server-only    Legacy no-op. The server always runs as a headless
                                         Kestrel web service.
              --gui, --client-only         Legacy no-op. Photino was removed; the UI is served
                                         from wwwroot and opened in any browser.
              --server-url <url>           Address the UI connects to. Default: http://127.0.0.1:5000
              --port <number>, -p <number> Override the Kestrel listening port. Default: 5000
              --data-dir <path>            Base folder for tracker.db, logs and covers.
                                         Default: %LOCALAPPDATA%\Tsundoku (current directory in Docker)
              --dev                        Force development mode (local ./data folder, tracker.dev.db).
              --migrate-only               Apply database migrations and exit with code 0.
              --help, -h                   Show this help and exit.

            Examples:
              Tsundoku.exe                                          Web server on the default port
              Tsundoku.exe --port 8080                              Web server on port 8080
              Tsundoku.exe --port 5050 --data-dir D:\TsundokuData
              Tsundoku.exe --migrate-only                           CI/CD migration step

            Environment variables:
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
