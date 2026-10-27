using FluentAssertions;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

public class ImageStorageServiceTests
{
    [Fact]
    public void DeleteCover_PathTraversal_ShouldNotDelete()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        var appPaths = new AppPaths(tempDir, isDevelopment: true);
        var service = new ImageStorageService(new HttpClient(), appPaths, NullLogger<ImageStorageService>.Instance);

        var secretFile = Path.Combine(tempDir, "secrets.txt");
        File.WriteAllText(secretFile, "secret");

        service.DeleteCover("/covers/../secrets.txt");

        File.Exists(secretFile).Should().BeTrue();
    }
}
