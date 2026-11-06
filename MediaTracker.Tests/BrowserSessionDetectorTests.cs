using System.Linq;
using System.Text;
using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.SocialLib;
using Microsoft.Data.Sqlite;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Regression coverage for the Zen/Firefox localStorage session pickup: the schema has only
/// key/value columns (the legacy "utf16" column is gone), values arrive as TEXT or as
/// UTF-8/UTF-16LE BLOBs, and the origin folders drift (lib.social, auth.lib.social, …).
/// </summary>
public class BrowserSessionDetectorTests
{
    private const string AuthJson =
        """{"token":{"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123"},"user":{"id":123456,"username":"reader"}}""";

    private static byte[] Utf16WithPadding(string json)
    {
        var bytes = Encoding.Unicode.GetBytes(json);
        Array.Resize(ref bytes, bytes.Length + 2); // NUL padding Firefox appends
        return bytes;
    }

    [Fact]
    public void TryQueryAuthRows_TextValue_IsParsed()
    {
        var db = CreateDataSqlite(rows: [("auth", Encoding.UTF8.GetBytes(AuthJson))], textValue: true);

        var rows = BrowserSessionDetector.TryQueryAuthRows(db).ToList();

        rows.Should().HaveCount(1);
        rows[0].Should().Contain("access_token");
    }

    [Fact]
    public void TryQueryAuthRows_Utf16Blob_IsDecoded()
    {
        // Current Zen schema: value is a UTF-16LE blob with NUL padding.
        var db = CreateDataSqlite(rows: [("auth", Utf16WithPadding(AuthJson))]);

        var rows = BrowserSessionDetector.TryQueryAuthRows(db).ToList();

        rows.Should().HaveCount(1);
        rows[0].Should().Contain("eyJhbGciOiJIUzI1NiJ9");
    }

    [Fact]
    public void TryQueryAuthRows_Utf8Blob_IsDecoded()
    {
        var db = CreateDataSqlite(rows: [("auth", Encoding.UTF8.GetBytes(AuthJson))]);

        var rows = BrowserSessionDetector.TryQueryAuthRows(db).ToList();

        rows.Should().Contain(r => r.Contains("eyJhbGciOiJIUzI1NiJ9"));
    }

    [Fact]
    public void TryQueryAuthRows_NoUtf16Column_DoesNotThrow()
    {
        // The old code SELECTed "utf16" and surfaced `no such column: utf16`.
        var db = CreateDataSqlite(rows: [("auth", Encoding.UTF8.GetBytes(AuthJson))]);

        var act = () => BrowserSessionDetector.TryQueryAuthRows(db).ToList();

        act.Should().NotThrow();
    }

    [Theory]
    [InlineData("https+++lib.social", true)]
    [InlineData("https+++auth.lib.social", true)]
    [InlineData("https+++mangalib.me", true)]
    [InlineData("https+++ranobelib.me", true)]
    [InlineData("https+++v5.animelib.org", true)]
    [InlineData("https+++example.com", false)]
    public void TryFirefoxProfile_MatchesSocialLibFoldersOnly(string folder, bool shouldFind)
    {
        var profile = Path.Combine(Path.GetTempPath(), $"tsundoku-det-{Guid.NewGuid():N}");
        var lsDir = Path.Combine(profile, "storage", "default", folder, "ls");
        Directory.CreateDirectory(lsDir);
        CreateDataSqliteAt(Path.Combine(lsDir, "data.sqlite"), rows: [("auth", Utf16WithPadding(AuthJson))]);

        try
        {
            var session = BrowserSessionDetector.TryFirefoxProfile(profile);

            if (shouldFind)
            {
                session.Should().NotBeNull();
                session!.Token.Should().StartWith("eyJ");
                session.UserId.Should().Be(123456);
                session.Username.Should().Be("reader");
            }
            else
            {
                session.Should().BeNull();
            }
        }
        finally
        {
            Directory.Delete(profile, recursive: true);
        }
    }

    [Fact]
    public void TryFirefoxProfile_ScansNestedDataSqliteRecursively()
    {
        var profile = Path.Combine(Path.GetTempPath(), $"tsundoku-det-{Guid.NewGuid():N}");
        var deepDir = Path.Combine(profile, "storage", "default", "https+++mangalib.me", "deep", "nested", "storage");
        Directory.CreateDirectory(deepDir);
        CreateDataSqliteAt(Path.Combine(deepDir, "data.sqlite"), rows: [("auth", Utf16WithPadding(AuthJson))]);

        try
        {
            var session = BrowserSessionDetector.TryFirefoxProfile(profile);
            session.Should().NotBeNull();
            session!.Token.Should().StartWith("eyJ");
        }
        finally
        {
            Directory.Delete(profile, recursive: true);
        }
    }

    [Fact]
    public void DecodeStoredValue_PlainText_PassesThrough()
    {
        BrowserSessionDetector.DecodeStoredValue(AuthJson).Should().Be(AuthJson);
        BrowserSessionDetector.DecodeStoredValue(DBNull.Value).Should().BeNull();
        BrowserSessionDetector.DecodeStoredValue(null).Should().BeNull();
    }

    [Fact]
    public void ParseAuthJson_FlatToken_IsExtracted()
    {
        var json = """{"token":"eyJhbGciOiJIUzI1NiJ9.flat.token.value","id":42,"login":"tester"}""";

        var session = BrowserSessionDetector.ParseAuthJson(json, "test");

        session.Should().NotBeNull();
        session!.Token.Should().Be("eyJhbGciOiJIUzI1NiJ9.flat.token.value");
        session.UserId.Should().Be(42);
        session.Username.Should().Be("tester");
    }

    private static string CreateDataSqlite(
        (string key, byte[] value)[] rows, bool textValue = false) =>
        CreateDataSqliteAt(
            Path.Combine(Path.GetTempPath(), $"tsundoku-det-{Guid.NewGuid():N}.sqlite"), rows, textValue);

    private static string CreateDataSqliteAt(
        string path, (string key, byte[] value)[] rows, bool textValue = false)
    {
        using var conn = new SqliteConnection($"Data Source={path}");
        conn.Open();
        using var create = conn.CreateCommand();
        create.CommandText = "CREATE TABLE data (key TEXT PRIMARY KEY, value);";
        create.ExecuteNonQuery();
        foreach (var (key, value) in rows)
        {
            using var insert = conn.CreateCommand();
            insert.CommandText = "INSERT INTO data (key, value) VALUES (@key, @value);";
            insert.Parameters.AddWithValue("@key", key);
            if (textValue)
            {
                insert.Parameters.AddWithValue("@value", Encoding.UTF8.GetString(value));
            }
            else
            {
                insert.Parameters.AddWithValue("@value", value);
            }

            insert.ExecuteNonQuery();
        }

        return path;
    }
}
