using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.MangaLib;

/// <summary>Detection result handed to the settings endpoint; the token is persisted encrypted.</summary>
public sealed record BrowserSession(int UserId, string Username, string Token, string SourcePath);

/// <summary>JSON contract of <c>POST /api/settings/sources/mangalib/detect-token</c>.</summary>
public sealed record MangalibSessionResponse(
    bool Success,
    int? UserId,
    string? Username,
    string? Source,
    string? Message);

/// <summary>
/// Picks up an existing SocialLib (MangaLib / AnimeLib / RanobeLib) session from the user's own
/// browsers so the import never needs a hand-pasted token. Two stores are searched:
///  1. Firefox-family localStorage archives (Zen Browser, Firefox — incl. flatpak/snap variants):
///     every <c>&lt;profile&gt;/storage/default/&lt;origin&gt;/ls/data.sqlite</c> whose folder name
///     matches a SocialLib domain (mangalib, lib.social, auth.lib.social, anilib, ranobelib, …).
///     Rows under keys auth / token / access_token / user are read from the <c>value</c> column
///     (TEXT is parsed as JSON directly; BLOBs are decoded as UTF-8 first, then UTF-16LE);
///  2. the isolated Chromium profile BrowserLauncher keeps at
///     <c>~/.local/share/Tsundoku/tsundoku-chromium-profile</c> — its Local Storage leveldb is
///     scanned for the auth JSON.
/// Everything stays local: the file is always read from a temporary snapshot (copy first, so a
/// running browser's exclusive lock cannot produce `database is locked`), and only the token/user
/// pair leaves the detector.
/// </summary>
public static class BrowserSessionDetector
{
    /// <summary>storage/default/ folder names are matched against these fragments (case-insensitive).</summary>
    private static readonly string[] StorageFolderPatterns =
    [
        "mangalib",
        "lib.social",
        "anilib",
        "animelib",
        "auth",
        "ranobelib",
        "slashlib",
        "hentailib",
    ];

    /// <summary>LocalStorage keys that carry the SocialLib auth JSON (any of them may hold it).</summary>
    private static readonly string[] AuthKeys = ["auth", "token", "access_token", "user"];

    public static Task<BrowserSession?> TryDetectSessionAsync(CancellationToken ct = default)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var stats = new DetectionStats();

        var zenProfiles = GetZenProfiles(home, out var checkedZenPaths);
        var allCheckedPaths = new List<string>(checkedZenPaths)
        {
            Path.Combine(home, ".mozilla", "firefox"),
            Path.Combine(home, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox"),
            Path.Combine(home, "snap", "firefox", "common", ".mozilla", "firefox"),
        };

        // 1. Check Zen Browser profiles first
        foreach (var profile in zenProfiles)
        {
            ct.ThrowIfCancellationRequested();
            var session = TryFirefoxProfile(profile, stats);
            if (session is not null)
            {
                Serilog.Log.Information(
                    "MangaLib session found in Zen profile: {Profile}. Zen profiles found: {ZenCount}. Checked paths: {Paths}",
                    profile,
                    zenProfiles.Count,
                    string.Join(", ", allCheckedPaths));
                return Task.FromResult<BrowserSession?>(session);
            }
        }

        // 2. Check other Firefox-family profiles
        var otherFirefoxRoots = new[]
        {
            Path.Combine(home, ".mozilla", "firefox"),
            Path.Combine(home, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox"),
            Path.Combine(home, "snap", "firefox", "common", ".mozilla", "firefox"),
        };

        foreach (var root in otherFirefoxRoots.Select(NormalizeHome).Where(Directory.Exists))
        {
            foreach (var profile in EnumerateProfileDirs(root))
            {
                ct.ThrowIfCancellationRequested();
                var session = TryFirefoxProfile(profile, stats);
                if (session is not null)
                {
                    Serilog.Log.Information(
                        "MangaLib session found in Firefox profile: {Profile}. Zen profiles found: {ZenCount}. Checked paths: {Paths}",
                        profile,
                        zenProfiles.Count,
                        string.Join(", ", allCheckedPaths));
                    return Task.FromResult<BrowserSession?>(session);
                }
            }
        }

        // 3. Chromium-family: the isolated profile BrowserLauncher maintains. Standard browser
        // profiles are intentionally NOT scanned — only our own profile is unambiguous consent.
        var chromiumLevelDb = Path.Combine(
            home, ".local", "share", "Tsundoku", "tsundoku-chromium-profile",
            "Default", "Local Storage", "leveldb");
        if (Directory.Exists(chromiumLevelDb))
        {
            ct.ThrowIfCancellationRequested();
            var session = TryChromiumLevelDb(chromiumLevelDb);
            if (session is not null)
            {
                Serilog.Log.Information(
                    "MangaLib session found in isolated Chromium profile. Zen profiles found: {ZenCount}. Checked paths: {Paths}",
                    zenProfiles.Count,
                    string.Join(", ", allCheckedPaths));
                return Task.FromResult<BrowserSession?>(session);
            }
        }

        // Nothing found: say what was actually inspected so a missing session is diagnosable.
        Serilog.Log.Information(
            "MangaLib session not found. Zen profiles found: {ZenCount} ({ZenProfiles}). Checked paths: {Paths}. Total profiles scanned: {TotalProfiles}. data.sqlite checked: {Databases}. Domains seen: {Domains}",
            zenProfiles.Count,
            zenProfiles.Count == 0 ? "(none)" : string.Join(", ", zenProfiles),
            string.Join(", ", allCheckedPaths),
            stats.ProfileDirs.Count == 0 ? "(none)" : string.Join(", ", stats.ProfileDirs),
            stats.DatabaseCount,
            stats.Domains.Count == 0 ? "(none)" : string.Join(", ", stats.Domains));

        return Task.FromResult<BrowserSession?>(null);
    }

    private static List<string> GetZenProfiles(string home, out List<string> checkedZenPaths)
    {
        checkedZenPaths =
        [
            Path.Combine(home, ".zen"),
            Path.Combine(home, ".config", "zen"),
            Path.Combine(home, ".zen-browser"),
            Path.Combine(home, ".var", "app", "app.zen_browser.zen"),
            Path.Combine(home, ".var", "app", "io.github.zen_browser.zen"),
        ];

        var profiles = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void AddProfile(string dir)
        {
            if (Directory.Exists(dir) && seen.Add(dir))
            {
                profiles.Add(dir);
            }
        }

        foreach (var root in new[]
        {
            Path.Combine(home, ".zen"),
            Path.Combine(home, ".config", "zen"),
            Path.Combine(home, ".zen-browser"),
        })
        {
            if (!Directory.Exists(root)) continue;
            foreach (var p in EnumerateProfileDirs(root)) AddProfile(p);
        }

        var flatpakRoots = new[]
        {
            Path.Combine(home, ".var", "app", "app.zen_browser.zen"),
            Path.Combine(home, ".var", "app", "io.github.zen_browser.zen"),
        };

        foreach (var flatpakDir in flatpakRoots)
        {
            if (!Directory.Exists(flatpakDir)) continue;

            foreach (var sub in new[] { ".zen", Path.Combine(".config", "zen"), ".zen-browser" })
            {
                var candidate = Path.Combine(flatpakDir, sub);
                if (Directory.Exists(candidate))
                {
                    foreach (var p in EnumerateProfileDirs(candidate)) AddProfile(p);
                }
            }

            try
            {
                foreach (var storage in Directory.EnumerateDirectories(flatpakDir, "storage", SearchOption.AllDirectories))
                {
                    if (Directory.Exists(Path.Combine(storage, "default")))
                    {
                        var parent = Directory.GetParent(storage)?.FullName;
                        if (!string.IsNullOrEmpty(parent)) AddProfile(parent);
                    }
                }
            }
            catch (Exception)
            {
                // Ignore filesystem exceptions in sandbox hierarchy
            }
        }

        return profiles;
    }

    /// <summary>What the last scan actually looked at — logged when no session is found.</summary>
    internal sealed class DetectionStats
    {
        public List<string> ProfileDirs { get; } = [];
        public HashSet<string> Domains { get; } = new(StringComparer.OrdinalIgnoreCase);
        public int DatabaseCount { get; set; }
    }

    private static string NormalizeHome(string path) => path
        .Replace("~", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    private static IEnumerable<string> EnumerateProfileDirs(string root)
    {
        if (!Directory.Exists(root)) yield break;

        if (Directory.Exists(Path.Combine(root, "storage", "default")))
        {
            yield return root;
            yield break;
        }

        foreach (var dir in Directory.EnumerateDirectories(root))
        {
            yield return dir;
            if (dir.EndsWith("Profiles", StringComparison.OrdinalIgnoreCase))
            {
                foreach (var nested in Directory.EnumerateDirectories(dir)) yield return nested;
            }
        }
    }

    internal static BrowserSession? TryFirefoxProfile(string profileDir, DetectionStats? stats = null)
    {
        stats?.ProfileDirs.Add(profileDir);

        var storageDefault = Path.Combine(profileDir, "storage", "default");
        if (!Directory.Exists(storageDefault)) return null;

        // Origins drift (mangalib.me -> lib.social, auth.lib.social, …) and Zen containers add
        // suffixes (…^userContextId=1): match the folder name against fragments instead of a
        // hard-coded origin list.
        foreach (var originDir in Directory.EnumerateDirectories(storageDefault))
        {
            var name = Path.GetFileName(originDir);
            stats?.Domains.Add(name);

            var matchesOrigin = StorageFolderPatterns.Any(pattern =>
                name.Contains(pattern, StringComparison.OrdinalIgnoreCase));

            IEnumerable<string> sqliteFiles;
            try
            {
                if (matchesOrigin)
                {
                    sqliteFiles = Directory.EnumerateFiles(originDir, "data.sqlite", SearchOption.AllDirectories);
                }
                else
                {
                    sqliteFiles = Directory.EnumerateDirectories(originDir, "*", SearchOption.AllDirectories)
                        .Where(subDir => StorageFolderPatterns.Any(pattern =>
                            Path.GetFileName(subDir).Contains(pattern, StringComparison.OrdinalIgnoreCase)))
                        .SelectMany(subDir => Directory.EnumerateFiles(subDir, "data.sqlite", SearchOption.AllDirectories));
                }
            }
            catch (Exception)
            {
                continue;
            }

            foreach (var dbPath in sqliteFiles)
            {
                if (stats is not null) stats.DatabaseCount++;

                foreach (var raw in ReadFirefoxAuthValues(dbPath))
                {
                    var session = ParseAuthJson(raw, $"{Path.GetFileName(profileDir)}/{name}");
                    if (session is not null) return session;

                    // The row holds the auth JSON in a non-parseable shape (truncated key,
                    // extra wrapper): fall back to pulling the JWT straight out of the text.
                    session = ExtractTokenByPattern(raw, $"{Path.GetFileName(profileDir)}/{name}");
                    if (session is not null) return session;
                }
            }
        }
        return null;
    }

    /// <summary>
    /// Reads the DB from a snapshot: Firefox/Zen holds an exclusive lock while running, so the
    /// live file is copied to /tmp first (WAL sidecars included). Direct read-only access is
    /// only the fallback when the copy itself fails.
    /// </summary>
    private static IEnumerable<string> ReadFirefoxAuthValues(string dbPath)
    {
        var temp = Path.Combine(Path.GetTempPath(), $"mangalib_detect_{Guid.NewGuid():N}.sqlite");
        try
        {
            File.Copy(dbPath, temp, overwrite: true);
            foreach (var suffix in new[] { "-wal", "-shm" })
            {
                var sidecar = dbPath + suffix;
                if (File.Exists(sidecar))
                {
                    try { File.Copy(sidecar, temp + suffix, overwrite: true); }
                    catch (IOException) { /* sidecar is optional */ }
                }
            }

            return TryQueryAuthRows(temp).ToList();
        }
        catch (IOException)
        {
            return TryQueryAuthRows(dbPath).ToList();
        }
        catch (UnauthorizedAccessException)
        {
            return TryQueryAuthRows(dbPath).ToList();
        }
        finally
        {
            foreach (var suffix in new[] { "", "-wal", "-shm" })
            {
                try { File.Delete(temp + suffix); } catch { /* best effort cleanup */ }
            }
        }
    }

    internal static IEnumerable<string> TryQueryAuthRows(string dbPath)
    {
        var results = new List<string>();
        try
        {
            using var conn = new SqliteConnection(
                new SqliteConnectionStringBuilder
                {
                    DataSource = dbPath,
                    Mode = SqliteOpenMode.ReadOnly,
                    Cache = SqliteCacheMode.Private,
                    Pooling = false,
                }.ToString());
            conn.Open();

            // Only the "value" column exists in current Firefox/Zen schemas — the legacy
            // "utf16" column is gone, and SELECTing it throws `no such column`. Scan every row:
            // the auth JSON may sit under any key, and the value may be TEXT or a BLOB
            // (UTF-8/UTF-16LE payload).
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT key, value FROM data;";
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                if (reader.FieldCount < 2) continue;

                var text = DecodeStoredValue(reader.GetValue(1));
                if (text is null) continue;

                var key = reader.GetValue(0)?.ToString();
                if (IsAuthCandidate(text) ||
                    (key is not null && AuthKeys.Contains(key, StringComparer.OrdinalIgnoreCase)))
                {
                    results.Add(text);
                }
            }
        }
        catch (SqliteException)
        {
            // Not a localStorage schema (or a locked/corrupt file): nothing to extract.
        }
        catch (IOException)
        {
            // The browser is mid-write; the temp-copy fallback retries.
        }
        return results;
    }

    /// <summary>TEXT is used as-is; BLOBs decode as UTF-8 first, then UTF-16LE (NUL-padded).</summary>
    internal static string? DecodeStoredValue(object? raw)
    {
        if (raw is null or DBNull) return null;

        if (raw is byte[] blob)
        {
            // Try UTF-8 first; when the decode is invalid (JSON starting with '{' but every
            // second byte a NUL — the signature of UTF-16LE read as UTF-8), fall back.
            foreach (var encoding in new[] { Encoding.UTF8, Encoding.Unicode })
            {
                var text = encoding.GetString(blob).TrimEnd('\0');
                if (IsAuthCandidate(text)) return text;
            }

            return null;
        }

        var stored = raw.ToString();
        return string.IsNullOrWhiteSpace(stored) ? null : stored.TrimEnd('\0');
    }

    /// <summary>A usable payload: printable JSON without embedded NUL bytes.</summary>
    private static bool IsAuthCandidate(string text) =>
        !text.Contains('\0') &&
        (text.TrimStart().StartsWith('{') || text.Contains("eyJ", StringComparison.Ordinal));

    /// <summary>Last-resort extraction: a JWT substring straight out of arbitrary text.</summary>
    private static BrowserSession? ExtractTokenByPattern(string text, string sourcePath)
    {
        // JWTs start with the base64url "eyJ" header marker and continue with base64url
        // characters plus the two '.' separators.
        var start = text.IndexOf("eyJ", StringComparison.Ordinal);
        while (start >= 0)
        {
            var end = start;
            while (end < text.Length &&
                   (char.IsAsciiLetterOrDigit(text[end]) || text[end] is '-' or '_' or '.'))
            {
                end++;
            }

            var token = text[start..end];
            if (token.Length >= 20)
            {
                return new BrowserSession(0, string.Empty, token, sourcePath);
            }

            start = text.IndexOf("eyJ", start + 3, StringComparison.Ordinal);
        }
        return null;
    }

    private static BrowserSession? TryChromiumLevelDb(string levelDbDir)
    {
        foreach (var file in Directory.EnumerateFiles(levelDbDir))
        {
            var ext = Path.GetExtension(file);
            if (ext is not (".log" or ".ldb" or ".sst")) continue;
            try
            {
                if (new FileInfo(file).Length > 256L * 1024 * 1024) continue;
                var bytes = File.ReadAllBytes(file);
                var session = ScanChromiumBytes(bytes, Path.GetFileName(file));
                if (session is not null) return session;
            }
            catch (IOException)
            {
                // The shell may be mid-write; the next detection pass retries.
            }
        }
        return null;
    }

    /// <summary>Chrome Local Storage keeps values as UTF-8 (0x01-prefixed) or UTF-16LE (0x00-prefixed)
    /// records inside leveldb log/table files: search both encodings for the auth JSON.</summary>
    private static BrowserSession? ScanChromiumBytes(byte[] bytes, string sourceName)
    {
        foreach (var encoding in new[] { Encoding.UTF8, Encoding.Unicode })
        {
            var tokenMarker = encoding.GetBytes("\"access_token\":\"");
            var offset = IndexOf(bytes, tokenMarker);
            while (offset >= 0)
            {
                var window = DecodeWindow(bytes, offset, encoding, windowSize: 4096);
                var session = ParseAuthJson(window, sourceName);
                if (session is not null) return session;
                offset = IndexOf(bytes, tokenMarker, offset + tokenMarker.Length);
            }
        }
        return null;
    }

    private static string DecodeWindow(byte[] bytes, int offset, Encoding encoding, int windowSize)
    {
        var start = Math.Max(0, offset - windowSize / 4);
        var length = Math.Min(bytes.Length - start, windowSize);
        // Align the window start to the encoding's character size so UTF-16 decoding stays valid.
        if (encoding is System.Text.UnicodeEncoding && (start & 1) == 1)
        {
            start--;
            length++;
        }
        var decoded = encoding.GetString(bytes, start, length);
        // The decoded window may start mid-JSON; keep the auth object tail which is what we parse.
        return decoded;
    }

    private static int IndexOf(byte[] haystack, byte[] needle, int from = 0)
    {
        var last = haystack.Length - needle.Length;
        for (var i = Math.Max(0, from); i <= last; i++)
        {
            var match = true;
            for (var j = 0; j < needle.Length; j++)
            {
                if (haystack[i + j] == needle[j]) continue;
                match = false;
                break;
            }
            if (match) return i;
        }
        return -1;
    }

    /// <summary>
    /// Extracts the token and user from the SocialLib localStorage auth JSON:
    /// <c>{"token":{"access_token":"eyJ…"},"user":{"id":123,"username":"…"}}</c> (older builds
    /// store the token flat or under "token" directly).
    /// </summary>
    internal static BrowserSession? ParseAuthJson(string json, string sourcePath)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var token = ExtractToken(root);
            if (string.IsNullOrWhiteSpace(token) || token.Length < 20) return null;

            var user = root.TryGetProperty("user", out var userEl) && userEl.ValueKind == JsonValueKind.Object
                ? userEl
                : root;

            var id = user.TryGetProperty("id", out var idEl) && idEl.ValueKind is JsonValueKind.Number or JsonValueKind.String
                ? idEl.ToString() switch
                {
                    "" => 0,
                    var s => int.TryParse(s, out var parsed) ? parsed : 0,
                }
                : 0;
            if (id == 0 && user.TryGetProperty("userId", out var userIdEl))
            {
                int.TryParse(userIdEl.ToString(), out id);
            }

            var username = FirstString(user, "username", "login", "nickname", "name") ?? string.Empty;

            return new BrowserSession(id, username, token, sourcePath);
        }
        catch (JsonException)
        {
            // Not the auth row (or a truncated leveldb window).
            return null;
        }
    }

    private static string? ExtractToken(JsonElement root)
    {
        if (root.TryGetProperty("token", out var tokenEl))
        {
            if (tokenEl.ValueKind == JsonValueKind.String && tokenEl.GetString() is { } raw &&
                raw.StartsWith("eyJ", StringComparison.Ordinal))
            {
                return raw;
            }
            if (tokenEl.ValueKind == JsonValueKind.Object &&
                tokenEl.TryGetProperty("access_token", out var nested) &&
                nested.ValueKind == JsonValueKind.String)
            {
                return nested.GetString();
            }
        }
        if (root.TryGetProperty("access_token", out var accessTokenEl) &&
            accessTokenEl.ValueKind == JsonValueKind.String)
        {
            return accessTokenEl.GetString();
        }
        return null;
    }

    private static string? FirstString(JsonElement el, params string[] names)
    {
        foreach (var name in names)
        {
            if (el.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String)
            {
                var s = value.GetString();
                if (!string.IsNullOrWhiteSpace(s)) return s;
            }
        }
        return null;
    }
}
