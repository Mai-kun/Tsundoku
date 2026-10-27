using System.Diagnostics;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using MediaTracker.Server.Infrastructure.Persistence;
using BenchmarkDotNet.Running;

namespace MediaTracker.Benchmarks;

public static class Program
{
    public static async Task Main(string[] args)
    {
        if (args.Length >= 3 && args[0] == "--seed-db")
        {
            var count = int.Parse(args[1]);
            var dbPath = args[2];
            await SeedDb(count, dbPath);
            return;
        }

        if (args.Length == 0)
        {
            args = ["--filter", "*"];
        }

        BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
    }

    private static async Task SeedDb(int count, string dbPath)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite($"Data Source={dbPath}")
            .Options;
            
        using var db = new AppDbContext(options);
        await db.Database.EnsureDeletedAsync();
        await db.Database.EnsureCreatedAsync();

        using var conn = new SqliteConnection($"Data Source={dbPath}");
        await conn.OpenAsync();
        
        var sw = Stopwatch.StartNew();
        var transaction = (SqliteTransaction)await conn.BeginTransactionAsync();
        
        var command = conn.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "INSERT INTO MediaItems (Id, Title, Status, CreatedAt, UpdatedAt, MediaType, SyncStatus, AutoRefreshIntervalDays, IsCustomEdited) VALUES (@id, @title, @status, @createdAt, @updatedAt, @disc, @sync, @refresh, @custom)";
        
        var idParam = command.CreateParameter(); idParam.ParameterName = "@id"; command.Parameters.Add(idParam);
        var titleParam = command.CreateParameter(); titleParam.ParameterName = "@title"; command.Parameters.Add(titleParam);
        var statusParam = command.CreateParameter(); statusParam.ParameterName = "@status"; command.Parameters.Add(statusParam);
        var createdAtParam = command.CreateParameter(); createdAtParam.ParameterName = "@createdAt"; command.Parameters.Add(createdAtParam);
        var updatedAtParam = command.CreateParameter(); updatedAtParam.ParameterName = "@updatedAt"; command.Parameters.Add(updatedAtParam);
        var discParam = command.CreateParameter(); discParam.ParameterName = "@disc"; command.Parameters.Add(discParam);
        var syncParam = command.CreateParameter(); syncParam.ParameterName = "@sync"; command.Parameters.Add(syncParam);
        var refreshParam = command.CreateParameter(); refreshParam.ParameterName = "@refresh"; command.Parameters.Add(refreshParam);
        var customParam = command.CreateParameter(); customParam.ParameterName = "@custom"; command.Parameters.Add(customParam);

        var random = new Random();
        string[] types = ["Game", "Book", "Manga", "Movie", "TvShow"];

        for (int i = 0; i < count; i++)
        {
            idParam.Value = Guid.NewGuid().ToString();
            titleParam.Value = $"{types[i % 5]} Item {i}";
            statusParam.Value = random.Next(0, 5); // 0: Planned, 1: InProgress, 2: Completed, 3: OnHold, 4: Dropped
            createdAtParam.Value = DateTime.UtcNow.AddDays(-random.Next(0, 365 * 5)).ToString("O");
            updatedAtParam.Value = DateTime.UtcNow.ToString("O");
            discParam.Value = types[i % 5];
            syncParam.Value = 0; // SyncStatus.Ready is 0
            refreshParam.Value = 7;
            customParam.Value = 0; // false
            
            await command.ExecuteNonQueryAsync();
            
            if (i > 0 && i % 5000 == 0) {
                await transaction.CommitAsync();
                await transaction.DisposeAsync();
                transaction = (SqliteTransaction)await conn.BeginTransactionAsync();
                command.Transaction = transaction;
            }
        }
        await transaction.CommitAsync();
        sw.Stop();
        Console.WriteLine($"[Seed] Successfully generated {count} items in {sw.ElapsedMilliseconds} ms.");
    }
}
