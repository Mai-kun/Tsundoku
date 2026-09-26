using System.Security.Cryptography;
using System.Text;
using MediaTracker.Server.Services.Storage;

namespace MediaTracker.Server.Services.Security;

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
            catch
            {
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
        catch
        {
        }
    }

    public string Encrypt(string plainText)
    {
        if (string.IsNullOrEmpty(plainText))
        {
            return string.Empty;
        }

        var nonce = new byte[AesGcm.NonceByteSizes.MaxSize];
        RandomNumberGenerator.Fill(nonce);

        var plainBytes = Encoding.UTF8.GetBytes(plainText);
        var cipherBytes = new byte[plainBytes.Length];
        var tag = new byte[AesGcm.TagByteSizes.MaxSize];

        using var aesGcm = new AesGcm(_key, AesGcm.TagByteSizes.MaxSize);
        aesGcm.Encrypt(nonce, plainBytes, cipherBytes, tag);

        var result = new byte[nonce.Length + tag.Length + cipherBytes.Length];
        Buffer.BlockCopy(nonce, 0, result, 0, nonce.Length);
        Buffer.BlockCopy(tag, 0, result, nonce.Length, tag.Length);
        Buffer.BlockCopy(cipherBytes, 0, result, nonce.Length + tag.Length, cipherBytes.Length);

        return Convert.ToBase64String(result);
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

            var nonce = new byte[nonceSize];
            var tag = new byte[tagSize];
            var cipherBytes = new byte[data.Length - nonceSize - tagSize];

            Buffer.BlockCopy(data, 0, nonce, 0, nonceSize);
            Buffer.BlockCopy(data, nonceSize, tag, 0, tagSize);
            Buffer.BlockCopy(data, nonceSize + tagSize, cipherBytes, 0, cipherBytes.Length);

            var plainBytes = new byte[cipherBytes.Length];
            using var aesGcm = new AesGcm(_key, tagSize);
            aesGcm.Decrypt(nonce, cipherBytes, tag, plainBytes);

            return Encoding.UTF8.GetString(plainBytes);
        }
        catch
        {
            return null;
        }
    }
}
