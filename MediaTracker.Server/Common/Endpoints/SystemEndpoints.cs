using System.Diagnostics;
using System.Runtime.InteropServices;
using MediaTracker.Server.Infrastructure.Desktop;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Common.Endpoints;

/// <summary>
/// Desktop-shell control endpoints: the second-instance handshake, the log console and
/// the "Выход" action (tray and UI both route through them). Loopback callers are
/// already trusted by ApiKeyAuthMiddleware, so the tray needs no API key.
/// </summary>
public static class SystemEndpoints
{
    public static IEndpointRouteBuilder MapSystemEndpoints(
        this IEndpointRouteBuilder app, DesktopLinks links, AppPaths appPaths)
    {
        app.MapPost("/api/system/open-ui", () =>
            {
                BrowserLauncher.OpenUrl(links.UiUrl);
                return Results.NoContent();
            })
            .WithTags("Система / System")
            .WithSummary("Открыть окно приложения (Chromium --app или вкладка браузера)")
            .ExcludeFromDescription();

        app.MapPost("/api/system/open-logs", () =>
            {
                BrowserLauncher.OpenUrl(links.LogsUrl);
                return Results.NoContent();
            })
            .WithTags("Система / System")
            .WithSummary("Открыть консоль логов")
            .ExcludeFromDescription();

        app.MapPost("/api/system/switch-to-browser", ([FromBody] SwitchToBrowserRequest? request) =>
        {
            // `preferAppWindow: false` forces a tab in the system default browser
            // (xdg-open / Zen), instead of a --app window owned by the server.
            var targetUrl = string.IsNullOrWhiteSpace(request?.Url) ? "http://127.0.0.1:5000" : request.Url;
            BrowserLauncher.OpenUrl(targetUrl, preferAppWindow: false);
            BrowserLauncher.CloseBrowser(); // закрываем окно Chromium --app
            return Results.NoContent();
        })
        .WithTags("Система / System")
        .WithSummary("Переключить текущую вкладку в системный браузер, закрыв окно Chromium --app")
        .ExcludeFromDescription();

        app.MapPost("/api/system/shutdown", (
                [FromServices] IHostApplicationLifetime lifetime) =>
            {
                // Stop after the 204 response has been flushed so the caller sees success.
                _ = Task.Run(async () =>
                {
                    BrowserLauncher.CloseBrowser();
                    await Task.Delay(500);
                    lifetime.StopApplication();
                });
                return Results.NoContent();
            })
            .WithTags("Система / System")
            .WithSummary("Корректно завершить работу Tsundoku");

        app.MapGet("/api/system/rate-limits", ([FromServices] RateLimitTracker rateLimitTracker) =>
            Results.Ok(rateLimitTracker.GetAll()))
            .WithTags("Система / System")
            .WithSummary("Получить список активных лимитов внешних API");

        app.MapPost("/api/system/trim-memory", ([FromServices] IMemoryCache cache, [FromServices] AppPaths appPaths) =>
        {
            var before = MemoryOptimizer.TakeSnapshot();
            MemoryOptimizer.TrimMemory(cache, $"Data Source={appPaths.DatabaseFilePath}");
            var after = MemoryOptimizer.TakeSnapshot();
            return Results.Ok<MemoryOptimizer.TrimMemoryResponse>(new(
                before,
                after,
                Math.Round((before.WorkingSetMb - after.WorkingSetMb) * 10) / 10,
                Math.Round((before.GcHeapMb - after.GcHeapMb) * 10) / 10));
        })
        .WithTags("Система / System")
        .WithSummary("Сжать память: сбросить кэши, собрать мусор и вернуть страницы ОС");

        app.MapPost("/api/system/reveal-in-explorer", ([FromBody] RevealInExplorerRequest? request, [FromServices] AppPaths appPaths) =>
        {
            var rawPath = request?.Path?.Trim();
            if (string.IsNullOrWhiteSpace(rawPath))
            {
                return Results.BadRequest(new { error = "Path is required" });
            }

            // Relative paths resolve against the data directory, so the UI can name
            // "media/{id}/covers/..." without knowing where the server stores its files.
            var fullPath = Path.IsPathRooted(rawPath)
                ? Path.GetFullPath(rawPath)
                : Path.GetFullPath(Path.Combine(appPaths.DataDirectory, rawPath));

            if (!File.Exists(fullPath) && !Directory.Exists(fullPath))
            {
                return Results.NotFound(new { error = $"Path not found: {fullPath}" });
            }

            if (RevealInFileManager(fullPath))
            {
                return Results.NoContent();
            }

            return Results.StatusCode(StatusCodes.Status500InternalServerError);
        })
        .WithTags("Система / System")
        .WithSummary("Показать файл или папку в системном проводнике");

        app.MapPost("/api/system/open-data-dir", ([FromServices] AppPaths appPaths) =>
        {
            if (OpenInFileManager(appPaths.DataDirectory))
            {
                return Results.NoContent();
            }

            return Results.StatusCode(StatusCodes.Status500InternalServerError);
        })
        .WithTags("Система / System")
        .WithSummary("Открыть папку данных приложения в системном проводнике");

        return app;
    }

    public record SwitchToBrowserRequest(string? Url);

    public record RevealInExplorerRequest(string? Path);

    /// <summary>
    /// Selects <paramref name="path"/> in the platform file manager. For a directory most managers
    /// just open it; the "select" behavior only makes sense for files.
    /// </summary>
    private static bool RevealInFileManager(string path)
    {
        if (Directory.Exists(path))
        {
            return OpenInFileManager(path);
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return TryStart(() => Process.Start(
                new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true }));
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return TryStart(() => Process.Start("open", $"-R \"{path}\""));
        }

        // Linux: file managers have no universal "select" verb, so the parent folder opens instead.
        return OpenInFileManager(Path.GetDirectoryName(path) ?? "/");
    }

    /// <summary>Opens <paramref name="path"/> (a directory) in the platform file manager.</summary>
    private static bool OpenInFileManager(string path)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return TryStart(() => Process.Start(
                new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true }));
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return TryStart(() => Process.Start("open", $"\"{path}\""));
        }

        return TryStart(() => Process.Start(
            new ProcessStartInfo("xdg-open", path) { UseShellExecute = true }));
    }

    private static bool TryStart(Func<Process?> start)
    {
        try
        {
            return start() is not null;
        }
        catch (Exception ex)
        {
            // Headless servers have no file manager to launch; the caller answers 500 and the UI
            // surfaces a toast rather than dying silently.
            Console.Error.WriteLine($"[System] Failed to open file manager: {ex.Message}");
            return false;
        }
    }
}
