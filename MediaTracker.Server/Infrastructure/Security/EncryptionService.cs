using System.Buffers;
using System.Security.Cryptography;
using System.Text;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Infrastructure.Security;

public interface IEncryptionService
{
    string Encrypt(string plainText);
    string? Decrypt(string cipherText);
}

public sealed class EncryptionService : IEncryptionService
{
    private readonly byte[] _key;

    public EncryptionService(AppPaths appPaths)
    {
        Directory.CreateDirectory(appPaths.DataDirectory);
        var keyFilePath = Path.Combine(appPaths.DataDirectory, ".secret.key");

        if (File.Exists(keyFilePath))
        {
            try
            {
                var bytes = File.ReadAllBytes(keyFilePath);
                if (bytes.Length == 32)
                {
                    _key = bytes;
                    return;
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Fallback to regenerating key if existing key is unreadable
            }
        }

        _key = new byte[32];
        RandomNumberGenerator.Fill(_key);
        try
        {
            File.WriteAllBytes(keyFilePath, _key);
            if (OperatingSystem.IsWindows())
            {
                File.SetAttributes(keyFilePath, FileAttributes.Hidden);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // If filesystem write fails, key remains in memory for the process lifetime
        }
    }

    public string Encrypt(string plainText)
    {
        if (string.IsNullOrEmpty(plainText))
        {
            return string.Empty;
        }

        var plainByteCount = Encoding.UTF8.GetByteCount(plainText);
        var nonceSize = AesGcm.NonceByteSizes.MaxSize;
        var tagSize = AesGcm.TagByteSizes.MaxSize;
        var totalLength = nonceSize + tagSize + plainByteCount;

        var result = new byte[totalLength];
        var nonceSpan = result.AsSpan(0, nonceSize);
        var tagSpan = result.AsSpan(nonceSize, tagSize);
        var cipherSpan = result.AsSpan(nonceSize + tagSize, plainByteCount);

        RandomNumberGenerator.Fill(nonceSpan);

        byte[]? rentedPlain = null;
        Span<byte> plainSpan = plainByteCount <= 512
            ? stackalloc byte[plainByteCount]
            : (rentedPlain = ArrayPool<byte>.Shared.Rent(plainByteCount)).AsSpan(0, plainByteCount);

        try
        {
            Encoding.UTF8.GetBytes(plainText, plainSpan);
            using var aesGcm = new AesGcm(_key, tagSize);
            aesGcm.Encrypt(nonceSpan, plainSpan, cipherSpan, tagSpan);

            return Convert.ToBase64String(result);
        }
        finally
        {
            if (rentedPlain is not null)
            {
                ArrayPool<byte>.Shared.Return(rentedPlain);
            }
        }
    }

    public string? Decrypt(string cipherText)
    {
        if (string.IsNullOrWhiteSpace(cipherText))
        {
            return null;
        }

        try
        {
            var data = Convert.FromBase64String(cipherText);
            var nonceSize = AesGcm.NonceByteSizes.MaxSize;
            var tagSize = AesGcm.TagByteSizes.MaxSize;

            if (data.Length < nonceSize + tagSize)
            {
                return null;
            }

            var nonce = data.AsSpan(0, nonceSize);
            var tag = data.AsSpan(nonceSize, tagSize);
            var cipherBytes = data.AsSpan(nonceSize + tagSize);

            byte[]? rentedPlain = null;
            Span<byte> plainSpan = cipherBytes.Length <= 512
                ? stackalloc byte[cipherBytes.Length]
                : (rentedPlain = ArrayPool<byte>.Shared.Rent(cipherBytes.Length)).AsSpan(0, cipherBytes.Length);

            try
            {
                using var aesGcm = new AesGcm(_key, tagSize);
                aesGcm.Decrypt(nonce, cipherBytes, tag, plainSpan);
                return Encoding.UTF8.GetString(plainSpan);
            }
            finally
            {
                if (rentedPlain is not null)
                {
                    ArrayPool<byte>.Shared.Return(rentedPlain);
                }
            }
        }
        catch (CryptographicException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
