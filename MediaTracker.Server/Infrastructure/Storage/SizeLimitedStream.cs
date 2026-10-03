namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class OversizedCoverException(string message) : IOException(message);

/// <summary>
/// Read-only wrapper that throws once more than <see cref="limit"/> bytes have been pulled.
/// Guards against a remote server that omits Content-Length (chunked transfer) and would otherwise
/// let an unbounded body into the image decoder.
/// </summary>
internal sealed class SizeLimitedStream(Stream inner, long limit) : Stream
{
    private long _consumed;

    public override bool CanRead => true;

    public override bool CanSeek => false;

    public override bool CanWrite => false;

    public override long Length => throw new NotSupportedException();

    public override long Position
    {
        get => _consumed;
        set => throw new NotSupportedException();
    }

    public override int Read(byte[] buffer, int offset, int count)
    {
        var allowed = (int)Math.Min(count, limit - _consumed);
        if (allowed <= 0)
        {
            throw new OversizedCoverException($"Cover image exceeded the {limit} byte limit.");
        }

        var read = inner.Read(buffer, offset, allowed);
        _consumed += read;
        return read;
    }

    public override int Read(Span<byte> buffer)
    {
        var allowed = (int)Math.Min(buffer.Length, limit - _consumed);
        if (allowed <= 0)
        {
            throw new OversizedCoverException($"Cover image exceeded the {limit} byte limit.");
        }

        var read = inner.Read(buffer[..allowed]);
        _consumed += read;
        return read;
    }

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        var allowed = (int)Math.Min(count, limit - _consumed);
        if (allowed <= 0)
        {
            throw new OversizedCoverException($"Cover image exceeded the {limit} byte limit.");
        }

        var read = await inner.ReadAsync(buffer.AsMemory(offset, allowed), cancellationToken);
        _consumed += read;
        return read;
    }

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        var allowed = (int)Math.Min(buffer.Length, limit - _consumed);
        if (allowed <= 0)
        {
            throw new OversizedCoverException($"Cover image exceeded the {limit} byte limit.");
        }

        var read = await inner.ReadAsync(buffer[..allowed], cancellationToken);
        _consumed += read;
        return read;
    }

    public override void Flush()
    {
    }

    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

    public override void SetLength(long value) => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            inner.Dispose();
        }

        base.Dispose(disposing);
    }
}
