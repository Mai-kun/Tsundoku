using BenchmarkDotNet.Attributes;
using MediaTracker.Benchmarks.Data;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Benchmarks;

[MemoryDiagnoser]
[ShortRunJob]
public class EvaluationAndScoringBenchmarks
{
    private List<MediaItem> _items = null!;
    private SmartListQueryDto _query = null!;
    private MediaItem _matchItem = null!;
    private List<ExternalMediaDto> _candidates = null!;
    private List<string> _priorities = null!;
    private List<string> _rawGenres = null!;

    [GlobalSetup]
    public void Setup()
    {
        _items = BenchmarkDataGenerator.Generate2000Items();
        _query = BenchmarkDataGenerator.GenerateComplexSmartListQuery();
        var matchData = BenchmarkDataGenerator.GenerateMatchCandidates();
        _matchItem = matchData.Item;
        _candidates = matchData.Candidates;
        _priorities = matchData.Priorities;
        _rawGenres = BenchmarkDataGenerator.GenerateRawGenresList();
    }

    [Benchmark]
    public IReadOnlyList<MediaItem> EvaluateSmartList()
    {
        return SmartListEvaluator.Evaluate(_items, _query);
    }

    [Benchmark]
    public MatchVerdict EvaluateCandidates()
    {
        return ImportMatchScorer.EvaluateCandidates(_matchItem, _candidates, _priorities);
    }

    [Benchmark]
    public string? NormalizeGenres()
    {
        return GenreNormalizer.NormalizeToCommaString(_rawGenres);
    }
}
