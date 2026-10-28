using System.Diagnostics;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// Base for every provider. The <see cref="MetadataSourceDescriptor"/> is passed directly through the
/// protected constructor (no reflection, no <c>GetProperty("Source")</c>). Each provider declares its
/// own descriptor once and passes it to the base.
/// </summary>
/// <remarks>
/// The descriptor is a constructor argument rather than a static abstract interface member because
/// <c>static abstract</c> makes <see cref="IMetadataProvider"/> unusable as a minimal-API service
/// parameter, which is how SettingsEndpoints enumerates the sources for the settings UI.
/// </remarks>
public abstract class MetadataProviderBase : IMetadataProvider
{
    private readonly MetadataSourceDescriptor _source;

    /// <summary>Pass the provider's declared <see cref="MetadataSourceDescriptor"/> directly, no reflection.</summary>
    protected MetadataProviderBase(MetadataSourceDescriptor source)
    {
        _source = source;
    }

    public string Id => _source.Id;
    public string Name => _source.Name;
    public string Description => _source.Description;
    public IReadOnlyList<string> MediaTypes => _source.MediaTypes;
    public bool RequiresApiKey => _source.RequiresApiKey;
    public bool OptionalApiKey => _source.OptionalApiKey;
    public bool IsDefault => _source.IsDefault;

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
    /// <remarks>
    /// A provider that returns an empty result set when its key is missing (RAWG, TMDb) must override
    /// this — the base probe would report such a silent no-op as a healthy connection. The empty
    /// check below is the second line of defence for any key-requiring provider added without its
    /// own override.
    /// </remarks>
    public virtual async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(5));
            var results = await SearchAsync("test", timeoutCts.Token);
            sw.Stop();

            // A key-requiring provider that asks for a missing key answers with an empty list and no
            // exception, which used to read as "reachable in 0 ms".
            if (_source.RequiresApiKey && results.Count == 0)
            {
                return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                    "The probe search returned no results — check the configured API key");
            }

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
