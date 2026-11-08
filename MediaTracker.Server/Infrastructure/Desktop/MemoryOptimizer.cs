using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Returns physical memory to the operating system once the desktop app goes idle or the user
/// closes the app window. Four layers, cheapest first: drop the in-process caches, flush the
/// SQLite page caches, compact the managed heap, and finally hand the freed pages back to the
/// kernel (malloc_trim on glibc, an empty working set on Windows).
/// </summary>
public static partial class MemoryOptimizer
{
    // Константы glibc (mallopt.h).
    private const int MTrimThreshold = -1;
    private const int MMmapThreshold = -3;
    private const int MArenaMax = -8;

    [LibraryImport("libc", EntryPoint = "malloc_trim", SetLastError = true)]
    private static partial int MallocTrim(nuint pad);

    [LibraryImport("libc", EntryPoint = "mallopt", SetLastError = true)]
    private static partial int Mallopt(int param, int value);

    [LibraryImport("kernel32.dll", EntryPoint = "SetProcessWorkingSetSize", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetProcessWorkingSetSize(IntPtr process, nuint minSize, nuint maxSize);

    [LibraryImport("kernel32.dll", EntryPoint = "GetCurrentProcess")]
    private static partial IntPtr GetCurrentProcess();

    /// <summary>A snapshot of the process memory the trim reports on.</summary>
    public sealed record MemorySnapshot(double WorkingSetMb, double GcHeapMb);

    /// <summary>Response of POST /api/system/trim-memory (AOT needs a registered DTO shape, not an anonymous type).</summary>
    public sealed record TrimMemoryResponse(MemorySnapshot Before, MemorySnapshot After, double FreedWorkingSetMb, double FreedGcHeapMb);

    public static MemorySnapshot TakeSnapshot() =>
        new(
            Math.Round(Process.GetCurrentProcess().WorkingSet64 / 1_048_576.0, 1),
            Math.Round(GC.GetTotalMemory(forceFullCollection: false) / 1_048_576.0, 1));

    /// <summary>
    /// Реальное управление аллокатором glibc через P/Invoke mallopt. Переменные окружения
    /// MALLOC_* игнорируются glibc, если заданы внутри уже запущенного C# процесса (прочитать их
    /// можно только на старте самого libc), поэтому единственный надёжный путь — прямой вызов
    /// mallopt до того, как процесс породит первые потоки.
    /// </summary>
    public static void ConfigureGlibcAllocators()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }

        try
        {
            // Ограничиваем количество арен до одной: каждая дополнительная арена glibc — это
            // до 64 МБ виртуальной памяти, которую malloc_trim не может слить обратно.
            Mallopt(MArenaMax, 1);
            // Агрессивный порог возврата памяти ядру: свободные верхушки куч отдаются уже
            // после 64 КБ вместо дефолтных мегабайтов.
            Mallopt(MTrimThreshold, 65536);
            Mallopt(MMmapThreshold, 65536);
        }
        catch
        {
            // Нет libc (Windows) или старый musl — живём с дефолтными настройками аллокатора.
        }
    }

    public static void TrimMemory(IMemoryCache? cache = null, string? sqliteConnectionString = null)
    {
        // 1. Сброс кэшей памяти приложения.
        if (cache is MemoryCache mc)
        {
            mc.Compact(1.0);
        }

        // 2. Сброс кэша SQLite: сначала выгрузить страницы pager'а из памяти открытых баз
        //    (shrink_memory), затем закрыть пулы целиком — иначе соединения продолжают держать
        //    страницы и mmap-окна базы в RSS после часа простоя.
        try
        {
            if (!string.IsNullOrWhiteSpace(sqliteConnectionString))
            {
                using var connection = new SqliteConnection(sqliteConnectionString);
                connection.Open();
                using var command = connection.CreateCommand();
                command.CommandText = "PRAGMA shrink_memory;";
                command.ExecuteNonQuery();
            }

            SqliteConnection.ClearAllPools();
        }
        catch
        {
            // База ещё не создана или пулы уже мертвы — чистить нечего.
        }

        // 3. Агрессивная сборка мусора .NET с компактизацией кучи: две проходки нужны, чтобы
        //    объекты, дожившие до второй генерации после первой, тоже освободились и куча
        //    действительно сжалась, а не осталась фрагментированной.
        GC.Collect(2, GCCollectionMode.Aggressive, blocking: true, compacting: true);
        GC.WaitForPendingFinalizers();
        GC.Collect(2, GCCollectionMode.Aggressive, blocking: true, compacting: true);

        // 4. Возврат физических страниц ядру операционной системы.
        try
        {
            if (OperatingSystem.IsLinux())
            {
                MallocTrim(0);
            }
            else if (OperatingSystem.IsWindows())
            {
                SetProcessWorkingSetSize(GetCurrentProcess(), unchecked((nuint)(-1)), unchecked((nuint)(-1)));
            }
        }
        catch
        {
            // На некоторых libc (musl) malloc_trim отсутствует — выгрузка страниц тогда
            // происходит сама по мере освобождения куч.
        }
    }
}
