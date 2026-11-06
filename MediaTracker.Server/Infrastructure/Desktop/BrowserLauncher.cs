using System.Diagnostics;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Opens the UI without a webview runtime: a dedicated Chromium-family `--app` window when one
/// is installed, otherwise a tab in the system default browser (Zen / Firefox / Edge / Safari).
/// The spawned window is kept in <see cref="ActiveBrowserProcess"/> so shutdown can close it.
/// </summary>
public static class BrowserLauncher
{
    public const string LaunchModeKey = "App_LaunchMode";
    public const string CloseActionKey = "App_CloseAction";
    public const string DefaultLaunchMode = "app_window";
    public const string DefaultCloseAction = "minimize_to_tray";

    /// <summary>The Chromium process opened by the last successful launch, if any.</summary>
    private static Process? ActiveBrowserProcess;

    /// <summary>Set while the server itself closes the window, so its exit is not user-initiated.</summary>
    private static volatile bool _closingBrowser;

    private static IHostApplicationLifetime? _hostLifetime;
    private static IServiceProvider? _services;

    /// <summary>`app_window` (Chromium --app) or `browser_tab` (default browser).</summary>
    public static string LaunchMode { get; private set; } = DefaultLaunchMode;

    /// <summary>`minimize_to_tray` or `exit_all`, applied when the user closes the app window.</summary>
    public static string CloseAction { get; private set; } = DefaultCloseAction;

    /// <summary>
    /// Isolated Chromium profile, kept strictly inside the storage root (./data in portable
    /// mode), so portable installs never write into the system app-data folder. Set once at
    /// startup; falls back to the app folder when storage has not been resolved yet.
    /// </summary>
    private static string ProfileDirectory =
        Path.Combine(AppPaths.GetAppDirectory(), "data", "chromium-profile");

    /// <summary>Wires the host shutdown path and loads the persisted launch/close behavior.</summary>
    public static async Task InitializeAsync(IServiceProvider services, IHostApplicationLifetime lifetime)
    {
        _services = services;
        _hostLifetime = lifetime;
        var appPaths = services.GetRequiredService<AppPaths>();
        ProfileDirectory = Path.Combine(appPaths.DataDirectory, "chromium-profile");
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        ApplySettings(
            await AppSettingStore.ReadAsync(db, LaunchModeKey) ?? DefaultLaunchMode,
            await AppSettingStore.ReadAsync(db, CloseActionKey) ?? DefaultCloseAction);
    }

    public static void ApplySettings(string launchMode, string closeAction)
    {
        LaunchMode = launchMode;
        CloseAction = closeAction;
    }

    /// <summary>Chromium-family launchers tried (in order) for a native chrome-less window.</summary>
    private static readonly string[] ChromiumBrowsers =
    [
        "chromium",
        "chromium-browser",
        "google-chrome-stable",
        "google-chrome",
        "brave-browser",
        "vivaldi",
        "microsoft-edge",
    ];

    /// <summary>Debug escape hatch: TSUNDOKU_BROWSER_MODE=tab forces a default-browser tab.</summary>
    private static bool PreferTabMode =>
        string.Equals(
            Environment.GetEnvironmentVariable("TSUNDOKU_BROWSER_MODE"),
            "tab",
            StringComparison.OrdinalIgnoreCase);

    public static void OpenUrl(string url, bool preferAppWindow = true)
    {
        // The persisted setting wins over the caller's preference (e.g. the log console).
        var useAppWindow = preferAppWindow
            && !string.Equals(LaunchMode, "browser_tab", StringComparison.OrdinalIgnoreCase);
        try
        {
            if (OperatingSystem.IsLinux())
            {
                OpenOnLinux(url, useAppWindow);
            }
            else if (OperatingSystem.IsWindows())
            {
                OpenOnWindows(url, useAppWindow);
            }
            else if (OperatingSystem.IsMacOS())
            {
                Process.Start("open", url);
            }
            else
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Failed to open {Url} in a browser", url);
        }
    }

    private static void OpenOnLinux(string url, bool preferAppWindow)
    {
        if (preferAppWindow && !PreferTabMode)
        {
            foreach (var browser in ChromiumBrowsers)
            {
                var path = FindInPath(browser);
                if (path is null)
                {
                    continue;
                }

                if (TryLaunchChromiumApp(path, url))
                {
                    Serilog.Log.Information("Opened {Url} in {Browser} (--app window)", url, path);
                    return;
                }
            }
        }

        // Fallback: a tab in the user's default browser (Zen, Firefox, ...).
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            Serilog.Log.Information("Opened {Url} in the default browser", url);
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "No browser could open {Url}; the server keeps running at {Url}", url, url);
        }
    }

    private static void OpenOnWindows(string url, bool preferAppWindow)
    {
        if (preferAppWindow && !PreferTabMode)
        {
            // Chromium installs live in Program Files, not on PATH; probe the common locations.
            foreach (var candidate in EnumerateWindowsChromiumCandidates())
            {
                if (TryLaunchChromiumApp(new FileInfo(candidate), url))
                {
                    Serilog.Log.Information("Opened {Url} in {Browser} (--app window)", url, candidate);
                    return;
                }
            }
        }

        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        Serilog.Log.Information("Opened {Url} in the default browser", url);
    }

    private static IEnumerable<string> EnumerateWindowsChromiumCandidates()
    {
        var programDirs = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Google", "Application"),
        };

        var relatives = new[]
        {
            Path.Combine("Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine("Chromium", "Application", "chrome.exe"),
            Path.Combine("BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
            Path.Combine("Vivaldi", "Application", "vivaldi.exe"),
            Path.Combine("Microsoft", "Edge", "Application", "msedge.exe"),
        };

        foreach (var root in programDirs)
        {
            if (string.IsNullOrEmpty(root))
            {
                continue;
            }

            foreach (var relative in relatives)
            {
                var full = Path.Combine(root, relative);
                if (File.Exists(full))
                {
                    yield return full;
                }
            }
        }
    }

    private static bool TryLaunchChromiumApp(FileInfo browser, string url)
    {
        var windowSize = url.EndsWith("/logs.html", StringComparison.OrdinalIgnoreCase)
            ? "1280,720"
            : "1400,900";
        var profileDir = ProfileDirectory;
        ClearStaleProfileLocks(profileDir);

        var startInfo = new ProcessStartInfo
        {
            FileName = browser.FullName,
            UseShellExecute = false,
            CreateNoWindow = true,
            // Chromium chatters on stderr (zygote broken-pipe noise when handing off to
            // an existing instance); drain the pipes to keep the server console clean.
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        startInfo.ArgumentList.Add($"--app={url}");
        startInfo.ArgumentList.Add($"--user-data-dir={profileDir}");
        // Window identity: WM_CLASS on X11, the Wayland app id and the shell's window name all
        // must match StartupWMClass=Tsundoku in tsundoku.desktop, or the taskbar/dock pairs the
        // --app window with the running Chromium instead of the Tsundoku icon.
        startInfo.ArgumentList.Add("--class=Tsundoku");
        startInfo.ArgumentList.Add("--name=Tsundoku");
        startInfo.ArgumentList.Add("--app-id=tsundoku");
        startInfo.ArgumentList.Add($"--window-size={windowSize}");
        // Let Ozone pick the platform (native Wayland on Wayland sessions, X11 on X11): forcing
        // XWayland broke mouse clicks in modal dialogs and flickered the whole screen on drag.
        // The taskbar icon is still matched by the desktop entry's StartupWMClass, which the
        // Wayland compositor pairs through the app window's resource class.
        startInfo.ArgumentList.Add("--ozone-platform-hint=auto");
        startInfo.ArgumentList.Add("--password-store=basic");
        startInfo.ArgumentList.Add("--no-first-run");
        startInfo.ArgumentList.Add("--no-default-browser-check");
        // Anti-zombie flags: without these a closed --app window leaves background Chromium
        // helper processes (network stack, extensions, component updater) pinned in RAM after
        // the user believes the app is closed.
        startInfo.ArgumentList.Add("--disable-background-mode");
        startInfo.ArgumentList.Add("--disable-background-networking");
        startInfo.ArgumentList.Add("--disable-component-update");
        startInfo.ArgumentList.Add("--disable-sync");
        startInfo.ArgumentList.Add("--disable-extensions");
        startInfo.ArgumentList.Add("--disable-features=Translate,GlobalMediaControls,MediaRouter,OptimizationHints");
        startInfo.ArgumentList.Add("--disable-translate");
        // Hardware GPU pipeline: without --ignore-gpu-blocklist Chromium 150+ falls back to
        // software rasterization on several Linux drivers, which shows up as window flicker
        // on drag and a visible white flash on first paint.
        startInfo.ArgumentList.Add("--enable-gpu-rasterization");
        startInfo.ArgumentList.Add("--enable-zero-copy");
        startInfo.ArgumentList.Add("--ignore-gpu-blocklist");
        startInfo.ArgumentList.Add("--force-dark-mode");

        try
        {
            var child = Process.Start(startInfo);
            if (child is null)
            {
                return false;
            }

            // Drain-to-discard: the redirected pipes must be consumed continuously or a
            // chatty child blocks once its pipe buffer fills.
            child.OutputDataReceived += (_, _) => { };
            child.ErrorDataReceived += (_, _) => { };
            child.BeginOutputReadLine();
            child.BeginErrorReadLine();

            // A successful Process.Start is enough: on Linux Chromium normally hands the
            // request to an already-running instance and exits the launcher with code 0.
            // Waiting here would misread that handoff as a crash and open a second window.
            var launchedAt = Stopwatch.GetTimestamp();
            child.EnableRaisingEvents = true;
            child.Exited += (_, _) =>
            {
                // shortcut: a handoff exit happens within a second or two; a real window
                // cannot be closed that fast in practice. Upgrade to a Chromium IPC signal
                // if false positives ever appear.
                if (Stopwatch.GetElapsedTime(launchedAt).TotalSeconds < 3)
                {
                    return;
                }

                OnBrowserWindowClosed();
            };

            ActiveBrowserProcess = child;
            return true;
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Failed to launch {Browser}", browser.FullName);
            return false;
        }
    }

    /// <summary>User closed the Chromium window: honor the persisted close action.</summary>
    private static async void OnBrowserWindowClosed()
    {
        try
        {
            if (_closingBrowser)
            {
                return;
            }

            var closeAction = CloseAction;
            IMemoryCache? cache = null;
            string? sqliteConnectionString = null;
            if (_services?.GetService(typeof(IServiceScopeFactory)) is IServiceScopeFactory scopeFactory)
            {
                using var scope = scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                closeAction = await AppSettingStore.ReadAsync(db, CloseActionKey) ?? closeAction;
                cache = scope.ServiceProvider.GetService<IMemoryCache>();
                var appPaths = scope.ServiceProvider.GetService<AppPaths>();
                sqliteConnectionString = appPaths is null ? null : $"Data Source={appPaths.DatabaseFilePath}";
            }

            // Nothing may outlive the window: kill whatever of the Chromium tree survived the
            // graceful exit (helper children on Windows, half-detached sandboxes on Linux).
            KillBrowserTree();

            if (string.Equals(closeAction, "exit_all", StringComparison.OrdinalIgnoreCase))
            {
                Serilog.Log.Information("[Desktop] App window closed by user. Shutting down Tsundoku...");
                _hostLifetime?.StopApplication();
            }
            else
            {
                Serilog.Log.Information("[Desktop] App window closed. Tsundoku continues running in tray.");

                // The shell just went quiet: no window means no requests for a while, so hand the
                // freed caches and Chromium allocations back to the OS right away instead of
                // waiting for the idle-sleep timer.
                var before = MemoryOptimizer.TakeSnapshot();
                MemoryOptimizer.TrimMemory(cache);
                var after = MemoryOptimizer.TakeSnapshot();
                Serilog.Log.Information(
                    "[Memory] Trimmed after window close. Working set {BeforeMb} MB -> {AfterMb} MB.",
                    before.WorkingSetMb,
                    after.WorkingSetMb);
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Failed to handle the browser window exit");
        }
    }

    /// <summary>Kills the whole Chromium process tree of the tracked launcher, if any of it is left.</summary>
    private static void KillBrowserTree()
    {
        var process = ActiveBrowserProcess;
        if (process is null || process.HasExited)
        {
            return;
        }

        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch (Exception error)
        {
            Serilog.Log.Debug(error, "Chromium tree was already gone when closing");
        }
    }

    /// <summary>Closes the Chromium window opened by this server, if it is still running.</summary>
    public static void CloseBrowser()
    {
        var process = ActiveBrowserProcess;
        ActiveBrowserProcess = null;
        if (process is null)
        {
            return;
        }

        _closingBrowser = true;

        try
        {
            if (!process.HasExited)
            {
                // CloseMainWindow is a no-op on Unix; fall back to a hard kill there.
                if (!process.CloseMainWindow())
                {
                    process.Kill(entireProcessTree: true);
                }
                else if (!process.WaitForExit(milliseconds: 1500))
                {
                    process.Kill(entireProcessTree: true);
                }

                // The graceful close must never leave helper children behind.
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Failed to close the browser window");
        }
        finally
        {
            process.Dispose();
        }
    }

    /// <summary>
    /// A hard-killed Chromium leaves SingletonLock/SingletonSocket/SingletonCookie in the profile,
    /// and the next launch spends ~5 seconds probing the dead socket before giving up and starting
    /// fresh. The lock is a symlink to "hostname-PID": clean it only when that PID is gone, so a
    /// live window (tray relaunch while the app is open) keeps its handoff target intact. The same
    /// hard kill sets exit_type=Crashed in Preferences, which makes Chromium show the restore
    /// prompt and start the next session with GPU disabled — reset it to Normal.
    /// </summary>
    /// <summary>
    /// Chromium writes "hostname-PID" into the SingletonLock symlink target. The PID is the
    /// dash-free digit tail: a hostname containing its own dashes still parses, matching the
    /// old two-part shape, and span slicing keeps the lock-cleanup path allocation-free.
    /// </summary>
    private static bool TryGetLockOwnerPid(string target, out int ownerPid)
    {
        ownerPid = 0;
        var dash = target.IndexOf('-');
        return dash >= 0
            && dash < target.Length - 1
            && char.IsAsciiDigit(target[dash + 1])
            && int.TryParse(target.AsSpan(dash + 1), out ownerPid);
    }

    private static void ClearStaleProfileLocks(string profileDir)
    {
        try
        {
            foreach (var lockName in new[] { "SingletonLock", "SingletonSocket", "SingletonCookie" })
            {
                var lockPath = Path.Combine(profileDir, lockName);
                if (!File.Exists(lockPath) && !Directory.Exists(lockPath))
                {
                    continue;
                }

                if (lockName == "SingletonLock"
                    && Path.GetFileName(File.ResolveLinkTarget(lockPath, returnFinalTarget: false)?.FullName ?? string.Empty)
                        is { Length: > 0 } target
                    && TryGetLockOwnerPid(target, out var ownerPid)
                    && Process.GetProcessById(ownerPid) is { HasExited: false })
                {
                    continue; // a live Chromium instance owns this profile
                }

                File.Delete(lockPath);
            }

            var prefsFile = Path.Combine(profileDir, "Default", "Preferences");
            if (File.Exists(prefsFile))
            {
                var text = File.ReadAllText(prefsFile);
                if (text.Contains("\"exit_type\":\"Crashed\"", StringComparison.Ordinal))
                {
                    File.WriteAllText(prefsFile, text.Replace("\"exit_type\":\"Crashed\"", "\"exit_type\":\"Normal\""));
                }
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Debug(error, "Failed to clean stale Chromium profile locks");
        }
    }

    private static FileInfo? FindInPath(string binary)
    {
        var pathVariable = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathVariable))
        {
            return null;
        }

        foreach (var range in MemoryExtensions.Split(pathVariable.AsSpan(), ':'))
        {
            var segment = pathVariable.AsSpan()[range];
            if (segment.IsEmpty)
            {
                continue;
            }

            var candidate = new FileInfo(Path.Combine(segment.ToString().TrimEnd('/'), binary));
            if (candidate is { Exists: true, Length: > 0 })
            {
                return candidate;
            }
        }

        return null;
    }
}
