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
    [LibraryImport("libc", EntryPoint = "malloc_trim", SetLastError = true)]
    private static partial int MallocTrim(nuint pad);

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

        // 2b. Нативные кэши SkiaSharp: декодированные глифы, шрифты и растровые ресурсы живут
        //     вне managed heap и не видны сборщику мусора.
        try
        {
            SkiaSharp.SKGraphics.PurgeFontCache();
            SkiaSharp.SKGraphics.PurgeResourceCache();
        }
        catch
        {
            // Skia может быть не инициализирована, если обложек ещё не качали.
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
