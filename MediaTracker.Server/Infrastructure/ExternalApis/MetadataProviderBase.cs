using System.Collections.Concurrent;
using System.Diagnostics;
using System.Reflection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// Base for every provider: the six descriptive properties are read straight off the type's
/// <c>static MetadataSourceDescriptor Source</c>, so a provider declares its own metadata once instead
/// of restating it as instance members that could disagree with it.
/// </summary>
/// <remarks>
/// The descriptor is a static member rather than a static abstract interface member because
/// <c>static abstract</c> makes <see cref="IMetadataProvider"/> unusable as a minimal-API service
/// parameter, which is how SettingsEndpoints enumerates the sources for the settings UI.
/// </remarks>
public abstract class MetadataProviderBase : IMetadataProvider
{
    // One reflection read per provider type, not per instance: keyed DI builds a fresh transient for
    // every resolve, so this sits on the hot path of both search and details.
    private static readonly ConcurrentDictionary<Type, MetadataSourceDescriptor> Cache = new();

    private static MetadataSourceDescriptor SourceOf(Type type) =>
        Cache.GetOrAdd(type, t => (MetadataSourceDescriptor)t
            .GetProperty("Source", BindingFlags.Public | BindingFlags.Static)!
            .GetValue(null)!);

    private MetadataSourceDescriptor Source => SourceOf(GetType());

    public string Id => Source.Id;
    public string Name => Source.Name;
    public string Description => Source.Description;
    public IReadOnlyList<string> MediaTypes => Source.MediaTypes;
    public bool RequiresApiKey => Source.RequiresApiKey;
    public bool IsDefault => Source.IsDefault;

    public abstract Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct);
    public abstract Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct);

    /// <summary>
    /// A "works by this studio/author" search. Sources that can ask the upstream API natively
    /// (AniList by studio, the book services by author) override this; every other provider runs a
    /// regular query and keeps only rows whose Studio or Author names the creator, falling back to
    /// the raw answer so a source that never reports creators still shows something.
    /// </summary>
    public virtual async Task<IReadOnlyList<ExternalMediaDto>> SearchByCreatorAsync(string creator, CancellationToken ct)
    {
        var results = await SearchAsync(creator, ct);
        var matches = results.Where(dto => MatchesCreator(dto, creator)).ToList();
        return matches.Count > 0 ? matches : results;
    }

    /// <summary>True when the row's Studio or Author names the creator, in either spelling order.</summary>
    internal static bool MatchesCreator(ExternalMediaDto dto, string creator)
    {
        return NameNamesCreator(dto.Studio, creator) || NameNamesCreator(dto.Author, creator);
    }

    private static bool NameNamesCreator(string? name, string creator)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        var clean = name.Trim();
        return clean.Contains(creator, StringComparison.OrdinalIgnoreCase)
            || creator.Contains(clean, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Reachability probe used by every provider that does not override it.
    ///
    /// This lives on the base class rather than as a default interface method on purpose. C# only
    /// lets a derived class take over a default interface member if it re-lists the interface or the
    /// base redeclares it, so with the default on the interface every provider's own
    /// <c>TestConnectionAsync</c> was silently dead code: the settings screen always ran this probe
    /// instead, which searches for the literal word "test" and reports OK whenever that search comes
    /// back without throwing — even for an API key the provider rejects.
    /// </summary>
    public virtual async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(5));
            _ = await SearchAsync("test", timeoutCts.Token);
            sw.Stop();
            return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                "Таймаут — сервис не отвечает (проверьте доступность из своей сети)");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }
}
