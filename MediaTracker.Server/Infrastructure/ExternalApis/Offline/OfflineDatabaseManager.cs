using System.Diagnostics;
using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Offline;

public sealed class OfflineDatabaseManager
{
    public const string CreateTableSql = @"
        CREATE TABLE IF NOT EXISTS OfflineMedia (
            Id TEXT PRIMARY KEY,
            Title TEXT NOT NULL,
            OriginalTitle TEXT,
            Type TEXT NOT NULL,
            Year INTEGER,
            Genres TEXT,
            ExternalSource TEXT,
            ExternalId TEXT,
            ExtraDataJson TEXT
        );
    ";

    public const string CreateIndexesSql = @"
        CREATE INDEX IF NOT EXISTS IX_OfflineMedia_Search ON OfflineMedia (Type, Title COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS IX_OfflineMedia_OriginalSearch ON OfflineMedia (Type, OriginalTitle COLLATE NOCASE);
        PRAGMA optimize;
    ";

    private readonly AppPaths? _appPaths;
    private readonly ILogger<OfflineDatabaseManager>? _logger;
    private readonly IServiceScopeFactory? _scopeFactory;

    // Per-database toggles live in the DisabledSources setting as "offline:{fileName}" entries.
    // The manager cannot depend on ISourcePriorityService (it would close a DI cycle: the priority
    // service already takes the manager), so the setting is read directly through a scope.
    private IReadOnlySet<string>? _disabledFilesCache;
    private DateTimeOffset _disabledFilesCacheUntil;

    public OfflineDatabaseManager(
        AppPaths? appPaths = null,
        ILogger<OfflineDatabaseManager>? logger = null,
        IServiceScopeFactory? scopeFactory = null)
    {
        _appPaths = appPaths;
        _logger = logger;
        _scopeFactory = scopeFactory;
    }

    private static readonly IReadOnlySet<string> EmptySet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    /// <summary>File names of offline databases the user switched off via their own toggle.</summary>
    private async Task<IReadOnlySet<string>> GetDisabledDatabaseFileNamesAsync(CancellationToken ct)
    {
        if (_scopeFactory is null) return EmptySet;

        if (_disabledFilesCache is not null && DateTimeOffset.UtcNow < _disabledFilesCacheUntil)
        {
            return _disabledFilesCache;
        }

        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var value = await db.GetSettingAsync("DisabledSources", ct);
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (value is not null && !string.IsNullOrWhiteSpace(value))
            {
                var list = JsonSerializer.Deserialize(value, AppJsonSerializerContext.Default.ListString);
                foreach (var entry in list ?? [])
                {
                    if (entry.StartsWith("offline:", StringComparison.OrdinalIgnoreCase))
                    {
                        set.Add(entry["offline:".Length..].Trim());
                    }
                }
            }

            _disabledFilesCache = set;
            _disabledFilesCacheUntil = DateTimeOffset.UtcNow.AddSeconds(10);
            return set;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "[Offline] Failed to read per-database toggles");
            return _disabledFilesCache ?? EmptySet;
        }
    }

    private static bool IsDisabledFile(string dbPath, IReadOnlySet<string> disabled) =>
        disabled.Contains(Path.GetFileName(dbPath));

    public string OfflineDirectory =>
        _appPaths?.OfflineDirectory ?? Path.Combine(AppPaths.GetAppDirectory(), "data", "offline");

    public string AnimeDatabasePath => Path.Combine(OfflineDirectory, "anime_offline.db");
    public string MoviesDatabasePath => Path.Combine(OfflineDirectory, "movies_offline.db");
    public string GamesDatabasePath => Path.Combine(OfflineDirectory, "games_offline.db");

    public bool HasAnyDatabase => GetExistingDatabases().Count > 0;

    public IReadOnlyList<string> GetExistingDatabases(string? type = null)
    {
        var dirs = new List<string>();
        if (!string.IsNullOrWhiteSpace(OfflineDirectory) && Directory.Exists(OfflineDirectory))
        {
            dirs.Add(OfflineDirectory);
        }

        var appOfflineDir = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline");
        if (Directory.Exists(appOfflineDir) && !dirs.Contains(appOfflineDir, StringComparer.OrdinalIgnoreCase))
        {
            dirs.Add(appOfflineDir);
        }

        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var dir in dirs)
        {
            try
            {
                foreach (var file in Directory.EnumerateFiles(dir, "*.db", SearchOption.TopDirectoryOnly))
                {
                    var name = Path.GetFileName(file);
                    if (name.Contains(".tmp", StringComparison.OrdinalIgnoreCase) ||
                        name.EndsWith("-wal", StringComparison.OrdinalIgnoreCase) ||
                        name.EndsWith("-shm", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }
                    found.Add(Path.GetFullPath(file));
                }
            }
            catch (Exception ex)
            {
                _logger?.LogDebug(ex, "Failed to enumerate databases in '{Dir}': {Message}", dir, ex.Message);
            }
        }

        var list = found.ToList();

        // Sort by relevance to type if specified
        list.Sort((a, b) =>
        {
            var aName = Path.GetFileName(a).ToLowerInvariant();
            var bName = Path.GetFileName(b).ToLowerInvariant();

            int Score(string name)
            {
                if (type == "anime" && name.Contains("anime")) return 0;
                if ((type is "movie" or "tvshow") && name.Contains("movie")) return 0;
                if (type == "game" && (name.Contains("game") || name.Contains("openvgdb"))) return 0;
                return 1;
            }

            return Score(aName).CompareTo(Score(bName));
        });

        return list;
    }

    public string? ResolveDatabasePath(string fileNameOrPath)
    {
        if (string.IsNullOrWhiteSpace(fileNameOrPath)) return null;
        if (File.Exists(fileNameOrPath)) return Path.GetFullPath(fileNameOrPath);

        var targetFileName = Path.GetFileName(fileNameOrPath);
        foreach (var existing in GetExistingDatabases())
        {
            if (string.Equals(Path.GetFileName(existing), targetFileName, StringComparison.OrdinalIgnoreCase))
            {
                return existing;
            }
        }

        var candidate = Path.Combine(OfflineDirectory, targetFileName);
        if (File.Exists(candidate))
        {
            return Path.GetFullPath(candidate);
        }

        return null;
    }

    public async Task<IReadOnlyList<ExternalMediaDto>> ExecuteSearchInDatabaseAsync(
        string dbFileNameOrPath,
        string? type,
        string query,
        int limit,
        CancellationToken ct)
    {
        var resolvedPath = ResolveDatabasePath(dbFileNameOrPath);
        if (resolvedPath is null) return [];
        if (IsDisabledFile(resolvedPath, await GetDisabledDatabaseFileNamesAsync(ct))) return [];

        var normalized = query?.Trim();
        if (string.IsNullOrWhiteSpace(normalized)) return [];

        var results = new List<ExternalMediaDto>();
        var seenKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        await SearchSingleDatabaseAsync(resolvedPath, type, normalized, limit, seenKeys, results, ct);
        return results;
    }

    public async Task<ExternalMediaDto?> GetDetailsInDatabaseAsync(
        string dbFileNameOrPath,
        string externalId,
        string? title,
        string? type,
        CancellationToken ct)
    {
        var resolvedPath = ResolveDatabasePath(dbFileNameOrPath);
        if (resolvedPath is null) return null;
        if (IsDisabledFile(resolvedPath, await GetDisabledDatabaseFileNamesAsync(ct))) return null;

        return await GetDetailsFromDatabaseAsync(resolvedPath, externalId, title, ct);
    }

    public async Task<IReadOnlyList<ExternalMediaDto>> ExecuteSearchAsync(
        string? type,
        string query,
        int limit,
        CancellationToken ct)
    {
        var disabled = await GetDisabledDatabaseFileNamesAsync(ct);
        var dbs = GetExistingDatabases(type)
            .Where(dbPath => !IsDisabledFile(dbPath, disabled))
            .ToList();
        if (dbs.Count == 0) return [];

        var normalized = query?.Trim();
        if (string.IsNullOrWhiteSpace(normalized)) return [];

        var results = new List<ExternalMediaDto>();
        var seenKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var dbPath in dbs)
        {
            await SearchSingleDatabaseAsync(dbPath, type, normalized, limit, seenKeys, results, ct);
            if (results.Count >= limit) break;
        }

        return results;
    }

    private async Task SearchSingleDatabaseAsync(
        string dbPath,
        string? type,
        string normalized,
        int limit,
        HashSet<string> seenKeys,
        List<ExternalMediaDto> results,
        CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        try
        {
            await using var conn = new SqliteConnection($"Data Source={dbPath};Mode=ReadOnly;");
            await conn.OpenAsync(ct);

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                SELECT Id, Title, OriginalTitle, Type, Year, Genres, ExternalSource, ExternalId, ExtraDataJson
                FROM OfflineMedia
                WHERE (@type IS NULL OR Type = @type)
                  AND (
                       Title LIKE @pattern COLLATE NOCASE
                    OR OriginalTitle LIKE @pattern COLLATE NOCASE
                    OR ExternalId = @exact
                    OR Id = @exact
                  )
                ORDER BY
                  CASE
                    WHEN Title = @exact COLLATE NOCASE THEN 1
                    WHEN Title LIKE @prefix COLLATE NOCASE THEN 2
                    ELSE 3
                  END
                LIMIT @limit;
            ";

            cmd.Parameters.AddWithValue("@type", (object?)type ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@exact", normalized);
            cmd.Parameters.AddWithValue("@prefix", $"{normalized}%");
            cmd.Parameters.AddWithValue("@pattern", $"%{normalized}%");
            cmd.Parameters.AddWithValue("@limit", limit);

            await using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                var dto = MapRow(reader);
                var key = $"{dto.Type}:{dto.ExternalId ?? dto.Title}";
                if (seenKeys.Add(key))
                {
                    results.Add(dto);
                    if (results.Count >= limit) break;
                }
            }
        }
        catch (SqliteException ex) when (ex.SqliteErrorCode == 1)
        {
            // Table doesn't exist, ignore this db file
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "Offline search error in '{DbPath}' for '{Query}': {Message}", dbPath, normalized, ex.Message);
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(
        string externalId,
        string? title,
        string? type,
        CancellationToken ct)
    {
        var dbs = GetExistingDatabases(type);
        if (dbs.Count == 0) return null;

        foreach (var dbPath in dbs)
        {
            var dto = await GetDetailsFromDatabaseAsync(dbPath, externalId, title, ct);
            if (dto is not null) return dto;
        }

        return null;
    }

    private async Task<ExternalMediaDto?> GetDetailsFromDatabaseAsync(
        string dbPath,
        string externalId,
        string? title,
        CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        try
        {
            await using var conn = new SqliteConnection($"Data Source={dbPath};Mode=ReadOnly;");
            await conn.OpenAsync(ct);

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                SELECT Id, Title, OriginalTitle, Type, Year, Genres, ExternalSource, ExternalId, ExtraDataJson
                FROM OfflineMedia
                WHERE Id = @id
                   OR ExternalId = @id
                   OR ExtraDataJson LIKE @idPattern
                   OR (@title IS NOT NULL AND (Title = @title COLLATE NOCASE OR OriginalTitle = @title COLLATE NOCASE))
                LIMIT 1;
            ";

            cmd.Parameters.AddWithValue("@id", externalId ?? string.Empty);
            cmd.Parameters.AddWithValue("@idPattern", $"%\"{externalId}\"%");
            cmd.Parameters.AddWithValue("@title", (object?)title ?? DBNull.Value);

            await using var reader = await cmd.ExecuteReaderAsync(ct);
            if (await reader.ReadAsync(ct))
            {
                return MapRow(reader);
            }
        }
        catch (SqliteException ex) when (ex.SqliteErrorCode == 1)
        {
            // Table doesn't exist
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger?.LogDebug(ex, "Offline GetDetails error in '{DbPath}' for id '{Id}', title '{Title}': {Message}", dbPath, externalId, title, ex.Message);
        }

        return null;
    }

    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var dbs = GetExistingDatabases();
        if (dbs.Count == 0)
        {
            return new ConnectionTestResult(false, 0, "Локальные базы данных не найдены в data/offline/");
        }

        var sw = Stopwatch.StartNew();
        long totalCount = 0;
        var accessibleDbs = 0;

        foreach (var db in dbs)
        {
            try
            {
                await using var conn = new SqliteConnection($"Data Source={db};Mode=ReadOnly;");
                await conn.OpenAsync(ct);

                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT COUNT(1) FROM OfflineMedia;";
                totalCount += Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
                accessibleDbs++;
            }
            catch { }
        }
        sw.Stop();

        if (accessibleDbs == 0)
        {
            return new ConnectionTestResult(false, 0, "Таблица OfflineMedia не найдена в доступных базах данных.");
        }

        return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, $"OK ({totalCount:N0} тайтлов в {accessibleDbs} базах)");
    }

    public async Task<OfflineDatabasesSummaryDto> GetSummaryAsync(CancellationToken ct = default)
    {
        var dbs = GetExistingDatabases();
        var statuses = new List<OfflineDatabaseStatusDto>();
        var totalIndexedTitles = 0;

        foreach (var dbPath in dbs)
        {
            ct.ThrowIfCancellationRequested();
            var fileName = Path.GetFileName(dbPath);
            var lower = fileName.ToLowerInvariant();
            var fi = new FileInfo(dbPath);
            var fileSizeBytes = fi.Exists ? fi.Length : 0L;
            var lastModified = fi.Exists ? fi.LastWriteTimeUtc : DateTime.UtcNow;

            string name;
            string type;
            if (lower.Contains("movie") || lower.Contains("imdb"))
            {
                name = "Фильмы и сериалы (IMDb)";
                type = "movie";
            }
            else if (lower.Contains("anime"))
            {
                name = "Аниме (Anime Offline DB)";
                type = "anime";
            }
            else if (lower.Contains("game") || lower.Contains("openvgdb"))
            {
                name = "Игры (OpenVGDB)";
                type = "game";
            }
            else
            {
                name = Path.GetFileNameWithoutExtension(fileName);
                type = "all";
            }

            var totalTitles = 0;
            var isActive = false;
            try
            {
                await using var conn = new SqliteConnection($"Data Source={dbPath};Mode=ReadOnly;");
                await conn.OpenAsync(ct);
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT COUNT(1) FROM OfflineMedia;";
                var scalar = await cmd.ExecuteScalarAsync(ct);
                totalTitles = Convert.ToInt32(scalar);
                isActive = totalTitles > 0;
            }
            catch (Exception ex)
            {
                _logger?.LogDebug(ex, "Failed to count OfflineMedia rows in '{DbPath}': {Message}", dbPath, ex.Message);
            }

            totalIndexedTitles += totalTitles;
            statuses.Add(new OfflineDatabaseStatusDto(
                Name: name,
                FileName: fileName,
                Type: type,
                TotalTitles: totalTitles,
                FileSizeBytes: fileSizeBytes,
                LastModified: lastModified,
                IsActive: isActive,
                SourceDumpFileName: FindSourceDumpForDatabase(fileName)));
        }

        statuses.Sort((a, b) =>
        {
            static int Priority(string t) => t switch
            {
                "movie" => 0,
                "anime" => 1,
                "game" => 2,
                _ => 3
            };
            return Priority(a.Type).CompareTo(Priority(b.Type));
        });

        var pendingDumps = GetPendingDumps(statuses);

        return new OfflineDatabasesSummaryDto(
            Databases: statuses,
            TotalIndexedTitles: totalIndexedTitles,
            OfflineDirectoryPath: OfflineDirectory,
            PendingDumps: pendingDumps);
    }

    public IReadOnlyList<string> GetPendingDumps(IReadOnlyList<OfflineDatabaseStatusDto>? existingStatuses = null)
    {
        var pending = new List<string>();
        var dirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(OfflineDirectory) && Directory.Exists(OfflineDirectory))
        {
            dirs.Add(OfflineDirectory);
        }
        var appOfflineDir = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline");
        if (Directory.Exists(appOfflineDir))
        {
            dirs.Add(appOfflineDir);
        }

        var hasMoviesDb = existingStatuses?.Any(d => d.Type == "movie" && d.TotalTitles > 0)
                          ?? (File.Exists(MoviesDatabasePath) && new FileInfo(MoviesDatabasePath).Length > 0);
        var hasAnimeDb = existingStatuses?.Any(d => d.Type == "anime" && d.TotalTitles > 0)
                         ?? (File.Exists(AnimeDatabasePath) && new FileInfo(AnimeDatabasePath).Length > 0);
        var hasGamesDb = existingStatuses?.Any(d => d.Type == "game" && d.TotalTitles > 0)
                         ?? (File.Exists(GamesDatabasePath) && new FileInfo(GamesDatabasePath).Length > 0);

        if (!hasMoviesDb && FindDumpFile("title.basics.tsv") != null)
        {
            pending.Add("title.basics.tsv");
        }

        if (!hasAnimeDb)
        {
            var animeDump = FindDumpFile("anime-offline-database.jsonl") ?? FindDumpFile("anime-offline-database.json");
            if (animeDump != null)
            {
                pending.Add(Path.GetFileName(animeDump));
            }
        }

        if (!hasGamesDb && FindOpenVgdbSource() != null)
        {
            var src = FindOpenVgdbSource()!;
            pending.Add(Path.GetFileName(src));
        }

        foreach (var dir in dirs)
        {
            try
            {
                foreach (var file in Directory.EnumerateFiles(dir, "*.*", SearchOption.TopDirectoryOnly))
                {
                    var ext = Path.GetExtension(file).ToLowerInvariant();
                    if (ext is not (".tsv" or ".jsonl")) continue;

                    var name = Path.GetFileName(file);
                    if (pending.Contains(name, StringComparer.OrdinalIgnoreCase)) continue;
                    if (name.Equals("title.basics.tsv", StringComparison.OrdinalIgnoreCase)) continue;
                    if (name.StartsWith("anime-offline-database", StringComparison.OrdinalIgnoreCase)) continue;

                    var stem = Path.GetFileNameWithoutExtension(file);
                    var correspondingDb = Path.Combine(dir, $"{stem}.db");
                    if (!File.Exists(correspondingDb))
                    {
                        pending.Add(name);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogDebug(ex, "Failed to scan directory for pending dumps: {Dir}", dir);
            }
        }

        return pending;
    }

    /// <summary>
    /// The raw source dump (".jsonl" / ".json" / ".tsv") that produced <paramref name="dbFileName"/>,
    /// if it still sits in an offline directory. Known fixed-name databases (anime/movies/games) map
    /// to their canonical dumps; everything else matches by file stem. Null when nothing is found.
    /// </summary>
    public string? FindSourceDumpForDatabase(string dbFileName)
    {
        if (string.IsNullOrWhiteSpace(dbFileName)) return null;

        var dirs = new List<string>();
        if (!string.IsNullOrWhiteSpace(OfflineDirectory) && Directory.Exists(OfflineDirectory))
        {
            dirs.Add(OfflineDirectory);
        }

        var appOfflineDir = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline");
        if (Directory.Exists(appOfflineDir) && !dirs.Contains(appOfflineDir, StringComparer.OrdinalIgnoreCase))
        {
            dirs.Add(appOfflineDir);
        }

        var stem = Path.GetFileNameWithoutExtension(dbFileName).ToLowerInvariant();
        string[] knownDumps = stem switch
        {
            "anime_offline" => ["anime-offline-database.jsonl", "anime-offline-database.json"],
            "movies_offline" => ["title.basics.tsv"],
            "games_offline" => ["openvgdb.sqlite", "openvgdb.db"],
            _ => [$"{stem}.jsonl", $"{stem}.json", $"{stem}.tsv"],
        };

        foreach (var dir in dirs)
        {
            foreach (var candidate in knownDumps)
            {
                var path = Path.Combine(dir, candidate);
                if (File.Exists(path)) return path;
            }
        }

        return null;
    }

    /// <summary>
    /// Deletes a source dump from an offline directory. Only the file name is accepted and only
    /// files that are actually discoverable offline dumps are removed, so the endpoint cannot be
    /// pointed at arbitrary paths.
    /// </summary>
    public bool DeleteSourceDump(string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName)
            || fileName.Contains('/')
            || fileName.Contains('\\')
            || fileName.Contains(".."))
        {
            return false;
        }

        var dumpPath = FindSourceDumpForDatabase(fileName)
            // A dump that has no indexed database yet ("pending") is deletable too.
            ?? ResolveOfflineDumpPath(fileName);
        if (dumpPath is null || !File.Exists(dumpPath)) return false;

        try
        {
            File.Delete(dumpPath);
            _logger?.LogInformation("[Offline] Deleted source dump '{DumpPath}'", dumpPath);
            return true;
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "[Offline] Failed to delete source dump '{DumpPath}'", dumpPath);
            return false;
        }
    }

    private string? ResolveOfflineDumpPath(string fileName)
    {
        var dirs = new List<string>();
        if (!string.IsNullOrWhiteSpace(OfflineDirectory) && Directory.Exists(OfflineDirectory))
        {
            dirs.Add(OfflineDirectory);
        }

        var appOfflineDir = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline");
        if (Directory.Exists(appOfflineDir)) dirs.Add(appOfflineDir);

        foreach (var dir in dirs)
        {
            var candidate = Path.Combine(dir, fileName);
            if (File.Exists(candidate)) return Path.GetFullPath(candidate);
        }

        return null;
    }

    public void EnqueuePendingImports(IJobManager jobManager, ILogger? logger = null, bool force = false)
    {
        var log = logger ?? _logger;
        try
        {
            Directory.CreateDirectory(OfflineDirectory);
        }
        catch { }

        // 1. IMDb Basics (title.basics.tsv -> movies_offline.db)
        var imdbDump = FindDumpFile("title.basics.tsv");
        if (imdbDump != null && (force || !File.Exists(MoviesDatabasePath)))
        {
            log?.LogInformation("Enqueuing offline IMDb indexing from '{Dump}'...", imdbDump);
            jobManager.Enqueue(null, "Индексация офлайн-базы: IMDb", async (sp, token, progress) =>
            {
                var importer = new ImdbBasicsImporter();
                await importer.ImportDumpAsync(imdbDump, MoviesDatabasePath, progress, token);
            });
        }

        // 2. Anime Database (anime-offline-database.jsonl / .json -> anime_offline.db)
        var animeDump = FindDumpFile("anime-offline-database.jsonl") ?? FindDumpFile("anime-offline-database.json");
        if (animeDump != null && (force || !File.Exists(AnimeDatabasePath)))
        {
            log?.LogInformation("Enqueuing offline Anime indexing from '{Dump}'...", animeDump);
            jobManager.Enqueue(null, "Индексация офлайн-базы: Anime", async (sp, token, progress) =>
            {
                var importer = new AnimeOfflineDatabaseImporter();
                await importer.ImportDumpAsync(animeDump, AnimeDatabasePath, progress, token);
            });
        }

        // 3. OpenVGDB (openvgdb directory or openvgdb.sqlite/openvgdb.db -> games_offline.db)
        var openvgdbSource = FindOpenVgdbSource();
        if (openvgdbSource != null && (force || !File.Exists(GamesDatabasePath)))
        {
            log?.LogInformation("Enqueuing offline OpenVGDB indexing from '{Source}'...", openvgdbSource);
            jobManager.Enqueue(null, "Индексация офлайн-базы: OpenVGDB", async (sp, token, progress) =>
            {
                var importer = new OpenVgdbImporter();
                await importer.ImportAsync(openvgdbSource, GamesDatabasePath, progress, token);
            });
        }
    }

    private string? FindDumpFile(string fileName)
    {
        var primary = Path.Combine(OfflineDirectory, fileName);
        if (File.Exists(primary)) return primary;

        var secondary = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline", fileName);
        if (File.Exists(secondary)) return secondary;

        return null;
    }

    private string? FindOpenVgdbSource()
    {
        var dirs = new[]
        {
            Path.Combine(OfflineDirectory, "openvgdb"),
            Path.Combine(AppPaths.GetAppDirectory(), "data", "offline", "openvgdb")
        };

        foreach (var dir in dirs)
        {
            if (Directory.Exists(dir))
            {
                var sqlite = Path.Combine(dir, "openvgdb.sqlite");
                if (File.Exists(sqlite)) return sqlite;

                var db = Path.Combine(dir, "openvgdb.db");
                if (File.Exists(db)) return db;

                var any = Directory.EnumerateFiles(dir, "*.sqlite", SearchOption.TopDirectoryOnly)
                    .Concat(Directory.EnumerateFiles(dir, "*.db", SearchOption.TopDirectoryOnly))
                    .FirstOrDefault(f => !Path.GetFileName(f).StartsWith('.'));
                if (any != null) return any;
            }
        }

        var directFiles = new[]
        {
            Path.Combine(OfflineDirectory, "openvgdb.sqlite"),
            Path.Combine(OfflineDirectory, "openvgdb.db"),
            Path.Combine(AppPaths.GetAppDirectory(), "data", "offline", "openvgdb.sqlite"),
            Path.Combine(AppPaths.GetAppDirectory(), "data", "offline", "openvgdb.db")
        };

        foreach (var file in directFiles)
        {
            if (File.Exists(file)) return file;
        }

        return null;
    }

    public static ExternalMediaDto MapRow(SqliteDataReader reader)
    {
        var id = reader.GetString(0);
        var title = reader.GetString(1);
        var originalTitle = reader.IsDBNull(2) ? null : reader.GetString(2);
        var type = reader.GetString(3);
        var year = reader.IsDBNull(4) ? (int?)null : reader.GetInt32(4);
        var genresStr = reader.IsDBNull(5) ? null : reader.GetString(5);
        var externalSource = reader.IsDBNull(6) ? null : reader.GetString(6);
        var externalId = reader.IsDBNull(7) ? null : reader.GetString(7);
        var extraJson = reader.IsDBNull(8) ? null : reader.GetString(8);

        OfflineExtraData? extra = null;
        if (!string.IsNullOrWhiteSpace(extraJson))
        {
            try
            {
                extra = JsonSerializer.Deserialize(extraJson, AppJsonSerializerContext.Default.OfflineExtraData);
            }
            catch { }
        }

        List<string>? genres = null;
        if (!string.IsNullOrWhiteSpace(genresStr))
        {
            genres = genresStr.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToList();
        }

        return new ExternalMediaDto
        {
            ExternalId = externalId ?? id,
            ExternalSource = "offline",
            Title = title,
            OriginalTitle = originalTitle,
            Type = type,
            ReleaseYear = year,
            Genres = genres ?? extra?.Tags,
            Tags = extra?.Tags ?? genres,
            CoverUrl = extra?.CoverUrl,
            Description = extra?.Description,
            Format = extra?.Format,
            TotalCount = extra?.TotalCount,
            RuntimeMinutes = extra?.RuntimeMinutes,
            ReleaseStatus = extra?.ReleaseStatus,
            Studio = extra?.Studio ?? extra?.Developer,
            Platform = extra?.Platform,
            AnilistId = extra?.AnilistId,
            MalId = extra?.MalId,
            KitsuId = extra?.KitsuId,
            AnidbId = extra?.AnidbId,
            SteamAppId = extra?.SteamAppId,
        };
    }
}
