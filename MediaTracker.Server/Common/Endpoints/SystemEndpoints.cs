using MediaTracker.Server.Infrastructure.Desktop;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

/// <summary>
/// Desktop-shell control endpoints: the second-instance handshake, the log console and
/// the "Выход" action (tray and UI both route through them). Loopback callers are
/// already trusted by ApiKeyAuthMiddleware, so the tray needs no API key.
/// </summary>
public static class SystemEndpoints
{
    public static IEndpointRouteBuilder MapSystemEndpoints(
        this IEndpointRouteBuilder app, DesktopLinks links)
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

        return app;
    }
}
