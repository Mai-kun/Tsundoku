using System.Text.Json;
using System.Text.RegularExpressions;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.Jobs;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Offline;

public sealed partial class OpenVgdbImporter
{
    [GeneratedRegex(@"\b(19\d\d|20\d\d)\b")]
    private static partial Regex YearRegex();

    public async Task<int> ImportAsync(
        string sourcePath,
        string targetDatabasePath,
        IProgress<JobProgressDto>? progress = null,
        CancellationToken ct = default)
    {
        var resolvedSource = ResolveSourceDbFile(sourcePath);
        if (resolvedSource == null || !File.Exists(resolvedSource))
        {
            throw new FileNotFoundException($"OpenVGDB source database not found at '{sourcePath}'.", sourcePath);
        }

        var targetDir = Path.GetDirectoryName(Path.GetFullPath(targetDatabasePath))!;
        Directory.CreateDirectory(targetDir);

        var tempDbPath = targetDatabasePath + ".import.tmp";
        if (File.Exists(tempDbPath))
        {
            try { File.Delete(tempDbPath); } catch { }
        }

        var totalImported = 0;

        try
        {
            await using var srcConn = new SqliteConnection($"Data Source={resolvedSource};Mode=ReadOnly;");
            await srcConn.OpenAsync(ct);

            // Read count first for realistic progress reporting
            var totalCount = 0;
            try
            {
                await using var countCmd = srcConn.CreateCommand();
                countCmd.CommandText = "SELECT COUNT(1) FROM RELEASES WHERE releaseTitleName IS NOT NULL AND TRIM(releaseTitleName) != '';";
                totalCount = Convert.ToInt32(await countCmd.ExecuteScalarAsync(ct));
            }
            catch
            {
                totalCount = 50_000;
            }

            await using (var targetConn = new SqliteConnection($"Data Source={tempDbPath};"))
            {
                await targetConn.OpenAsync(ct);

                await ExecuteNonQueryAsync(targetConn, @"
                    PRAGMA synchronous = OFF;
                    PRAGMA journal_mode = MEMORY;
                    PRAGMA temp_store = MEMORY;
                    PRAGMA cache_size = -64000;
                ", ct);

                await ExecuteNonQueryAsync(targetConn, OfflineDatabaseManager.CreateTableSql, ct);

                await using var readCmd = srcConn.CreateCommand();
                // Group by title and system to combine multi-region/ROM dumps into unique game-per-platform records
                readCmd.CommandText = @"
                    SELECT
                        MIN(r.releaseID) AS releaseID,
                        r.releaseTitleName,
                        COALESCE(s.systemName, r.TEMPsystemName) AS systemName,
                        COALESCE(s.systemShortName, r.TEMPsystemShortName) AS systemShortName,
                        MAX(r.releaseDate) AS releaseDate,
                        MAX(r.releaseGenre) AS releaseGenre,
                        MAX(r.releaseDeveloper) AS releaseDeveloper,
                        MAX(r.releasePublisher) AS releasePublisher,
                        MAX(r.releaseCoverFront) AS releaseCoverFront,
                        MAX(r.releaseDescription) AS releaseDescription
                    FROM RELEASES r
                    LEFT JOIN ROMs rm ON r.romID = rm.romID
                    LEFT JOIN SYSTEMS s ON rm.systemID = s.systemID
                    WHERE r.releaseTitleName IS NOT NULL AND TRIM(r.releaseTitleName) != ''
                    GROUP BY r.releaseTitleName, COALESCE(s.systemShortName, r.TEMPsystemShortName);
                ";

                SqliteDataReader reader;
                try
                {
                    reader = await readCmd.ExecuteReaderAsync(ct);
                }
                catch
                {
                    // Fallback query if ROMs or SYSTEMS table is missing
                    readCmd.CommandText = @"
                        SELECT
                            MIN(r.releaseID) AS releaseID,
                            r.releaseTitleName,
                            r.TEMPsystemName AS systemName,
                            r.TEMPsystemShortName AS systemShortName,
                            MAX(r.releaseDate) AS releaseDate,
                            MAX(r.releaseGenre) AS releaseGenre,
                            MAX(r.releaseDeveloper) AS releaseDeveloper,
                            MAX(r.releasePublisher) AS releasePublisher,
                            MAX(r.releaseCoverFront) AS releaseCoverFront,
                            MAX(r.releaseDescription) AS releaseDescription
                        FROM RELEASES r
                        WHERE r.releaseTitleName IS NOT NULL AND TRIM(r.releaseTitleName) != ''
                        GROUP BY r.releaseTitleName, r.TEMPsystemShortName;
                    ";
                    reader = await readCmd.ExecuteReaderAsync(ct);
                }

                await using (reader)
                {
                    var tx = targetConn.BeginTransaction();
                    await using var insertCmd = targetConn.CreateCommand();
                    insertCmd.Transaction = tx;
                    insertCmd.CommandText = @"
                        INSERT INTO OfflineMedia (Id, Title, OriginalTitle, Type, Year, Genres, ExternalSource, ExternalId, ExtraDataJson)
                        VALUES (@Id, @Title, @OriginalTitle, @Type, @Year, @Genres, @ExternalSource, @ExternalId, @ExtraDataJson);
                    ";

                    var pId = insertCmd.Parameters.Add("@Id", SqliteType.Text);
                    var pTitle = insertCmd.Parameters.Add("@Title", SqliteType.Text);
                    var pOriginalTitle = insertCmd.Parameters.Add("@OriginalTitle", SqliteType.Text);
                    var pType = insertCmd.Parameters.Add("@Type", SqliteType.Text);
                    var pYear = insertCmd.Parameters.Add("@Year", SqliteType.Integer);
                    var pGenres = insertCmd.Parameters.Add("@Genres", SqliteType.Text);
                    var pExternalSource = insertCmd.Parameters.Add("@ExternalSource", SqliteType.Text);
                    var pExternalId = insertCmd.Parameters.Add("@ExternalId", SqliteType.Text);
                    var pExtraDataJson = insertCmd.Parameters.Add("@ExtraDataJson", SqliteType.Text);

                    var batchCount = 0;

                    while (await reader.ReadAsync(ct))
                    {
                        var releaseId = reader.GetInt64(0);
                        var title = reader.GetString(1);
                        var systemName = reader.IsDBNull(2) ? null : reader.GetString(2);
                        var systemShortName = reader.IsDBNull(3) ? null : reader.GetString(3);
                        var releaseDate = reader.IsDBNull(4) ? null : reader.GetString(4);
                        var genre = reader.IsDBNull(5) ? null : reader.GetString(5);
                        var developer = reader.IsDBNull(6) ? null : reader.GetString(6);
                        var publisher = reader.IsDBNull(7) ? null : reader.GetString(7);
                        var coverFront = reader.IsDBNull(8) ? null : reader.GetString(8);
                        var description = reader.IsDBNull(9) ? null : reader.GetString(9);

                        int? year = null;
                        if (!string.IsNullOrWhiteSpace(releaseDate))
                        {
                            var match = YearRegex().Match(releaseDate);
                            if (match.Success && int.TryParse(match.Value, out var y))
                            {
                                year = y;
                            }
                        }

                        var platform = systemName ?? systemShortName;
                        var extra = new OfflineExtraData
                        {
                            CoverUrl = coverFront,
                            Description = description,
                            Developer = developer,
                            Publisher = publisher,
                            Platform = platform
                        };

                        var extIdStr = releaseId.ToString();
                        pId.Value = $"openvgdb:{extIdStr}";
                        pTitle.Value = title;
                        pOriginalTitle.Value = DBNull.Value;
                        pType.Value = "game";
                        pYear.Value = (object?)year ?? DBNull.Value;
                        pGenres.Value = (object?)genre ?? DBNull.Value;
                        pExternalSource.Value = "openvgdb";
                        pExternalId.Value = extIdStr;
                        pExtraDataJson.Value = JsonSerializer.Serialize(extra, AppJsonSerializerContext.Default.OfflineExtraData);

                        await insertCmd.ExecuteNonQueryAsync(ct);

                        totalImported++;
                        batchCount++;

                        if (totalImported % 5_000 == 0 && progress != null)
                        {
                            var pct = totalCount > 0 ? (int)Math.Clamp(totalImported * 100 / totalCount, 0, 99) : 0;
                            progress.Report(new JobProgressDto(
                                Guid.Empty,
                                null,
                                string.Empty,
                                pct,
                                $"Обработано {totalImported:N0} игр...",
                                JobStatus.Running,
                                DateTime.MinValue,
                                null));
                        }

                        if (batchCount >= 10_000)
                        {
                            await tx.CommitAsync(ct);
                            await tx.DisposeAsync();
                            tx = targetConn.BeginTransaction();
                            insertCmd.Transaction = tx;
                            batchCount = 0;
                        }
                    }

                    if (batchCount > 0)
                    {
                        await tx.CommitAsync(ct);
                    }
                }

                // Strictly build indexes AFTER all rows are inserted
                await ExecuteNonQueryAsync(targetConn, OfflineDatabaseManager.CreateIndexesSql, ct);
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

    private static string? ResolveSourceDbFile(string path)
    {
        if (File.Exists(path)) return path;

        if (Directory.Exists(path))
        {
            var sqlite = Path.Combine(path, "openvgdb.sqlite");
            if (File.Exists(sqlite)) return sqlite;

            var db = Path.Combine(path, "openvgdb.db");
            if (File.Exists(db)) return db;

            return Directory.EnumerateFiles(path, "*.sqlite", SearchOption.TopDirectoryOnly)
                .Concat(Directory.EnumerateFiles(path, "*.db", SearchOption.TopDirectoryOnly))
                .FirstOrDefault(f => !Path.GetFileName(f).StartsWith('.'));
        }

        return null;
    }

    private static async Task ExecuteNonQueryAsync(SqliteConnection conn, string sql, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
