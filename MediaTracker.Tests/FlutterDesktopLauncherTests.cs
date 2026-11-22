using FluentAssertions;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Infrastructure.Desktop;
using Xunit;

namespace MediaTracker.Tests;

public class FlutterDesktopLauncherTests
{
    [Fact]
    public void CommandLineOptions_ShouldParseNoUiAndWebFlags()
    {
        var opts1 = CommandLineOptions.Parse(["--no-ui"]);
        opts1.StartMinimized.Should().BeTrue();
        opts1.PreferWebBrowser.Should().BeFalse();

        var opts2 = CommandLineOptions.Parse(["--no-browser"]);
        opts2.StartMinimized.Should().BeTrue();
        opts2.PreferWebBrowser.Should().BeFalse();

        var opts3 = CommandLineOptions.Parse(["--web"]);
        opts3.PreferWebBrowser.Should().BeTrue();
        opts3.StartMinimized.Should().BeFalse();

        var opts4 = CommandLineOptions.Parse(["--no-ui", "--web", "--port", "5099"]);
        opts4.StartMinimized.Should().BeTrue();
        opts4.PreferWebBrowser.Should().BeTrue();
        opts4.Port.Should().Be(5099);
    }

    [Fact]
    public void FindFlutterUiBinary_ShouldResolveInAdjacentUiFolder()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_test_ui_" + Guid.NewGuid());
        var uiDir = Path.Combine(tempDir, "ui");
        Directory.CreateDirectory(uiDir);

        try
        {
            var binaryName = OperatingSystem.IsWindows() ? "tsundoku_flutter.exe" : "tsundoku_flutter";
            var fakeBinaryPath = Path.Combine(uiDir, binaryName);
            File.WriteAllText(fakeBinaryPath, "#!/bin/sh\necho ok");

            var resolved = BrowserLauncher.FindFlutterUiBinary(baseDir: tempDir);
            resolved.Should().NotBeNull();
            resolved.Should().Be(Path.GetFullPath(fakeBinaryPath));
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public void FindFlutterUiBinary_ShouldResolveInAppImageStructure()
    {
        var appDir = Path.Combine(Path.GetTempPath(), "tsundoku_appdir_" + Guid.NewGuid());
        var binDir = Path.Combine(appDir, "bin");
        var uiDir = Path.Combine(appDir, "ui");
        Directory.CreateDirectory(binDir);
        Directory.CreateDirectory(uiDir);

        try
        {
            var binaryName = OperatingSystem.IsWindows() ? "tsundoku_flutter.exe" : "tsundoku_flutter";
            var fakeBinaryPath = Path.Combine(uiDir, binaryName);
            File.WriteAllText(fakeBinaryPath, "#!/bin/sh\necho ok");

            // BaseDir is $HERE/bin, UI is in $HERE/ui
            var resolved = BrowserLauncher.FindFlutterUiBinary(baseDir: binDir, contentRoot: appDir);
            resolved.Should().NotBeNull();
            resolved.Should().Be(Path.GetFullPath(fakeBinaryPath));
        }
        finally
        {
            if (Directory.Exists(appDir))
            {
                Directory.Delete(appDir, recursive: true);
            }
        }
    }

    [Fact]
    public void FindFlutterUiBinary_ShouldReturnNullWhenUiMissing()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_empty_" + Guid.NewGuid());
        Directory.CreateDirectory(tempDir);

        try
        {
            var resolved = BrowserLauncher.FindFlutterUiBinary(baseDir: tempDir, contentRoot: tempDir);
            resolved.Should().BeNull();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public void OpenUrl_ShouldGracefullyFallbackToHeadlessWhenUiMissing()
    {
        // When not in web mode and UI binary is missing, OpenUrl must not throw or crash
        BrowserLauncher.PreferWebBrowser = false;

        var act = () => BrowserLauncher.OpenUrl("http://127.0.0.1:5099");
        act.Should().NotThrow();
    }
}
