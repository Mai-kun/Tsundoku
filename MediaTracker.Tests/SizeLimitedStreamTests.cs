using FluentAssertions;
using MediaTracker.Server.Infrastructure.Storage;
using Xunit;

namespace MediaTracker.Tests;

public class SizeLimitedStreamTests
{
    [Fact]
    public void Read_ShouldReturnData_UnderLimit()
    {
        using var inner = new MemoryStream(Enumerable.Range(0, 100).Select(i => (byte)(i % 251)).ToArray());
        using var stream = new SizeLimitedStream(inner, 1000);
        var buffer = new byte[100];

        stream.Read(buffer, 0, 100).Should().Be(100);
        buffer[0].Should().Be(0);

        stream.CanRead.Should().BeTrue();
        stream.CanSeek.Should().BeFalse();
        stream.CanWrite.Should().BeFalse();
        stream.Position.Should().Be(100);
    }

    [Fact]
    public void Read_ShouldThrow_WhenLimitBreached()
    {
        using var inner = new MemoryStream(new byte[100]);
        using var stream = new SizeLimitedStream(inner, 50);
        var buffer = new byte[200];

        stream.Read(buffer, 0, 60).Should().Be(50);

        var act = () => stream.Read(buffer, 0, 10);
        act.Should().Throw<OversizedCoverException>().WithMessage("*50*");
    }

    [Fact]
    public void ReadSpanAndLengthAndSeek_ShouldThrowOrWork()
    {
        using var inner = new MemoryStream(new byte[10]);
        using var stream = new SizeLimitedStream(inner, 5);

        stream.Read(new Span<byte>(new byte[10])[..5]).Should().Be(5);
        stream.Position.Should().Be(5);

        // the whole window was consumed: the next pull is over the limit
        var exhausted = () => stream.Read(new Span<byte>(new byte[10]));
        exhausted.Should().Throw<OversizedCoverException>();

        ((Action)(() => _ = stream.Length)).Should().Throw<NotSupportedException>();
        ((Action)(() => stream.Position = 0)).Should().Throw<NotSupportedException>();
        ((Action)(() => stream.Seek(0, SeekOrigin.Begin))).Should().Throw<NotSupportedException>();
        ((Action)(() => stream.SetLength(0))).Should().Throw<NotSupportedException>();
        ((Action)(() => stream.Write([1, 2], 0, 2))).Should().Throw<NotSupportedException>();
        stream.Flush();
        stream.Position.Should().Be(5);
    }

    [Fact]
    public async Task ReadAsync_ShouldReturnDataAndDisposeInner()
    {
        var inner = new MemoryStream(new byte[20]);
        using (var stream = new SizeLimitedStream(inner, 100))
        {
            (await stream.ReadAsync(new Memory<byte>(new byte[20]), CancellationToken.None)).Should().Be(20);

            var buffer = new byte[30];
            (await stream.ReadAsync(buffer, 0, 30, CancellationToken.None)).Should().Be(0);
        }
        // Dispose forwards to the inner stream
        inner.CanRead.Should().BeFalse();
    }
}
