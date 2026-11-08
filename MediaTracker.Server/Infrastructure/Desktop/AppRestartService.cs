using System.Diagnostics;
using System.Runtime.InteropServices;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Infrastructure.Desktop;

public static class AppRestartService
{
    private static readonly List<string> AdditionalRestartArgs = [];

    public static bool IsRestartScheduled { get; private set; }

    public static void ScheduleRestart(params string[] extraArgs)
    {
        IsRestartScheduled = true;
        if (extraArgs is { Length: > 0 })
        {
            foreach (var arg in extraArgs)
            {
                if (!AdditionalRestartArgs.Contains(arg, StringComparer.OrdinalIgnoreCase))
                {
                    AdditionalRestartArgs.Add(arg);
                }
            }
        }
    }

    /// <summary>
    /// Перезапуск с сохранением уже открытого окна Chromium: ApplicationStopping не закрывает
    /// окно, новый процесс стартует свернутым (--no-browser) и усыновляет живое окно по PID
    /// (--adopt-browser-pid) — иначе после execv терялось managed-состояние BrowserLauncher:
    /// закрытие окна пользователем переставало работать, а финальный выход из трея оставлял
    /// бы окно висеть на мёртвом порту. Если окна нет, новый процесс открывает его сам.
    /// </summary>
    public static void ScheduleRestartKeepingWindow()
    {
        var windowPid = BrowserLauncher.GetWindowPidForHandoff();
        if (windowPid > 0)
        {
            // Значение отдельным токеном: CLI-парсер матчит метки case по точному равенству,
            // и форма --adopt-browser-pid=123 не доходит до своего case (Unknown option).
            ScheduleRestart("--no-browser", "--adopt-browser-pid", windowPid.ToString());
        }
        else
        {
            ScheduleRestart();
        }
    }

    public static void ExecuteRestart()
    {
        var exePath = AppPaths.GetExecutablePath();
        var rawArgs = Environment.GetCommandLineArgs().Skip(1);
        var argsList = new List<string>(rawArgs);
        foreach (var extra in AdditionalRestartArgs)
        {
            if (!argsList.Contains(extra, StringComparer.OrdinalIgnoreCase))
            {
                argsList.Add(extra);
            }
        }
        var args = argsList.ToArray();

        if (OperatingSystem.IsWindows())
        {
            var escapedArgs = string.Join(" ", args.Select(a => $"\"{a.Replace("\"", "\\\"")}\""));
            var psi = new ProcessStartInfo("cmd.exe", $"/c timeout /t 1 /nobreak >nul & start \"\" \"{exePath}\" {escapedArgs}")
            {
                CreateNoWindow = true,
                UseShellExecute = false
            };
            Process.Start(psi);
            return;
        }

        if (OperatingSystem.IsLinux())
        {
            try
            {
                var execArgs = new List<string> { exePath };
                execArgs.AddRange(args);

                var ptrs = new IntPtr[execArgs.Count + 1];
                for (int i = 0; i < execArgs.Count; i++)
                {
                    ptrs[i] = Marshal.StringToCoTaskMemUTF8(execArgs[i]);
                }
                ptrs[execArgs.Count] = IntPtr.Zero;

                Execv(exePath, ptrs);
            }
            catch (Exception ex)
            {
                Serilog.Log.Error(ex, "execv failed during restart, falling back to Process.Start");
            }
        }

        try
        {
            var psi = new ProcessStartInfo(exePath)
            {
                UseShellExecute = false,
                WorkingDirectory = AppPaths.GetAppDirectory()
            };
            foreach (var arg in args)
            {
                psi.ArgumentList.Add(arg);
            }
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            Serilog.Log.Error(ex, "Failed to restart application");
        }
    }

#pragma warning disable CA2101 // Specify marshaling for P/Invoke string arguments
    [DllImport("libc", SetLastError = true, EntryPoint = "execv", ExactSpelling = true)]
    private static extern int Execv([MarshalAs(UnmanagedType.LPUTF8Str)] string path, IntPtr[] argv);
#pragma warning restore CA2101
}
