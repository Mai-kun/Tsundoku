using System.Collections.Frozen;

namespace MediaTracker.Server.Features.External.SearchExternal;

/// <summary>The type filter the search box offers. "all" fans out across every supported type.</summary>
public static class SearchTypes
{
    public const string All = "all";

    public static readonly FrozenSet<string> Supported = new[]
    {
        All,
        "game",
        "movie",
        "tvshow",
        "anime",
        "manga",
        "book",
    }.ToFrozenSet(StringComparer.OrdinalIgnoreCase);

    public static string Normalize(string? type) =>
        string.IsNullOrWhiteSpace(type) ? All : type.Trim();

    public static bool IsSupported(string type) => Supported.Contains(type);
}
