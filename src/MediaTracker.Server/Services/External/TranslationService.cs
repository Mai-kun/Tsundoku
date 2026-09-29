using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Services.External;

public interface ITranslationService
{
    Task<string> TranslateAsync(string text, string targetLanguage, CancellationToken ct = default);
}

public sealed partial class TranslationService(
    IHttpClientFactory httpClientFactory,
    IMemoryCache cache,
    ILogger<TranslationService> logger) : ITranslationService
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromHours(24);
    private static readonly Regex HtmlTagRegex = new("<.*?>", RegexOptions.Compiled);

    public async Task<string> TranslateAsync(string text, string targetLanguage, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        var cleanText = HtmlTagRegex.Replace(text, " ").Trim();
        if (string.IsNullOrWhiteSpace(cleanText))
        {
            return text;
        }

        var target = string.IsNullOrWhiteSpace(targetLanguage) ? "ru" : targetLanguage.Trim().ToLowerInvariant();
        var cacheKey = ComputeCacheKey(target, cleanText);

        if (cache.TryGetValue(cacheKey, out string? cached) && !string.IsNullOrWhiteSpace(cached))
        {
            return cached;
        }

        var client = httpClientFactory.CreateClient("Translation");

        // Strategy 1: Google Dict API
        try
        {
            var googleUrl = $"https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl={Uri.EscapeDataString(target)}&q={Uri.EscapeDataString(cleanText)}";
            using var response = await client.GetAsync(googleUrl, ct);
            if (response.IsSuccessStatusCode)
            {
                await using var stream = await response.Content.ReadAsStreamAsync(ct);
                using var jsonDoc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
                var root = jsonDoc.RootElement;
                string? translated = null;

                if (root.ValueKind == JsonValueKind.Array && root.GetArrayLength() > 0)
                {
                    var first = root[0];
                    if (first.ValueKind == JsonValueKind.Array && first.GetArrayLength() > 0)
                    {
                        translated = first[0].GetString();
                    }
                    else if (first.ValueKind == JsonValueKind.String)
                    {
                        translated = first.GetString();
                    }
                }

                if (!string.IsNullOrWhiteSpace(translated))
                {
                    cache.Set(cacheKey, translated, CacheDuration);
                    return translated;
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "Google translation failed for query, trying fallback");
        }

        // Strategy 2: MyMemory Translate
        try
        {
            var myMemoryUrl = $"https://api.mymemory.translated.net/get?q={Uri.EscapeDataString(cleanText)}&langpair=auto|{Uri.EscapeDataString(target)}";
            using var response = await client.GetAsync(myMemoryUrl, ct);
            if (response.IsSuccessStatusCode)
            {
                await using var stream = await response.Content.ReadAsStreamAsync(ct);
                using var jsonDoc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
                if (jsonDoc.RootElement.TryGetProperty("responseData", out var respData) &&
                    respData.TryGetProperty("translatedText", out var transElem))
                {
                    var translated = transElem.GetString();
                    if (!string.IsNullOrWhiteSpace(translated))
                    {
                        cache.Set(cacheKey, translated, CacheDuration);
                        return translated;
                    }
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "MyMemory translation failed for query");
        }

        return cleanText;
    }

    private static string ComputeCacheKey(string targetLanguage, string text)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        return $"translate:{targetLanguage}:{Convert.ToHexString(hash)[..16]}";
    }
}
