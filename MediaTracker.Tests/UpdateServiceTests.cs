using System.IO.Compression;
using System.Text;
using MediaTracker.Server.Features.System.Updates;
using Xunit;

namespace MediaTracker.Tests;

public sealed class UpdateServiceTests
{
    [Fact]
    public void ApplyZip_UpdatesBinariesAndWwwroot_PreservesUserDataByteForByte()
    {
        var testId = Guid.NewGuid().ToString("N");
        var baseDir = Path.Combine(Path.GetTempPath(), $"update_test_base_{testId}");
        var zipSourceDir = Path.Combine(Path.GetTempPath(), $"update_test_src_{testId}");
        var zipPath = Path.Combine(Path.GetTempPath(), $"update_payload_{testId}.zip");

        try
        {
            Directory.CreateDirectory(baseDir);
            Directory.CreateDirectory(zipSourceDir);

            // --- 1. Seed base application directory with old files and user data ---
            var oldBinaryBytes = Encoding.UTF8.GetBytes("OLD_BINARY_v1.0.0");
            var oldJsBytes = Encoding.UTF8.GetBytes("console.log('old wwwroot asset');");
            var originalStorageBytes = Encoding.UTF8.GetBytes("{\"mode\":\"portable\",\"customPath\":null}");
            var originalSecretKey = Encoding.UTF8.GetBytes("DO_NOT_TOUCH_SECRET_KEY_12345");
            var originalDbBytes = Encoding.UTF8.GetBytes("SQLITE_DATABASE_BINARY_HEADER_DATA_123");
            var originalCoverBytes = Encoding.UTF8.GetBytes("WEBP_IMAGE_PAYLOAD_ORIGINAL_COVER");
            var originalLogBytes = Encoding.UTF8.GetBytes("log entry: app started");
            var originalCustomDb = Encoding.UTF8.GetBytes("ANOTHER_DB_CONTENT");

            File.WriteAllBytes(Path.Combine(baseDir, "Tsundoku"), oldBinaryBytes);

            var oldWwwroot = Path.Combine(baseDir, "wwwroot", "assets");
            Directory.CreateDirectory(oldWwwroot);
            File.WriteAllBytes(Path.Combine(oldWwwroot, "old.js"), oldJsBytes);

            File.WriteAllBytes(Path.Combine(baseDir, "storage.json"), originalStorageBytes);
            File.WriteAllBytes(Path.Combine(baseDir, ".secret.key"), originalSecretKey);
            File.WriteAllBytes(Path.Combine(baseDir, "custom.db"), originalCustomDb);

            var dataMediaDir = Path.Combine(baseDir, "data", "media");
            var dataLogsDir = Path.Combine(baseDir, "data", "logs");
            Directory.CreateDirectory(dataMediaDir);
            Directory.CreateDirectory(dataLogsDir);

            File.WriteAllBytes(Path.Combine(baseDir, "data", "tracker.db"), originalDbBytes);
            File.WriteAllBytes(Path.Combine(dataMediaDir, "test-cover.webp"), originalCoverBytes);
            File.WriteAllBytes(Path.Combine(dataLogsDir, "app.log"), originalLogBytes);

            // --- 2. Seed update payload zip (contains new files + accidental protected files) ---
            var newBinaryBytes = Encoding.UTF8.GetBytes("NEW_BINARY_v2.0.0_SUPER_FAST");
            var newNativeSoBytes = Encoding.UTF8.GetBytes("LIBE_SQLITE3_SO_NATIVE_BINARY");
            var newIndexHtml = Encoding.UTF8.GetBytes("<!doctype html><html><body>New UI</body></html>");
            var newAppJs = Encoding.UTF8.GetBytes("console.log('new bundle');");

            File.WriteAllBytes(Path.Combine(zipSourceDir, "Tsundoku"), newBinaryBytes);
            File.WriteAllBytes(Path.Combine(zipSourceDir, "libe_sqlite3.so"), newNativeSoBytes);

            var newWwwroot = Path.Combine(zipSourceDir, "wwwroot", "assets");
            Directory.CreateDirectory(newWwwroot);
            File.WriteAllBytes(Path.Combine(zipSourceDir, "wwwroot", "index.html"), newIndexHtml);
            File.WriteAllBytes(Path.Combine(newWwwroot, "new.js"), newAppJs);

            // Payload accidentally contains user-owned protected files:
            var maliciousPayload = Encoding.UTF8.GetBytes("CORRUPTED_OVERWRITTEN_PAYLOAD");
            File.WriteAllBytes(Path.Combine(zipSourceDir, "storage.json"), maliciousPayload);
            File.WriteAllBytes(Path.Combine(zipSourceDir, ".secret.key"), maliciousPayload);
            File.WriteAllBytes(Path.Combine(zipSourceDir, "custom.db"), maliciousPayload);

            var payloadDataMedia = Path.Combine(zipSourceDir, "data", "media");
            Directory.CreateDirectory(payloadDataMedia);
            File.WriteAllBytes(Path.Combine(zipSourceDir, "data", "tracker.db"), maliciousPayload);
            File.WriteAllBytes(Path.Combine(payloadDataMedia, "test-cover.webp"), maliciousPayload);

            ZipFile.CreateFromDirectory(zipSourceDir, zipPath);

            // --- 3. Execute update ---
            UpdatePayloadApplier.ApplyZip(zipPath, baseDir, isWindows: false);

            // --- 4. Assert binaries and wwwroot are updated ---
            Assert.Equal(newBinaryBytes, File.ReadAllBytes(Path.Combine(baseDir, "Tsundoku")));
            Assert.Equal(newNativeSoBytes, File.ReadAllBytes(Path.Combine(baseDir, "libe_sqlite3.so")));
            Assert.Equal(newIndexHtml, File.ReadAllBytes(Path.Combine(baseDir, "wwwroot", "index.html")));
            Assert.Equal(newAppJs, File.ReadAllBytes(Path.Combine(baseDir, "wwwroot", "assets", "new.js")));
            Assert.False(File.Exists(Path.Combine(baseDir, "wwwroot", "assets", "old.js")), "Old asset chunk in wwwroot must be deleted");

            // --- 5. Assert user data, db and config remain 100% byte-for-byte identical ---
            Assert.Equal(originalStorageBytes, File.ReadAllBytes(Path.Combine(baseDir, "storage.json")));
            Assert.Equal(originalSecretKey, File.ReadAllBytes(Path.Combine(baseDir, ".secret.key")));
            Assert.Equal(originalDbBytes, File.ReadAllBytes(Path.Combine(baseDir, "data", "tracker.db")));
            Assert.Equal(originalCoverBytes, File.ReadAllBytes(Path.Combine(dataMediaDir, "test-cover.webp")));
            Assert.Equal(originalLogBytes, File.ReadAllBytes(Path.Combine(dataLogsDir, "app.log")));
            Assert.Equal(originalCustomDb, File.ReadAllBytes(Path.Combine(baseDir, "custom.db")));
        }
        finally
        {
            if (Directory.Exists(baseDir)) Directory.Delete(baseDir, recursive: true);
            if (Directory.Exists(zipSourceDir)) Directory.Delete(zipSourceDir, recursive: true);
            if (File.Exists(zipPath)) File.Delete(zipPath);
        }
    }

    [Fact]
    public void Apply_WindowsExecutable_RenamesOldAndCopiesNew()
    {
        var testId = Guid.NewGuid().ToString("N");
        var baseDir = Path.Combine(Path.GetTempPath(), $"update_win_base_{testId}");
        var extractedDir = Path.Combine(Path.GetTempPath(), $"update_win_ext_{testId}");

        try
        {
            Directory.CreateDirectory(baseDir);
            Directory.CreateDirectory(extractedDir);

            var oldExeBytes = Encoding.UTF8.GetBytes("OLD_WINDOWS_EXE_v1");
            var newExeBytes = Encoding.UTF8.GetBytes("NEW_WINDOWS_EXE_v2");

            File.WriteAllBytes(Path.Combine(baseDir, "Tsundoku.exe"), oldExeBytes);
            File.WriteAllBytes(Path.Combine(extractedDir, "Tsundoku.exe"), newExeBytes);

            UpdatePayloadApplier.Apply(extractedDir, baseDir, isWindows: true);

            Assert.Equal(newExeBytes, File.ReadAllBytes(Path.Combine(baseDir, "Tsundoku.exe")));
            Assert.True(File.Exists(Path.Combine(baseDir, "Tsundoku.exe.old")));
            Assert.Equal(oldExeBytes, File.ReadAllBytes(Path.Combine(baseDir, "Tsundoku.exe.old")));

            // A second update cleans up the old .exe.old
            var v3ExeBytes = Encoding.UTF8.GetBytes("NEW_WINDOWS_EXE_v3");
            File.WriteAllBytes(Path.Combine(extractedDir, "Tsundoku.exe"), v3ExeBytes);

            UpdatePayloadApplier.Apply(extractedDir, baseDir, isWindows: true);

            Assert.Equal(v3ExeBytes, File.ReadAllBytes(Path.Combine(baseDir, "Tsundoku.exe")));
            Assert.Equal(newExeBytes, File.ReadAllBytes(Path.Combine(baseDir, "Tsundoku.exe.old")));
        }
        finally
        {
            if (Directory.Exists(baseDir)) Directory.Delete(baseDir, recursive: true);
            if (Directory.Exists(extractedDir)) Directory.Delete(extractedDir, recursive: true);
        }
    }
}
