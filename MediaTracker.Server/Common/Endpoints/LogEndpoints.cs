using System.Diagnostics;
using System.Runtime.InteropServices;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Logs.ClientLog;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class LogEndpoints
{
    /// <summary>Какой хвост последнего лога отдаём: последние строки ограничены и по числу, и по объёму.</summary>
    private const int TailMaxLines = 250;
    private const long TailMaxBytes = 128 * 1024;

    public static IEndpointRouteBuilder MapLogEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/logs/client", (
                ClientLogRequest request,
                [FromServices] IClientLogHandler handler) =>
            handler.Handle(request).ToNoContent())
            .WithTags("Система / System")
            .WithSummary("Запись клиентских логов")
            .WithDescription("Принимает сообщения об ошибках и событиях с фронтенда для централизованного логирования на сервере.");

        app.MapGet("/api/logs/latest", ([FromServices] AppPaths appPaths) =>
        {
            var dir = appPaths.LogsDirectory;
            if (!Directory.Exists(dir)) return Results.Text("Логи отсутствуют.");

            var latest = Directory.GetFiles(dir, "session_*.log")
                .Select(f => new FileInfo(f))
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .FirstOrDefault();
            if (latest is null) return Results.Text("Логи отсутствуют.");

            // Serilog держит файл открытым (shared), поэтому читаем с FileShare.ReadWrite.
            // Хвост ограничен по объёму: длинная сессия может вырастать до многих мегабайт.
            using var fs = new FileStream(
                latest.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (fs.Length > TailMaxBytes)
            {
                fs.Seek(-TailMaxBytes, SeekOrigin.End);
            }

            using var sr = new StreamReader(fs);
            // Первая строка после сдвига может быть обрезана посередине — отбрасываем её.
            sr.ReadLine();

            var content = sr.ReadToEnd();
            var lines = content.Split('\n');
            var tail = lines.Length > TailMaxLines
                ? string.Join('\n', lines[^TailMaxLines..])
                : content;

            return Results.Text(tail, "text/plain; charset=utf-8");
        })
        .ExcludeFromDescription();

        app.MapGet("/api/logs/telemetry", (AppDbContext db, AppPaths appPaths) =>
        {
            var process = Process.GetCurrentProcess();
            var workingSetMb = Math.Round(process.WorkingSet64 / 1024.0 / 1024.0, 1);
            var gcHeapMb = Math.Round(GC.GetTotalMemory(false) / 1024.0 / 1024.0, 1);
            var uptime = DateTime.UtcNow - process.StartTime.ToUniversalTime();

            string? localIp = null;
            try
            {
                localIp = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up &&
                                n.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback)
                    .SelectMany(n => n.GetIPProperties().UnicastAddresses)
                    .FirstOrDefault(a => a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)?.Address.ToString();
            }
            catch {}

            long dbSizeBytes = 0;
            try { if (File.Exists(appPaths.DatabaseFilePath)) dbSizeBytes = new FileInfo(appPaths.DatabaseFilePath).Length; } catch {}

            return Results.Ok(new
            {
                processRamMb = workingSetMb,
                gcHeapMb = gcHeapMb,
                uptime = $"{(int)uptime.TotalHours:D2}:{uptime.Minutes:D2}:{uptime.Seconds:D2}",
                localIp = localIp ?? "127.0.0.1",
                os = RuntimeInformation.OSDescription,
                pid = process.Id,
                threads = process.Threads.Count,
                dbSizeMb = Math.Round(dbSizeBytes / 1024.0 / 1024.0, 2),
                architecture = $"{RuntimeInformation.ProcessArchitecture} (NativeAOT)"
            });
        }).ExcludeFromDescription();

        return app;
    }
}
