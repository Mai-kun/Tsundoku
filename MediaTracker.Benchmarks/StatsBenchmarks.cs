using BenchmarkDotNet.Attributes;
using MediaTracker.Benchmarks.Data;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaStats;

namespace MediaTracker.Benchmarks;

[MemoryDiagnoser]
[ShortRunJob]
public class StatsBenchmarks
{
    private List<MediaItem> _items = null!;
    private AdvancedStatsDto _advancedStats = null!;

    [GlobalSetup]
    public void Setup()
    {
        _items = BenchmarkDataGenerator.Generate2000Items();
        _advancedStats = AdvancedStatsCalculator.Calculate(_items);
    }

    [Benchmark]
    public AdvancedStatsDto CalculateAdvancedStats()
    {
        return AdvancedStatsCalculator.Calculate(_items);
    }

    [Benchmark]
    public TasteProfileDto CalculateTasteProfile()
    {
        return TasteProfileCalculator.Calculate(_items, _advancedStats);
    }
}
