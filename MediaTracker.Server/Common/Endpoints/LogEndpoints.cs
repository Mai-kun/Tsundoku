using System.Diagnostics;
using System.Runtime.InteropServices;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Logs.ClientLog;
using MediaTracker.Server.Features.Logs.Telemetry;
using MediaTracker.Server.Infrastructure.Logging;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.Infrastructure.Persistence;
using System.Net.NetworkInformation;
using System.Net.Sockets;
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

        app.MapGet("/api/logs/telemetry", (AppPaths appPaths) =>
        {
            var currentProc = Process.GetCurrentProcess();
            var processRamMb = Math.Round(currentProc.WorkingSet64 / 1024.0 / 1024.0, 1);
            var gcHeapMb = Math.Round(GC.GetTotalMemory(false) / 1024.0 / 1024.0, 1);

            string localIp = "127.0.0.1";
            try
            {
                foreach (var netInterface in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (netInterface.OperationalStatus != OperationalStatus.Up ||
                        netInterface.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                        continue;

                    var ipv4 = netInterface.GetIPProperties().UnicastAddresses
                        .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork &&
                                             !System.Net.IPAddress.IsLoopback(a.Address));
                    if (ipv4 != null)
                    {
                        localIp = ipv4.Address.ToString();
                        break;
                    }
                }
            }
            catch { }

            var uptimeTimeSpan = DateTime.UtcNow - currentProc.StartTime.ToUniversalTime();
            var uptime = $"{(int)uptimeTimeSpan.TotalHours}ч {uptimeTimeSpan.Minutes}м {uptimeTimeSpan.Seconds}с";

            double dbSizeMb = 0;
            try { if (File.Exists(appPaths.DatabaseFilePath)) dbSizeMb = Math.Round(new FileInfo(appPaths.DatabaseFilePath).Length / 1024.0 / 1024.0, 2); } catch { }

            var telemetry = new TelemetryDto(
                ProcessRamMb: processRamMb,
                GcHeapMb: gcHeapMb,
                LocalIp: localIp,
                Uptime: uptime,
                Os: RuntimeInformation.OSDescription,
                Pid: Environment.ProcessId,
                Threads: currentProc.Threads.Count,
                DbSizeMb: dbSizeMb,
                Architecture: $"{RuntimeInformation.ProcessArchitecture} (NativeAOT)",
                Gpu: HardwareDetector.GetGpuName());

            return Results.Ok(telemetry);
        }).ExcludeFromDescription();

        return app;
    }
}
