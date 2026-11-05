using System.Text;
using System.Text.Json;

using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

/// <summary>
/// Genre registry loaded from <c>Resources/genres-dictionary.json</c> (embedded, AOT-safe) with an
/// optional external override at <c>data/dictionaries/genres.json</c> so new genres, synonyms and
/// Russian names can be added by hand without a rebuild.
///
/// Each entry: canonical key -> { ru, en, isGenre, aliases }. <see cref="IsKnownGenre"/> accepts
/// anything registered; <see cref="IsPrimaryGenre"/> only entries flagged <c>isGenre</c> — offline
/// dumps carry hundreds of story tropes ("aim for the top", "bdsm") that must stay out of the
/// Genres column, and <see cref="ToRussian"/> returns the display name for the UI.
/// </summary>
public static class GenreNormalizer
{
    private sealed record GenreEntry(string Ru, string En, bool IsGenre, IReadOnlyList<string> Aliases);

    private const string EmbeddedResourceName = "MediaTracker.Server.Resources.genres-dictionary.json";
    private const string ExternalOverrideFolder = "data/dictionaries";
    private const string DictionaryFileName = "genres-dictionary.json";

    private static readonly Lazy<Dictionary<string, string>> LazyAliases = new(LoadAliases);
    private static readonly Lazy<Dictionary<string, GenreEntry>> LazyEntries = new(LoadEntries);

    private static Dictionary<string, GenreEntry> Entries => LazyEntries.Value;
    private static Dictionary<string, string> Aliases => LazyAliases.Value;

    public static string Normalize(string rawGenre)
    {
        var value = rawGenre.Trim();
        if (value.Length == 0)
        {
            return value;
        }

        var key = BuildLookupKey(value);
        // The canonical English name keeps the registry's casing ("Action", not the lowercase
        // dictionary key) — stored genres stay readable alongside legacy rows.
        return Aliases.TryGetValue(key, out var canonical) && Entries.TryGetValue(canonical, out var entry)
            ? entry.En
            : value;
    }

    /// <summary>True when the raw tag resolves to any registered entry (genre or format).</summary>
    public static bool IsKnownGenre(string? rawGenre) => Resolve(rawGenre) is not null;

    /// <summary>
    /// True when the raw tag resolves to an entry flagged <c>isGenre</c> — the filter that keeps
    /// story tropes out of the Genres column during offline imports and cleanups.
    /// </summary>
    public static bool IsPrimaryGenre(string? rawGenre) =>
        Resolve(rawGenre) is { } entry && Entries.GetValueOrDefault(entry)?.IsGenre is true;

    /// <summary>The Russian display name for a registered tag; falls back to the raw value.</summary>
    public static string ToRussian(string rawTag)
    {
        var value = rawTag.Trim();
        return Resolve(value) is { } entry && Entries.TryGetValue(entry, out var genre)
            ? genre.Ru
            : value;
    }

    private static string? Resolve(string? rawTag)
    {
        var value = rawTag?.Trim() ?? string.Empty;
        return value.Length == 0 ? null : Aliases.GetValueOrDefault(BuildLookupKey(value));
    }

    internal static string BuildLookupKey(string value)
    {
        var sb = new StringBuilder(value.Length);
        var inWhitespace = true;
        for (var i = 0; i < value.Length; i++)
        {
            var ch = value[i];
            if (ch is ' ' or '-' or '\t' or '\r' or '\n')
            {
                if (!inWhitespace)
                {
                    sb.Append(' ');
                    inWhitespace = true;
                }
            }
            else
            {
                sb.Append(char.ToLowerInvariant(ch));
                inWhitespace = false;
            }
        }

        if (sb.Length > 0 && sb[^1] == ' ')
        {
            sb.Length--;
        }

        return sb.ToString();
    }

    public static IEnumerable<string> ExtractGenres(string? genresRaw)
    {
        if (string.IsNullOrWhiteSpace(genresRaw)) yield break;
        var raw = genresRaw.Trim();
        if (raw.StartsWith('[') && raw.EndsWith(']'))
        {
            List<string>? list = null;
            try
            {
                list = JsonSerializer.Deserialize(raw, AppJsonSerializerContext.Default.ListString);
            }
            catch
            {
                // Fall back to delimiter-based splitting if not valid JSON
            }

            if (list != null)
            {
                foreach (var g in list)
                {
                    if (!string.IsNullOrWhiteSpace(g))
                    {
                        var trimmed = g.Trim().Trim('"', '\'');
                        if (!string.IsNullOrWhiteSpace(trimmed))
                        {
                            yield return trimmed;
                        }
                    }
                }
                yield break;
            }
        }

        var parts = raw.Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var part in parts)
        {
            var cleaned = part.Trim().Trim('[', ']', '"', '\'', ' ');
            if (!string.IsNullOrWhiteSpace(cleaned))
            {
                yield return cleaned;
            }
        }
    }

    /// <summary>Normalizes each entry, drops blanks and dedupes (case-insensitive), preserving order.</summary>
    public static IReadOnlyList<string> NormalizeList(IEnumerable<string>? rawGenres)
    {
        if (rawGenres is null)
        {
            return [];
        }

        return rawGenres
            .Select(Normalize)
            .Where(g => !string.IsNullOrWhiteSpace(g))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>Splits, normalizes, dedupes and re-joins a genre list; null when nothing remains.</summary>
    public static string? NormalizeToCommaString(IEnumerable<string>? rawGenres)
    {
        var genres = NormalizeList(rawGenres);
        return genres.Count > 0 ? string.Join(", ", genres) : null;
    }

    public static string? NormalizeToCommaString(string? rawCommaSeparated)
    {
        if (string.IsNullOrWhiteSpace(rawCommaSeparated))
        {
            return null;
        }

        return NormalizeToCommaString(ExtractGenres(rawCommaSeparated));
    }

    /// <summary>
    /// Loads the dictionary: the embedded resource first, then merges the user-editable override at
    /// <c>data/dictionaries/genres.json</c> when present (entries with the same key replace the
    /// bundled ones). Returns alias-key -> canonical key plus canonical-key -> entry.
    /// </summary>
    private static (Dictionary<string, string> Aliases, Dictionary<string, GenreEntry> Entries) LoadDictionary()
    {
        Dictionary<string, GenreEntry> entries;
        try
        {
            using var stream = typeof(GenreNormalizer).Assembly.GetManifestResourceStream(EmbeddedResourceName)
                ?? throw new InvalidOperationException($"Embedded resource '{EmbeddedResourceName}' is missing.");
            entries = ParseEntries(stream);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // A broken/missing dictionary must never take the process down; fall back to an empty
            // registry where every tag passes through untouched.
            Console.Error.WriteLine($"[GenreNormalizer] Failed to load the embedded genre dictionary: {ex.Message}");
            return (new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase), new Dictionary<string, GenreEntry>(StringComparer.OrdinalIgnoreCase));
        }

        try
        {
            var overridePath = Path.Combine(AppPaths.GetAppDirectory(), ExternalOverrideFolder, DictionaryFileName);
            if (File.Exists(overridePath))
            {
                using var stream = File.OpenRead(overridePath);
                foreach (var (key, entry) in ParseEntries(stream))
                {
                    entries[key] = entry;
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            Console.Error.WriteLine($"[GenreNormalizer] Ignoring broken external genre dictionary override: {ex.Message}");
        }

        var aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, entry) in entries)
        {
            aliases[key] = key;
            aliases[BuildLookupKey(entry.En)] = key;
            foreach (var alias in entry.Aliases)
            {
                aliases[BuildLookupKey(alias)] = key;
            }
        }

        return (aliases, entries);
    }

    private static Dictionary<string, GenreEntry> ParseEntries(Stream stream)
    {
        using var document = JsonDocument.Parse(stream);
        var result = new Dictionary<string, GenreEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (var property in document.RootElement.EnumerateObject())
        {
            if (property.Value.ValueKind != JsonValueKind.Object) continue;
            var element = property.Value;
            var ru = element.TryGetProperty("ru", out var ruProp) && ruProp.ValueKind == JsonValueKind.String ? ruProp.GetString() ?? property.Name : property.Name;
            var en = element.TryGetProperty("en", out var enProp) && enProp.ValueKind == JsonValueKind.String ? enProp.GetString() ?? property.Name : property.Name;
            var isGenre = !element.TryGetProperty("isGenre", out var genreProp) || genreProp.ValueKind != JsonValueKind.False;
            var aliases = new List<string>();
            if (element.TryGetProperty("aliases", out var aliasesProp) && aliasesProp.ValueKind == JsonValueKind.Array)
            {
                aliases.AddRange(aliasesProp.EnumerateArray()
                    .Where(a => a.ValueKind == JsonValueKind.String)
                    .Select(a => a.GetString()!)
                    .Where(a => !string.IsNullOrWhiteSpace(a)));
            }

            result[property.Name] = new GenreEntry(ru, en, isGenre, aliases);
        }

        return result;
    }

    private static Dictionary<string, string> LoadAliases()
    {
        var (aliases, _) = LoadDictionary();
        return aliases;
    }

    private static Dictionary<string, GenreEntry> LoadEntries()
    {
        var (_, entries) = LoadDictionary();
        return entries;
    }
}
