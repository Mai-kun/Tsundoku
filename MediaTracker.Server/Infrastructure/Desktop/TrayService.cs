using MediaTracker.Server.Common.Cli;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>Links the tray menu and the launcher need; resolved once at startup.</summary>
public sealed record DesktopLinks(string UiUrl, string LogsUrl);

/// <summary>
/// Cross-platform system tray (Linux: GTK + AppIndicator via P/Invoke, Windows:
/// Shell_NotifyIconW on a hidden message window). When the desktop integration is
/// unavailable — headless flags, containers, servers without GTK — the service
/// degrades to a no-op and the web server keeps running.
/// </summary>
public interface ITrayService
{
    bool IsAvailable { get; }
}

public sealed class TrayBackgroundService(
    IHostApplicationLifetime lifetime,
    DesktopLinks links,
    CommandLineOptions options) : BackgroundService, ITrayService
{
    public bool IsAvailable { get; private set; }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (options.IsHeadless || CommandLineOptions.IsRunningInContainer)
        {
            Serilog.Log.Information("Headless mode: tray icon disabled");
            return Task.CompletedTask;
        }

        void OpenUi() => BrowserLauncher.OpenUrl(links.UiUrl);
        void OpenLogs() => BrowserLauncher.OpenUrl(links.LogsUrl);
        void Exit()
        {
            Serilog.Log.Information("Tray: exit requested");
            BrowserLauncher.CloseBrowser();
            lifetime.StopApplication();
        }

        try
        {
            if (OperatingSystem.IsLinux())
            {
                IsAvailable = LinuxTray.TryStart(OpenUi, OpenLogs, Exit);
            }
            else if (OperatingSystem.IsWindows())
            {
                IsAvailable = WindowsTray.TryStart(OpenUi, OpenLogs, Exit);
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Tray initialization failed; continuing without a tray icon");
        }

        if (!IsAvailable)
        {
            Serilog.Log.Information("Tray icon unavailable on this system; continuing headless");
        }

        return Task.CompletedTask;
    }

    public override Task StopAsync(CancellationToken cancellationToken)
    {
        if (OperatingSystem.IsWindows())
        {
            WindowsTray.Shutdown();
        }

        return base.StopAsync(cancellationToken);
    }
}
