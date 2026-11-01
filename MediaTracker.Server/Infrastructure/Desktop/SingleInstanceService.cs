using System.ComponentModel;
using System.Runtime.InteropServices;
using MediaTracker.Server.Common.Cli;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Guarantees one Tsundoku server per listening port. A second launch fails to take the
/// instance lock, asks the running instance to surface its UI and exits immediately — the
/// same behavior the Tauri single-instance plugin used to provide.
///
/// Lock mechanisms are per-OS because .NET named Mutexes are NOT machine-wide under
/// NativeAOT on Linux (two processes both "acquire"): Linux uses flock(2) on a lock file,
/// Windows keeps a Win32 named Mutex. Both release automatically when the process dies.
/// </summary>
public static class SingleInstanceService
{
    /// <summary>Rooted for the process lifetime; releasing early would defeat the lock.</summary>
    private static IDisposable? _instanceLock;

    /// <summary>
    /// Returns true when this process may continue starting (lock acquired). Exits the
    /// process with code 0 when an instance is already serving the same port. Pure utility
    /// runs (--migrate-only) and containers are never blocked: Docker gives every container
    /// its own /tmp and PID space, so the lock would be process-local anyway — and the
    /// WebApplicationFactory test suite runs several servers per process under that flag.
    /// </summary>
    public static bool EnsureSingleInstance(CommandLineOptions options)
    {
        if (options.MigrateOnly || CommandLineOptions.IsRunningInContainer)
        {
            return true;
        }

        var port = options.EffectivePort;
        _instanceLock = OperatingSystem.IsWindows()
            ? TryAcquireWindowsLock(port)
            : TryAcquireLinuxLock(port);

        if (_instanceLock is not null)
        {
            return true;
        }

        ActivateUiAndExit(port);
        return false; // unreachable
    }

    /// <summary>Win32 named mutex: reliable under CoreCLR and NativeAOT on Windows.</summary>
    private static IDisposable? TryAcquireWindowsLock(int port)
    {
        var mutex = new Mutex(initiallyOwned: true, $"Tsundoku_SingleInstance_Mutex_{port}", out var createdNew);
        if (createdNew)
        {
            return mutex;
        }

        mutex.Dispose();
        return null;
    }

    /// <summary>advisory flock(LOCK_EX | LOCK_NB) on a per-user, per-port lock file.</summary>
    private static IDisposable? TryAcquireLinuxLock(int port)
    {
        var lockPath = Path.Combine(
            Path.GetTempPath(),
            $"Tsundoku_{Environment.UserName}_{port}.instance.lock");

        FileStream stream;
        try
        {
            stream = new FileStream(
                lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite);
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Instance lock file {Path} is not usable", lockPath);
            return null;
        }

        if (LinuxFlock.TryLockExclusive(stream) is false)
        {
            stream.Dispose();
            return null;
        }

        return stream;
    }

    /// <summary>
    /// Second launch while the server owns the port: surface the UI in this user's
    /// graphical session and exit cleanly with code 0. No errors are printed — a busy
    /// port is a normal situation, not a failure.
    /// </summary>
    private static void ActivateUiAndExit(int port)
    {
        Console.WriteLine($"[Tsundoku] Сервер уже запущен на порту {port}. Открываем интерфейс...");

        // Exactly one launch: Chromium with the same profile deduplicates into the
        // existing app process, so this focuses/opens a single window. Pinging
        // /api/system/open-ui as well would open a second one.
        BrowserLauncher.OpenUrl($"http://127.0.0.1:{port}");
        Environment.Exit(0);
    }
}

/// <summary>Thin flock(2) wrapper; flock is advisory but honored across all processes.</summary>
internal static class LinuxFlock
{
    private const int LockEx = 2;
    private const int LockNb = 4;

    [DllImport("libc", SetLastError = true)]
    private static extern int flock(int fd, int operation);

    /// <summary>true = locked, false = held by another process, null = flock unavailable.</summary>
    public static bool? TryLockExclusive(FileStream stream)
    {
        var fd = (int)stream.SafeFileHandle.DangerousGetHandle();
        var result = flock(fd, LockEx | LockNb);
        if (result == 0)
        {
            return true;
        }

        var error = new Win32Exception(); // wraps errno after the failed libc call
        if (error.NativeErrorCode is 11 /* EAGAIN */ or 35 /* EWOULDBLOCK (same value on x86-64) */)
        {
            return false;
        }

        Serilog.Log.Warning("flock failed with errno {Errno} — instance lock degraded", error.NativeErrorCode);
        return null;
    }
}
