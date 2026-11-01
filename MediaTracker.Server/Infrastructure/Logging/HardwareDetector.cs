using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MediaTracker.Server.Infrastructure.Logging;

/// <summary>
/// Определяет имя видеокарты/чипа хоста. Вызывается один раз за жизнь процесса (Lazy)
/// и служит заменой WebGL-детектору на фронтенде, который под WebKit возвращает маскированное имя.
/// </summary>
public static class HardwareDetector
{
    private static readonly Lazy<string?> GpuNameLazy = new(DetectGpuInternal);

    public static string? GetGpuName() => GpuNameLazy.Value;

    private static string? DetectGpuInternal()
    {
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                // На Apple Silicon видеоядро интегрировано в чип (Apple M1/M2/M3/M4).
                var brand = RunProcess("sysctl", "-n machdep.cpu.brand_string");
                if (!string.IsNullOrWhiteSpace(brand))
                    return brand.Trim();

                var profiler = RunProcess("system_profiler", "SPDisplaysDataType");
                if (!string.IsNullOrWhiteSpace(profiler)
                    && TryFindLine(profiler, "Chipset Model:", out ReadOnlySpan<char> chipsetLine))
                {
                    var colon = chipsetLine.IndexOf(':');
                    if (colon >= 0 && colon < chipsetLine.Length - 1)
                        return chipsetLine[(colon + 1)..].Trim().ToString();
                }
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                var lspci = RunProcess("lspci", "");
                if (!string.IsNullOrWhiteSpace(lspci)
                    && (TryFindLine(lspci, "VGA compatible controller", out ReadOnlySpan<char> gpuLine)
                        || TryFindLine(lspci, "3D controller", out gpuLine)
                        || TryFindLine(lspci, "Display controller", out gpuLine)))
                {
                    var colonIdx = gpuLine.LastIndexOf(':');
                    if (colonIdx >= 0 && colonIdx < gpuLine.Length - 1)
                        return gpuLine[(colonIdx + 1)..].Trim().ToString();
                }

                var nvidia = RunProcess("nvidia-smi", "--query-gpu=name --format=csv,noheader");
                if (!string.IsNullOrWhiteSpace(nvidia))
                {
                    var newline = nvidia.IndexOf('\n');
                    return (newline < 0 ? nvidia : nvidia[..newline]).Trim();
                }
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                var wmic = RunProcess("powershell", "-NoProfile -Command \"(Get-CimInstance Win32_VideoController).Name | Select-Object -First 1\"");
                if (!string.IsNullOrWhiteSpace(wmic))
                    return wmic.Trim();
            }
        }
        catch
        {
            // Fallback: вернет null, фронтенд покажет WebGL значение.
        }

        return null;
    }

    /// <summary>
    /// Line scan without materializing a string[]: the detector runs under the
    /// request-agnostic one-shot lazy path, but system_profiler output is large
    /// enough that a blind Split would heap-allocate hundreds of lines.
    /// </summary>
    private static bool TryFindLine(string text, string marker, out ReadOnlySpan<char> line)
    {
        ReadOnlySpan<char> rest = text;
        while (!rest.IsEmpty)
        {
            var newline = rest.IndexOf('\n');
            ReadOnlySpan<char> current = newline < 0 ? rest : rest[..newline];
            if (current.Contains(marker, StringComparison.OrdinalIgnoreCase))
            {
                line = current;
                return true;
            }
            if (newline < 0)
            {
                break;
            }
            rest = rest[(newline + 1)..];
        }

        line = default;
        return false;
    }

    private static string? RunProcess(string filename, string args)
    {
        try
        {
            using var proc = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = filename,
                    Arguments = args,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                }
            };
            proc.Start();
            var output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit(1000);
            return proc.ExitCode == 0 ? output : null;
        }
        catch
        {
            return null;
        }
    }
}
