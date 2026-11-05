using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.GetMediaStats;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Offline;

public sealed class AnimeOfflineDatabaseImporter
{
    public sealed record ImportProgress(int ProcessedCount, long ElapsedMilliseconds);

    public Task<int> ImportDumpAsync(
        string dumpFilePath,
        string targetDatabasePath,
        IProgress<ImportProgress>? legacyProgress,
        CancellationToken ct = default)
    {
        var sw = Stopwatch.StartNew();
        var adapter = legacyProgress == null ? null : new Progress<JobProgressDto>(p =>
        {
            legacyProgress.Report(new ImportProgress(p.ProgressPercent, sw.ElapsedMilliseconds));
        });
        return ImportDumpAsync(dumpFilePath, targetDatabasePath, adapter, ct);
    }

    public async Task<int> ImportDumpAsync(
        string dumpFilePath,
        string targetDatabasePath,
        IProgress<JobProgressDto>? progress = null,
        CancellationToken ct = default)
    {
        if (!File.Exists(dumpFilePath))
        {
            throw new FileNotFoundException($"Offline anime dump file not found at '{dumpFilePath}'.", dumpFilePath);
        }

        var targetDir = Path.GetDirectoryName(Path.GetFullPath(targetDatabasePath))!;
        Directory.CreateDirectory(targetDir);

        var tempDbPath = targetDatabasePath + ".import.tmp";
        if (File.Exists(tempDbPath))
        {
            try { File.Delete(tempDbPath); } catch { }
        }

        long totalBytes;
        using (var s = File.OpenRead(dumpFilePath))
        {
            totalBytes = s.Length;
        }
        var totalCount = 0;
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

                var tx = conn.BeginTransaction();
                await using var insertCmd = conn.CreateCommand();
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

                await foreach (var (entry, streamPosition) in ReadEntriesWithPositionAsync(dumpFilePath, ct))
                {
                    if (string.IsNullOrWhiteSpace(entry.Title)) continue;

                    var normalizedStatus = entry.Status?.ToUpperInvariant() switch
                    {
                        "FINISHED" => "Completed",
                        "ONGOING" => "Airing",
                        "UPCOMING" => "Planned",
                        _ => entry.Status
                    };

                    var extra = new OfflineExtraData
                    {
                        CoverUrl = entry.Picture ?? entry.Thumbnail,
                        Format = entry.Type,
                        TotalCount = entry.Episodes,
                        ReleaseStatus = normalizedStatus,
                        Synonyms = entry.Synonyms,
                        Tags = entry.Tags,
                        AnilistId = entry.AnilistId,
                        MalId = entry.MalId,
                        KitsuId = entry.KitsuId,
                        AnidbId = entry.AnidbId
                    };
                    var extId = entry.AnilistId ?? entry.MalId ?? entry.KitsuId ?? entry.AnidbId ?? (totalCount + 1).ToString();
                    var id = entry.AnilistId != null ? $"anilist:{entry.AnilistId}"
                           : entry.MalId != null ? $"mal:{entry.MalId}"
                           : $"anime:{totalCount + 1}";

                    // The slash-joined synonyms blob used to land in OriginalTitle and flow on
                    // into RomajiTitle during enrichment, burying the romanized name under a
                    // giant "a / b / c" string. Keep only the first clean Latin synonym — that
                    // is what a romaji/original title is supposed to be.
                    string? originalTitle = FirstLatinSynonym(entry.Synonyms);

                    // The dump's tag list mixes real genres with hundreds of story tropes
                    // ("aim for the top", "middle school", "lingerie"). The dictionary decides:
                    // primary genres (max 6, canonical English) go into the Genres column, every
                    // other descriptive trope is preserved in ExtraDataJson.Tags.
                    var validGenres = entry.Tags is { Count: > 0 }
                        ? entry.Tags
                            .Where(GenreNormalizer.IsPrimaryGenre)
                            .Select(GenreNormalizer.Normalize)
                            .Distinct(StringComparer.OrdinalIgnoreCase)
                            .Take(6)
                            .ToList()
                        : [];
                    var extraTags = entry.Tags is { Count: > 0 }
                        ? entry.Tags
                            .Where(tag => !GenreNormalizer.IsPrimaryGenre(tag))
                            .Distinct(StringComparer.OrdinalIgnoreCase)
                            .ToList()
                        : null;
                    extra.Tags = extraTags is { Count: > 0 } ? extraTags : null;
                    string? genresStr = validGenres.Count > 0 ? string.Join(", ", validGenres) : null;

                    pId.Value = id;
                    pTitle.Value = entry.Title;
                    pOriginalTitle.Value = (object?)originalTitle ?? DBNull.Value;
                    pType.Value = "anime";
                    pYear.Value = (object?)entry.Year ?? DBNull.Value;
                    pGenres.Value = (object?)genresStr ?? DBNull.Value;
                    pExternalSource.Value = "offline_anime";
                    pExternalId.Value = extId;
                    pExtraDataJson.Value = JsonSerializer.Serialize(extra, AppJsonSerializerContext.Default.OfflineExtraData);

                    await insertCmd.ExecuteNonQueryAsync(ct);

                    totalCount++;
                    batchCount++;

                    if (totalCount % 5_000 == 0 && progress != null)
                    {
                        var pct = totalBytes > 0 ? (int)Math.Clamp(streamPosition * 100 / totalBytes, 0, 99) : 0;
                        progress.Report(new JobProgressDto(
                            Guid.Empty,
                            null,
                            string.Empty,
                            pct,
                            $"Обработано {totalCount:N0} аниме...",
                            JobStatus.Running,
                            DateTime.MinValue,
                            null));
                    }

                    if (batchCount >= 10_000)
                    {
                        await tx.CommitAsync(ct);
                        await tx.DisposeAsync();
                        tx = conn.BeginTransaction();
                        insertCmd.Transaction = tx;
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
                $"Индексация завершена: добавлено {totalCount:N0} тайтлов",
                JobStatus.Completed,
                DateTime.MinValue,
                null));

            return totalCount;
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

    private static async IAsyncEnumerable<(ParsedOfflineEntry Entry, long Position)> ReadEntriesWithPositionAsync(
        string dumpPath,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        await using var stream = File.OpenRead(dumpPath);
        using var reader = new StreamReader(stream);

        var firstLine = await reader.ReadLineAsync(ct);
        if (firstLine == null) yield break;

        var trimmedFirst = firstLine.TrimStart();
        if (trimmedFirst.StartsWith("{\"license", StringComparison.OrdinalIgnoreCase) ||
            trimmedFirst.StartsWith("{\"repository", StringComparison.OrdinalIgnoreCase) ||
            trimmedFirst.StartsWith("{\"data\"", StringComparison.OrdinalIgnoreCase))
        {
            stream.Position = 0;
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            if (doc.RootElement.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in data.EnumerateArray())
                {
                    var entry = ParseEntry(item);
                    if (entry != null) yield return (entry, stream.Position);
                }
            }
        }
        else
        {
            var line = firstLine;
            do
            {
                if (!string.IsNullOrWhiteSpace(line))
                {
                    ParsedOfflineEntry? entry = null;
                    try
                    {
                        using var doc = JsonDocument.Parse(line);
                        entry = ParseEntry(doc.RootElement);
                    }
                    catch
                    {
                        // Skip malformed line
                    }

                    if (entry != null) yield return (entry, stream.Position);
                }
            } while ((line = await reader.ReadLineAsync(ct)) != null);
        }
    }

    private static ParsedOfflineEntry? ParseEntry(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object) return null;

        var title = el.TryGetProperty("title", out var titleProp) ? titleProp.GetString() : null;
        if (string.IsNullOrWhiteSpace(title)) return null;

        var type = el.TryGetProperty("type", out var typeProp) ? typeProp.GetString() : null;
        int? episodes = el.TryGetProperty("episodes", out var epProp) && epProp.TryGetInt32(out var epVal) ? epVal : null;
        var status = el.TryGetProperty("status", out var stProp) ? stProp.GetString() : null;
        var picture = el.TryGetProperty("picture", out var picProp) ? picProp.GetString() : null;
        var thumbnail = el.TryGetProperty("thumbnail", out var thProp) ? thProp.GetString() : null;

        string? season = null;
        int? year = null;
        if (el.TryGetProperty("animeSeason", out var seasonObj) && seasonObj.ValueKind == JsonValueKind.Object)
        {
            if (seasonObj.TryGetProperty("season", out var sProp)) season = sProp.GetString();
            if (seasonObj.TryGetProperty("year", out var yProp) && yProp.TryGetInt32(out var yVal)) year = yVal;
        }

        List<string>? synonyms = null;
        if (el.TryGetProperty("synonyms", out var synArray) && synArray.ValueKind == JsonValueKind.Array)
        {
            synonyms = synArray.EnumerateArray()
                .Select(s => s.GetString())
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Select(s => s!)
                .ToList();
        }

        List<string>? tags = null;
        if (el.TryGetProperty("tags", out var tagArray) && tagArray.ValueKind == JsonValueKind.Array)
        {
            tags = tagArray.EnumerateArray()
                .Select(s => s.GetString())
                .Where(s => !string.IsNullOrWhiteSpace(s))
                .Select(s => s!)
                .ToList();
        }

        string? anilistId = null;
        string? malId = null;
        string? kitsuId = null;
        string? anidbId = null;

        if (el.TryGetProperty("sources", out var sourcesArray) && sourcesArray.ValueKind == JsonValueKind.Array)
        {
            foreach (var srcProp in sourcesArray.EnumerateArray())
            {
                var src = srcProp.GetString();
                if (string.IsNullOrWhiteSpace(src)) continue;

                if (anilistId == null && src.Contains("anilist.co/anime/", StringComparison.OrdinalIgnoreCase))
                    anilistId = ExtractId(src, "anilist.co/anime/");
                else if (malId == null && src.Contains("myanimelist.net/anime/", StringComparison.OrdinalIgnoreCase))
                    malId = ExtractId(src, "myanimelist.net/anime/");
                else if (kitsuId == null && (src.Contains("kitsu.io/anime/", StringComparison.OrdinalIgnoreCase) || src.Contains("kitsu.app/anime/", StringComparison.OrdinalIgnoreCase)))
                    kitsuId = ExtractId(src, "/anime/");
                else if (anidbId == null && src.Contains("anidb.net/anime/", StringComparison.OrdinalIgnoreCase))
                    anidbId = ExtractId(src, "anidb.net/anime/");
            }
        }

        return new ParsedOfflineEntry(
            Title: title,
            Type: type,
            Episodes: episodes,
            Status: status,
            Season: season,
            Year: year,
            Picture: picture,
            Thumbnail: thumbnail,
            Synonyms: synonyms,
            Tags: tags,
            AnilistId: anilistId,
            MalId: malId,
            KitsuId: kitsuId,
            AnidbId: anidbId);
    }

    private static string? ExtractId(string url, string segment)
    {
        var idx = url.IndexOf(segment, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return null;
        var sub = url[(idx + segment.Length)..].TrimStart('/');
        var end = sub.IndexOfAny(['/', '?', '#']);
        var id = end >= 0 ? sub[..end] : sub;
        return string.IsNullOrWhiteSpace(id) ? null : id.Trim();
    }

    /// <summary>
    /// First synonym that is actually a Latin-script title. Offline dumps mix Russian and
    /// English synonyms freely, and Cyrillic junk is useless as the stored romanized title.
    /// </summary>
    private static string? FirstLatinSynonym(List<string>? synonyms)
    {
        if (synonyms is null) return null;

        foreach (var synonym in synonyms)
        {
            var candidate = synonym?.Trim();
            if (string.IsNullOrWhiteSpace(candidate) || !IsMostlyLatin(candidate)) continue;
            return candidate;
        }

        return null;
    }

    /// <summary>True when every letter is Latin (ASCII or Latin Extended), and there is at least one.</summary>
    private static bool IsMostlyLatin(string value)
    {
        var hasLetter = false;
        foreach (var c in value)
        {
            if (!char.IsLetter(c)) continue;
            hasLetter = true;
            if (c > (char)0x024F) return false;
        }

        return hasLetter;
    }

    private sealed record ParsedOfflineEntry(
        string Title,
        string? Type,
        int? Episodes,
        string? Status,
        string? Season,
        int? Year,
        string? Picture,
        string? Thumbnail,
        List<string>? Synonyms,
        List<string>? Tags,
        string? AnilistId,
        string? MalId,
        string? KitsuId,
        string? AnidbId);
}
