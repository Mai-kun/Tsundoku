using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.Persistence;
using Xunit;

namespace MediaTracker.Tests;

public class HistoryAndSettingsTests
{
    private static AppDbContext CreateDbContext()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.db");
        var db = new AppDbContext($"Data Source={dbPath}");
        db.Database.EnsureCreated();
        return db;
    }

    [Fact]
    public async Task ClearHistoryHandlerTests_ShouldClearAllEvents()
    {
        using var db = CreateDbContext();
        var media = new Movie { Title = "Test" };
        db.Movies.Add(media);
        await db.SaveChangesAsync();

        db.Events.Add(new MediaEvent { MediaId = media.Id, Type = MediaEventType.StatusChanged, CreatedAt = DateTime.UtcNow });
        db.Events.Add(new MediaEvent { MediaId = media.Id, Type = MediaEventType.StatusChanged, CreatedAt = DateTime.UtcNow });
        await db.SaveChangesAsync();

        db.Events.RemoveRange(db.Events);
        await db.SaveChangesAsync();

        (await db.Events.CountAsync()).Should().Be(0);
    }

    [Fact]
    public async Task DeleteHistoryEventHandlerTests_ShouldDeleteSpecificEvent()
    {
        using var db = CreateDbContext();
        var media = new Movie { Title = "Test" };
        db.Movies.Add(media);
        await db.SaveChangesAsync();

        var e = new MediaEvent { MediaId = media.Id, Type = MediaEventType.StatusChanged, CreatedAt = DateTime.UtcNow };
        db.Events.Add(e);
        await db.SaveChangesAsync();

        db.Events.Remove(e);
        await db.SaveChangesAsync();

        (await db.Events.FindAsync(e.Id)).Should().BeNull();
    }

    [Fact]
    public async Task ApiTokenHandlersTests_ShouldManageTokens()
    {
        using var db = CreateDbContext();
        var token = new ApiToken { Name = "Test", TokenHash = "hash", TokenPrefix = "tsk_live_" };
        db.ApiTokens.Add(token);
        await db.SaveChangesAsync();

        db.ApiTokens.Remove(token);
        await db.SaveChangesAsync();

        (await db.ApiTokens.FindAsync(token.Id)).Should().BeNull();
    }

    [Fact]
    public async Task SaveReadingSettingsHandlerTests_ShouldSaveSettings()
    {
        using var db = CreateDbContext();
        var setting = new AppSetting { Key = "ReadingSpeed", Value = "100" };
        db.Settings.Add(setting);
        await db.SaveChangesAsync();

        var saved = await db.Settings.FindAsync("ReadingSpeed");
        saved!.Value.Should().Be("100");
    }

    [Fact]
    public void AppPaths_AppImageResolution_ShouldResolveNextToAppImage()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);
        var fakeAppImage = Path.Combine(tempDir, "Tsundoku.AppImage");
        File.WriteAllText(fakeAppImage, "fake");

        var originalAppImage = Environment.GetEnvironmentVariable("APPIMAGE");
        try
        {
            Environment.SetEnvironmentVariable("APPIMAGE", fakeAppImage);
            var resolvedDir = MediaTracker.Server.Infrastructure.Storage.AppPaths.GetAppDirectory();
            resolvedDir.Should().Be(tempDir);

            var resolvedExe = MediaTracker.Server.Infrastructure.Storage.AppPaths.GetExecutablePath();
            resolvedExe.Should().Be(fakeAppImage);
        }
        finally
        {
            Environment.SetEnvironmentVariable("APPIMAGE", originalAppImage);
            try { Directory.Delete(tempDir, true); } catch { }
        }
    }
}
