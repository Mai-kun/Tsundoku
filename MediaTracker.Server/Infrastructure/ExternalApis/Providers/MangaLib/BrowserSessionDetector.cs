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
/// Everything stays local: the file is opened read-only (a temp copy when the browser holds a
/// lock) and only the token/user pair leaves the detector.
/// </summary>
public static class BrowserSessionDetector
{
    /// <summary>storage/default/ folder names are matched against these fragments (case-insensitive).</summary>
    private static readonly string[] StorageFolderPatterns =
    [
        "mangalib",
        "lib.social",
        "anilib",
        "ranobelib",
        "slashlib",
        "hentailib",
    ];

    /// <summary>LocalStorage keys that carry the SocialLib auth JSON (any of them may hold it).</summary>
    private static readonly string[] AuthKeys = ["auth", "token", "access_token", "user"];

    public static Task<BrowserSession?> TryDetectSessionAsync(CancellationToken ct = default)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        // Firefox-family: each root contains one profile directory per folder (Zen keeps them
        // directly under the root; some distributions nest them under "Profiles").
        var firefoxRoots = new[]
        {
            Path.Combine(home, ".zen"),
            Path.Combine(home, ".mozilla", "firefox"),
            Path.Combine(home, ".var", "app", "app.zen_browser.zen", ".zen"),
            Path.Combine(home, ".var", "app", "io.github.zen_browser.zen", ".zen"),
            Path.Combine(home, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox"),
            Path.Combine(home, "snap", "firefox", "common", ".mozilla", "firefox"),
        };

        foreach (var root in firefoxRoots.Select(NormalizeHome).Where(Directory.Exists))
        {
            foreach (var profile in EnumerateProfileDirs(root))
            {
                ct.ThrowIfCancellationRequested();
                var session = TryFirefoxProfile(profile);
                if (session is not null) return Task.FromResult<BrowserSession?>(session);
            }
        }

        // Chromium-family: the isolated profile BrowserLauncher maintains. Standard browser
        // profiles are intentionally NOT scanned — only our own profile is unambiguous consent.
        var chromiumLevelDb = Path.Combine(
            home, ".local", "share", "Tsundoku", "tsundoku-chromium-profile",
            "Default", "Local Storage", "leveldb");
        if (Directory.Exists(chromiumLevelDb))
        {
            ct.ThrowIfCancellationRequested();
            var session = TryChromiumLevelDb(chromiumLevelDb);
            if (session is not null) return Task.FromResult<BrowserSession?>(session);
        }

        return Task.FromResult<BrowserSession?>(null);
    }

    private static string NormalizeHome(string path) => path
        .Replace("~", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    private static IEnumerable<string> EnumerateProfileDirs(string root)
    {
        foreach (var dir in Directory.EnumerateDirectories(root))
        {
            yield return dir;
            if (dir.EndsWith("Profiles", StringComparison.OrdinalIgnoreCase))
            {
                foreach (var nested in Directory.EnumerateDirectories(dir)) yield return nested;
            }
        }
    }

    internal static BrowserSession? TryFirefoxProfile(string profileDir)
    {
        var storageDefault = Path.Combine(profileDir, "storage", "default");
        if (!Directory.Exists(storageDefault)) return null;

        // Origins drift (mangalib.me -> lib.social, auth.lib.social, …): match the folder
        // name against fragments instead of a hard-coded origin list.
        foreach (var originDir in Directory.EnumerateDirectories(storageDefault))
        {
            var name = Path.GetFileName(originDir);
            if (!StorageFolderPatterns.Any(pattern =>
                    name.Contains(pattern, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            var dbPath = Path.Combine(originDir, "ls", "data.sqlite");
            if (!File.Exists(dbPath)) continue;

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
        return null;
    }

    /// <summary>Reads the auth rows read-only; falls back to a temp copy when the browser locks the DB.</summary>
    private static IEnumerable<string> ReadFirefoxAuthValues(string dbPath)
    {
        var values = TryQueryAuthRows(dbPath).ToList();
        if (values.Count > 0) return values;

        // Firefox keeps an exclusive lock while running: read a snapshot instead.
        try
        {
            var temp = Path.Combine(Path.GetTempPath(), $"tsundoku-ls-{Guid.NewGuid():N}.sqlite");
            try
            {
                File.Copy(dbPath, temp, overwrite: true);
                return TryQueryAuthRows(temp);
            }
            finally
            {
                try { File.Delete(temp); } catch { /* best effort cleanup */ }
            }
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
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
            // "utf16" column is gone, and SELECTing it throws `no such column`. The value
            // itself may be TEXT (JSON) or a BLOB (UTF-8/UTF-16LE payload).
            using var cmd = conn.CreateCommand();
            cmd.CommandText =
                """
                SELECT key, value FROM data
                WHERE key IN ('auth', 'token', 'access_token', 'user') OR value LIKE '%eyJ%';
                """;
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                if (reader.FieldCount < 2) continue;
                var text = DecodeStoredValue(reader.GetValue(1));
                if (text is not null) results.Add(text);
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

    /// <summary>Last-resort extraction: the JWT substring straight out of arbitrary text.</summary>
    private static BrowserSession? ExtractTokenByPattern(string text, string sourcePath)
    {
        foreach (var marker in new[] { "\"access_token\":\"", "\"token\":\"" })
        {
            var start = text.IndexOf(marker, StringComparison.Ordinal);
            if (start < 0) continue;

            start += marker.Length;
            if (start >= text.Length || !text.AsSpan(start).StartsWith("eyJ", StringComparison.Ordinal)) continue;

            var end = text.IndexOf('"', start);
            if (end < 0) end = Math.Min(text.Length, start + 4096);
            var token = text[start..end];
            if (token.Length >= 20)
            {
                return new BrowserSession(0, string.Empty, token, sourcePath);
            }
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
