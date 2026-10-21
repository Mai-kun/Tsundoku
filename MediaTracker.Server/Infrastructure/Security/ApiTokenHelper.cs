using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace MediaTracker.Server.Infrastructure.Security;

public static class ApiTokenHelper
{
    public const string TokenPrefixScheme = "tsk_live_";
    public const int DisplayPrefixLength = 16;

    public static (string RawToken, string TokenPrefix, string TokenHash) GenerateToken()
    {
        var randomBytes = RandomNumberGenerator.GetBytes(32);
        var base64Url = Base64Url.EncodeToString(randomBytes);
        var rawToken = $"{TokenPrefixScheme}{base64Url}";
        var tokenPrefix = rawToken.Length >= DisplayPrefixLength
            ? rawToken[..DisplayPrefixLength]
            : rawToken;
        var tokenHash = ComputeHash(rawToken);

        return (rawToken, tokenPrefix, tokenHash);
    }

    public static string ComputeHash(string token)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(token);
        var bytes = Encoding.UTF8.GetBytes(token);
        var hashBytes = SHA256.HashData(bytes);
        return Convert.ToHexStringLower(hashBytes);
    }
}
