using System.Runtime.InteropServices;
using System.Text;

namespace MediaTracker.Server.Infrastructure.Logging;

/// <summary>
/// The app is built as WinExe, so a console started by the user is not attached by default and
/// stdout can be lost. Re-attaching to the parent console keeps --help visible from cmd/PowerShell.
/// </summary>
internal static partial class ConsoleOutput
{
    private const int AttachParentProcess = -1;

    public static void Attach()
    {
        if (!OperatingSystem.IsWindows() || Console.IsOutputRedirected)
        {
            return;
        }

        AttachConsole(AttachParentProcess);
        Console.SetOut(
            new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false))
            {
                AutoFlush = true,
            }
        );
        Console.SetError(
            new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false))
            {
                AutoFlush = true,
            }
        );
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AttachConsole(int processId);
}
