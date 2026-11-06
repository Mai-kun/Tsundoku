using System.Diagnostics;
using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.Jobs;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Offline;

public sealed class ImdbBasicsImporter
{
    public const int BatchSize = 50_000;
    public const int ProgressIntervalLines = 100_000;

    public async Task<int> ImportDumpAsync(
        string dumpFilePath,
        string targetDatabasePath,
        IProgress<JobProgressDto>? progress = null,
        CancellationToken ct = default)
    {
        if (!File.Exists(dumpFilePath))
        {
            throw new FileNotFoundException($"IMDb dump file not found at '{dumpFilePath}'.", dumpFilePath);
        }

        var targetDir = Path.GetDirectoryName(Path.GetFullPath(targetDatabasePath))!;
        Directory.CreateDirectory(targetDir);

        var tempDbPath = targetDatabasePath + ".import.tmp";
        if (File.Exists(tempDbPath))
        {
            try { File.Delete(tempDbPath); } catch { }
        }

        var totalLines = 0L;
        var totalImported = 0;
        var batchCount = 0;

        try
        {
            await using (var conn = new SqliteConnection($"Data Source={tempDbPath};"))
            {
                await conn.OpenAsync(ct);

                await ExecuteNonQueryAsync(conn, @"
                    PRAGMA synchronous = OFF;
                    PRAGMA journal_mode = MEMORY;
                    PRAGMA temp_store = MEMORY;
                    PRAGMA cache_size = -64000;
                ", ct);

                await ExecuteNonQueryAsync(conn, OfflineDatabaseManager.CreateTableSql, ct);

                await using var stream = new FileStream(dumpFilePath, FileMode.Open, FileAccess.Read, FileShare.Read, 1024 * 1024);
                using var reader = new StreamReader(stream);
                var totalBytes = stream.Length;

                var tx = conn.BeginTransaction();
                await using var cmd = conn.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = @"
                    INSERT INTO OfflineMedia (Id, Title, OriginalTitle, Type, Year, Genres, ExternalSource, ExternalId, ExtraDataJson)
                    VALUES (@Id, @Title, @OriginalTitle, @Type, @Year, @Genres, @ExternalSource, @ExternalId, @ExtraDataJson);
                ";

                var pId = cmd.Parameters.Add("@Id", SqliteType.Text);
                var pTitle = cmd.Parameters.Add("@Title", SqliteType.Text);
                var pOriginalTitle = cmd.Parameters.Add("@OriginalTitle", SqliteType.Text);
                var pType = cmd.Parameters.Add("@Type", SqliteType.Text);
                var pYear = cmd.Parameters.Add("@Year", SqliteType.Integer);
                var pGenres = cmd.Parameters.Add("@Genres", SqliteType.Text);
                var pExternalSource = cmd.Parameters.Add("@ExternalSource", SqliteType.Text);
                var pExternalId = cmd.Parameters.Add("@ExternalId", SqliteType.Text);
                var pExtraDataJson = cmd.Parameters.Add("@ExtraDataJson", SqliteType.Text);

                string? line;
                while ((line = await reader.ReadLineAsync(ct)) != null)
                {
                    totalLines++;

                    if (totalLines % ProgressIntervalLines == 0 && progress != null)
                    {
                        var pct = totalBytes > 0 ? (int)Math.Clamp(stream.Position * 100 / totalBytes, 0, 99) : 0;
                        progress.Report(new JobProgressDto(
                            Guid.Empty,
                            null,
                            string.Empty,
                            pct,
                            $"Обработано {totalLines:N0} строк...",
                            JobStatus.Running,
                            DateTime.MinValue,
                            null));
                    }

                    ReadOnlySpan<char> span = line.AsSpan();
                    if (span.IsEmpty) continue;

                    // Parse columns: tconst, titleType, primaryTitle, originalTitle, isAdult, startYear, endYear, runtimeMinutes, genres
                    int col = 0;
                    ReadOnlySpan<char> tconst = default;
                    ReadOnlySpan<char> titleType = default;
                    ReadOnlySpan<char> primaryTitle = default;
                    ReadOnlySpan<char> originalTitle = default;
                    ReadOnlySpan<char> isAdult = default;
                    ReadOnlySpan<char> startYear = default;
                    ReadOnlySpan<char> endYear = default;
                    ReadOnlySpan<char> runtimeMinutes = default;
                    ReadOnlySpan<char> genres = default;

                    while (!span.IsEmpty || col <= 8)
                    {
                        int tab = span.IndexOf('\t');
                        ReadOnlySpan<char> field = tab >= 0 ? span.Slice(0, tab) : span;
                        span = tab >= 0 ? span.Slice(tab + 1) : ReadOnlySpan<char>.Empty;

                        switch (col)
                        {
                            case 0: tconst = field; break;
                            case 1: titleType = field; break;
                            case 2: primaryTitle = field; break;
                            case 3: originalTitle = field; break;
                            case 4: isAdult = field; break;
                            case 5: startYear = field; break;
                            case 6: endYear = field; break;
                            case 7: runtimeMinutes = field; break;
                            case 8: genres = field; break;
                        }

                        col++;
                        if (tab < 0) break;
                    }

                    // Header line check
                    if (tconst.SequenceEqual("tconst")) continue;

                    // Adult content check
                    if (isAdult.SequenceEqual("1")) continue;

                    // Type filter: only movie, tvSeries, tvMiniSeries, tvMovie
                    string mediaType;
                    if (titleType.SequenceEqual("movie") || titleType.SequenceEqual("tvMovie"))
                    {
                        mediaType = "movie";
                    }
                    else if (titleType.SequenceEqual("tvSeries") || titleType.SequenceEqual("tvMiniSeries"))
                    {
                        mediaType = "tvshow";
                    }
                    else
                    {
                        continue;
                    }

                    if (primaryTitle.IsEmpty || primaryTitle.SequenceEqual(@"\N")) continue;

                    string extId = tconst.ToString();
                    string titleStr = primaryTitle.ToString();
                    string? origTitleStr = originalTitle.IsEmpty || originalTitle.SequenceEqual(@"\N") || originalTitle.SequenceEqual(primaryTitle)
                        ? null
                        : originalTitle.ToString();

                    int? yearVal = null;
                    if (!startYear.IsEmpty && !startYear.SequenceEqual(@"\N") && int.TryParse(startYear, out var y))
                    {
                        yearVal = y;
                    }

                    string? genresStr = genres.IsEmpty || genres.SequenceEqual(@"\N") ? null : genres.ToString();

                    int? runtimeVal = null;
                    if (!runtimeMinutes.IsEmpty && !runtimeMinutes.SequenceEqual(@"\N") && int.TryParse(runtimeMinutes, out var rt))
                    {
                        runtimeVal = rt;
                    }

                    string? extraJson = null;
                    if (runtimeVal.HasValue || !titleType.SequenceEqual("movie"))
                    {
                        var extra = new OfflineExtraData
                        {
                            Format = titleType.ToString(),
                            RuntimeMinutes = runtimeVal,
                            ImdbId = extId
                        };
                        extraJson = JsonSerializer.Serialize(extra, OfflineExtraData.SerializerOptions);
                    }

                    pId.Value = $"imdb:{extId}";
                    pTitle.Value = titleStr;
                    pOriginalTitle.Value = (object?)origTitleStr ?? DBNull.Value;
                    pType.Value = mediaType;
                    pYear.Value = (object?)yearVal ?? DBNull.Value;
                    pGenres.Value = (object?)genresStr ?? DBNull.Value;
                    pExternalSource.Value = "imdb";
                    pExternalId.Value = extId;
                    pExtraDataJson.Value = (object?)extraJson ?? DBNull.Value;

                    await cmd.ExecuteNonQueryAsync(ct);

                    totalImported++;
                    batchCount++;

                    if (batchCount >= BatchSize)
                    {
                        await tx.CommitAsync(ct);
                        await tx.DisposeAsync();
                        tx = conn.BeginTransaction();
                        cmd.Transaction = tx;
                        batchCount = 0;
                    }
                }

                if (batchCount > 0)
                {
                    await tx.CommitAsync(ct);
                }

                // Strictly build indexes AFTER all rows are inserted
                await ExecuteNonQueryAsync(conn, OfflineDatabaseManager.CreateIndexesSql, ct);
            }

            if (File.Exists(targetDatabasePath))
            {
                File.Delete(targetDatabasePath);
            }
            File.Move(tempDbPath, targetDatabasePath);

            progress?.Report(new JobProgressDto(
                Guid.Empty,
                null,
                string.Empty,
                100,
                $"Индексация завершена: добавлено {totalImported:N0} тайтлов",
                JobStatus.Completed,
                DateTime.MinValue,
                null));

            return totalImported;
        }
        finally
        {
            if (File.Exists(tempDbPath))
            {
                try { File.Delete(tempDbPath); } catch { }
            }
        }
    }

    private static async Task ExecuteNonQueryAsync(SqliteConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
