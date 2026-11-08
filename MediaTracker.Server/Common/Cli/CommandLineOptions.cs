namespace MediaTracker.Server.Common.Cli;

/// <summary>
/// Hand-rolled parser for the process arguments, so Program.cs only branches on the resolved
/// options instead of sniffing raw strings. The web server itself is always a headless Kestrel
/// service; the desktop shell (tray icon + browser window) is layered on top unless the process
/// is explicitly started headless (server, systemd, Docker).
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

    /// <summary>Skip the tray icon and the automatic browser window (services, containers).</summary>
    public bool IsHeadless { get; private set; }

    /// <summary>Keep the process in the tray without surfacing the UI (autostart, shortcuts).</summary>
    public bool StartMinimized { get; private set; }

    /// <summary>
    /// Internal: PID окна Chromium, пережившего перезапуск (--adopt-browser-pid). Новый процесс
    /// усыновляет его, чтобы закрытие окна и финальный выход работали как в исходном процессе.
    /// </summary>
    public int? BrowserPidToAdopt { get; private set; }

    public bool ImportOfflineDb { get; private set; }
    public string? OfflineDbDumpPath { get; private set; }

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
                // Headless: no tray icon, no browser window (systemd, Docker, scripts).
                case "--headless":
                case "--server-only":
                    options.IsHeadless = true;
                    break;

                // Legacy no-ops kept for backwards compatibility with old shortcuts.
                case "--gui":
                case "--client-only":
                    break;

                // Start in the tray without opening the UI (autostart, shortcuts, internal restart).
                case "--no-browser":
                case "--tray":
                case "--minimized":
                    options.StartMinimized = true;
                    break;

                // Internal: adopt the Chromium window surviving from the previous instance
                // after a scheduled restart (see AppRestartService.ScheduleRestartKeepingWindow).
                // The value is emitted as a separate token — the parser matches case labels by
                // exact equality, so an attached "--adopt-browser-pid=123" would be rejected
                // as an unknown option before this case ever runs.
                case "--adopt-browser-pid":
                    {
                        if (!TryTakeValue(args, ref i, out var rawPid)
                            || !int.TryParse(rawPid, out var adoptPid)
                            || adoptPid <= 0)
                        {
                            return options.WithError($"Invalid value for '{arg}'. Expected a positive process id.");
                        }

                        options.BrowserPidToAdopt = adoptPid;
                        break;
                    }

                case "--import-offline-db":
                    options.ImportOfflineDb = true;
                    break;

                case "--offline-dump":
                    {
                        if (!TryTakeValue(args, ref i, out var dumpPath))
                        {
                            return options.WithError($"Missing value for '{arg}'.");
                        }

                        options.OfflineDbDumpPath = dumpPath;
                        break;
                    }

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

    /// <summary>
    /// The port the UI (and the single-instance handshake) targets: --port wins, then
    /// ASPNETCORE_URLS, then the default — the exact precedence UseUrls() applies.
    /// </summary>
    public int EffectivePort =>
        Port
        ?? TryParseAspnetcoreUrlsPort()
        ?? DefaultPort;

    private static int? TryParseAspnetcoreUrlsPort()
    {
        var urls = Environment.GetEnvironmentVariable("ASPNETCORE_URLS");
        if (string.IsNullOrWhiteSpace(urls))
        {
            return null;
        }

        foreach (var part in urls.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (Uri.TryCreate(part, UriKind.Absolute, out var uri) && uri.Port > 0)
            {
                return uri.Port;
            }
        }

        return null;
    }

    public static string HelpText =>
        """
            Tsundoku - MediaTracker.Server

            Usage:
              Tsundoku.exe [options]

            Options:
              --headless, --server-only    Run without the tray icon and without opening a
                                         browser window (systemd, Docker, scripts).
              --tray, --minimized          Start in the tray; the UI is not opened automatically.
              --no-browser                 Do not launch browser window on startup.
              --import-offline-db          Import anime-offline-database into anime_offline.db.
              --offline-dump <path>        Custom path to anime-offline-database.json(l).
              --gui, --client-only         Legacy no-op.
              --server-url <url>           Address the UI connects to. Default: http://127.0.0.1:5000
              --port <number>, -p <number> Override the Kestrel listening port. Default: 5000
              --data-dir <path>            Base folder for tracker.db, logs and covers.
                                         Default: %LOCALAPPDATA%\Tsundoku (current directory in Docker)
              --dev                        Force development mode (local ./data folder, tracker.dev.db).
              --migrate-only               Apply database migrations and exit with code 0.
              --help, -h                   Show this help and exit.

            Examples:
              Tsundoku                                          Server + tray + UI in the browser
              Tsundoku --port 8080                              Web server on port 8080
              Tsundoku --port 5050 --data-dir D:\TsundokuData   Custom storage location
              Tsundoku --headless                               Pure service (no tray, no UI)
              Tsundoku --migrate-only                           CI/CD migration step

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
