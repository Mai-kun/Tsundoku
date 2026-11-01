using System.Diagnostics;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Opens the UI without a webview runtime: a dedicated Chromium-family `--app` window when one
/// is installed, otherwise a tab in the system default browser (Zen / Firefox / Edge / Safari).
/// The spawned window is kept in <see cref="ActiveBrowserProcess"/> so shutdown can close it.
/// </summary>
public static class BrowserLauncher
{
    /// <summary>The Chromium process opened by the last successful launch, if any.</summary>
    private static Process? ActiveBrowserProcess;

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
        try
        {
            if (OperatingSystem.IsLinux())
            {
                OpenOnLinux(url, preferAppWindow);
            }
            else if (OperatingSystem.IsWindows())
            {
                OpenOnWindows(url, preferAppWindow);
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
        var profileDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Tsundoku",
            "tsundoku-chromium-profile");

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
        startInfo.ArgumentList.Add("--class=Tsundoku");
        startInfo.ArgumentList.Add($"--window-size={windowSize}");
        startInfo.ArgumentList.Add("--ozone-platform-hint=auto");
        startInfo.ArgumentList.Add("--password-store=basic");
        startInfo.ArgumentList.Add("--no-first-run");
        startInfo.ArgumentList.Add("--no-default-browser-check");
        startInfo.ArgumentList.Add("--disable-features=Translate,GlobalMediaControls,MediaRouter,OptimizationHints");
        startInfo.ArgumentList.Add("--enable-gpu-rasterization");
        startInfo.ArgumentList.Add("--enable-zero-copy");
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
            ActiveBrowserProcess = child;
            return true;
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Failed to launch {Browser}", browser.FullName);
            return false;
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

        try
        {
            if (process.HasExited)
            {
                return;
            }

            // CloseMainWindow is a no-op on Unix; fall back to a hard kill there.
            if (!process.CloseMainWindow())
            {
                process.Kill(entireProcessTree: true);
            }
            else if (!process.WaitForExit(milliseconds: 1500))
            {
                process.Kill(entireProcessTree: true);
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

    private static FileInfo? FindInPath(string binary)
    {
        var pathVariable = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathVariable))
        {
            return null;
        }

        foreach (var directory in pathVariable.Split(':', StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = new FileInfo(Path.Combine(directory.TrimEnd('/'), binary));
            if (candidate is { Exists: true, Length: > 0 })
            {
                return candidate;
            }
        }

        return null;
    }
}
