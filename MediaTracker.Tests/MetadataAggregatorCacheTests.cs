using System.Collections.Frozen;
using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// The aggregator persists each provider's answer under its own {source}:{type}:{query} key, so
/// the "All" cascade reuses whatever a provider already returned, switching between "All" and one
/// source costs zero network calls, and priority/toggle changes take effect immediately without
/// waiting for the cache to expire.
/// </summary>
public sealed class MetadataAggregatorCacheTests : IDisposable
{
    private readonly string _tempDir;
    private readonly SearchCacheService _searchCache;
    private readonly FakePriorityService _priorities = new("provider-a", "provider-b");
    private readonly CountingProvider _providerA = new("provider-a");
    private readonly CountingProvider _providerB = new("provider-b");

    public MetadataAggregatorCacheTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"aggregator-cache-tests-{Guid.NewGuid():N}");
        _searchCache = new SearchCacheService(new AppPaths(_tempDir, isDevelopment: true));
    }

    public void Dispose()
    {
        _searchCache.Dispose();
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    private MetadataAggregatorService CreateAggregator() => new(
        new FakeResolver(_providerA, _providerB),
        _priorities,
        new MemoryCache(new MemoryCacheOptions()),
        NullLogger<MetadataAggregatorService>.Instance,
        searchCache: _searchCache);

    private sealed class CountingProvider(string id) : IMetadataProvider
    {
        private int _searchCalls;

        public int SearchCalls => _searchCalls;

        /// <summary>When true, SearchAsync answers an empty list (a "dry" provider).</summary>
        public bool ReturnsEmpty { get; init; }

        public string Id => id;
        public string Name => id;
        public string Description => string.Empty;
        public IReadOnlyList<string> MediaTypes => ["anime"];
        public bool RequiresApiKey => false;
        public bool OptionalApiKey => false;
        public bool IsDefault => false;
        public bool IsScraper => false;

        public Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
        {
            Interlocked.Increment(ref _searchCalls);
            if (ReturnsEmpty)
            {
                return Task.FromResult<IReadOnlyList<ExternalMediaDto>>([]);
            }

            IReadOnlyList<ExternalMediaDto> results =
            [
                new ExternalMediaDto
                {
                    ExternalId = $"{id}-1",
                    ExternalSource = id,
                    Title = $"{id} result for {query}",
                    Type = "anime",
                },
            ];
            return Task.FromResult(results);
        }

        public Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct) =>
            Task.FromResult<ExternalMediaDto?>(null);

        public Task<IReadOnlyList<ExternalMediaDto>> SearchByCreatorAsync(string creator, CancellationToken ct) =>
            SearchAsync(creator, ct);

        public Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct) =>
            Task.FromResult(new ConnectionTestResult(true, 0, "ok"));
    }

    private sealed class FakeResolver(params CountingProvider[] providers) : IMetadataProviderResolver
    {
        public IMetadataProvider? Resolve(string type, string? source = null) =>
            providers.FirstOrDefault(provider => provider.Id == source);
    }

    private sealed class FakePriorityService(params string[] sources) : ISourcePriorityService
    {
        private IReadOnlyList<string> _current = sources;

        public int Version { get; private set; } = 1;

        public ValueTask<IReadOnlyList<string>> GetPrioritiesAsync(string type, CancellationToken ct) =>
            ValueTask.FromResult(_current);

        public Task<IReadOnlySet<string>> GetDisabledSourcesAsync(CancellationToken ct) =>
            Task.FromResult<IReadOnlySet<string>>(FrozenSet<string>.Empty);

        public Task SetSourceEnabledAsync(string sourceId, bool enabled, CancellationToken ct) => Task.CompletedTask;

        public void InvalidateCache() { }

        /// <summary>Simulates a settings change: the new list applies and the version bumps.</summary>
        public void SetSources(params string[] sources)
        {
            _current = sources;
            Version++;
        }
    }

    [Fact]
    public async Task CascadeSearch_PersistsOneEntryPerProvider()
    {
        var aggregator = CreateAggregator();

        var results = await aggregator.SearchAsync("anime", "noragami", CancellationToken.None);

        results.Should().HaveCount(2);
        results.Select(r => r.ExternalSource).Should().BeEquivalentTo("provider-a", "provider-b");

        var info = await _searchCache.GetInfoAsync();
        info.EntryCount.Should().Be(2);

        (await _searchCache.TryGetAsync(SearchCacheService.BuildKey("provider-a", "anime", "noragami"))).Should().NotBeNull();
        (await _searchCache.TryGetAsync(SearchCacheService.BuildKey("provider-b", "anime", "noragami"))).Should().NotBeNull();
    }

    [Fact]
    public async Task RepeatCascade_AnswersFromPersistentCache_WithoutProviderCalls()
    {
        var first = CreateAggregator();
        await first.SearchAsync("anime", "noragami", CancellationToken.None);

        // A fresh aggregator simulates a process restart: its in-memory cache is empty, so only
        // search_cache.db can answer — and the per-provider entries do.
        var second = CreateAggregator();
        var results = await second.SearchAsync("anime", "noragami", CancellationToken.None);

        results.Should().HaveCount(2);
        _providerA.SearchCalls.Should().Be(1, "provider-a answered only once, the second cascade hit the cache");
        _providerB.SearchCalls.Should().Be(1);
    }

    [Fact]
    public async Task ExplicitSourceSearch_ReusesCascadeEntries()
    {
        var aggregator = CreateAggregator();
        await aggregator.SearchAsync("anime", "noragami", CancellationToken.None);

        var results = await aggregator.SearchSourceAsync("anime", "noragami", "provider-b", CancellationToken.None);

        results.Should().HaveCount(1);
        results[0].ExternalSource.Should().Be("provider-b");
        _providerB.SearchCalls.Should().Be(1, "the explicit-source search served the cascade's cached entry");
    }

    [Fact]
    public async Task PriorityOrToggleChange_TakesEffectImmediately()
    {
        var aggregator = CreateAggregator();
        await aggregator.SearchAsync("anime", "noragami", CancellationToken.None);

        // The user disables provider-b in Settings: the merge now iterates only provider-a, and
        // provider-b is never asked again — the cached entry is simply not consulted.
        _priorities.SetSources("provider-a");

        var results = await aggregator.SearchAsync("anime", "noragami", CancellationToken.None);

        results.Should().HaveCount(1);
        results[0].ExternalSource.Should().Be("provider-a");
        _providerB.SearchCalls.Should().Be(1);
        _providerA.SearchCalls.Should().Be(1, "provider-a's answer is still served from its own cache entry");
    }

    [Fact]
    public async Task BypassCache_RefreshesEntries_AndThenReusesThem()
    {
        var aggregator = CreateAggregator();
        await aggregator.SearchAsync("anime", "noragami", CancellationToken.None);

        var refreshed = await aggregator.SearchAsync("anime", "noragami", CancellationToken.None, bypassCache: true);

        refreshed.Should().HaveCount(2);
        _providerA.SearchCalls.Should().Be(2, "bypass re-fetches and refreshes the entries");
        _providerB.SearchCalls.Should().Be(2);

        var third = CreateAggregator();
        var served = await third.SearchAsync("anime", "noragami", CancellationToken.None);

        served.Should().HaveCount(2);
        _providerA.SearchCalls.Should().Be(2, "the refresh repopulated the entries, the next cascade reuses them");
        _providerB.SearchCalls.Should().Be(2);
    }

    [Fact]
    public async Task EmptyProviderAnswer_IsNotPersisted()
    {
        var provider = new CountingProvider("provider-a") { ReturnsEmpty = true };
        var aggregator = new MetadataAggregatorService(
            new FakeResolver(provider),
            _priorities,
            new MemoryCache(new MemoryCacheOptions()),
            NullLogger<MetadataAggregatorService>.Instance,
            searchCache: _searchCache);

        await aggregator.SearchAsync("anime", "noragami", CancellationToken.None);

        var info = await _searchCache.GetInfoAsync();
        info.EntryCount.Should().Be(0, "a dry search keeps going upstream on the next request");
    }
}
