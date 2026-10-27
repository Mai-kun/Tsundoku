using FluentAssertions;
using MediaTracker.Server.Infrastructure.Security;
using MediaTracker.Server.Infrastructure.Storage;
using Xunit;

namespace MediaTracker.Tests;

public class EncryptionServiceTests
{
    [Fact]
    public void Encryption_RoundTrip_ShouldWork()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        var appPaths = new AppPaths(tempDir, isDevelopment: true);
        var service = new EncryptionService(appPaths);
        var original = "test-string";
        var encrypted = service.Encrypt(original);
        var decrypted = service.Decrypt(encrypted);
        decrypted.Should().Be(original);
    }

    [Fact]
    public void Encryption_EmptyString_ShouldReturnEmpty()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        var appPaths = new AppPaths(tempDir, isDevelopment: true);
        var service = new EncryptionService(appPaths);
        var original = "";
        var encrypted = service.Encrypt(original);
        encrypted.Should().Be(original);
    }

    [Fact]
    public void Decrypt_InvalidCiphertext_ShouldReturnNull()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(tempDir);
        var appPaths = new AppPaths(tempDir, isDevelopment: true);
        var service = new EncryptionService(appPaths);
        var decrypted = service.Decrypt("invalid-ciphertext");
        decrypted.Should().BeNull();
    }
}
