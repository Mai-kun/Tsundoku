using BenchmarkDotNet.Attributes;
using MediaTracker.Benchmarks.Data;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.Import.Parsers;

namespace MediaTracker.Benchmarks;

[MemoryDiagnoser]
[ShortRunJob]
public class ParsersBenchmarks
{
    private string _mangalibJson = null!;
    private string _sampleCsv = null!;

    [GlobalSetup]
    public void Setup()
    {
        _mangalibJson = BenchmarkDataGenerator.GenerateMangalib100Json();
        _sampleCsv = BenchmarkDataGenerator.GenerateCsv100Rows();
    }

    [Benchmark]
    public IReadOnlyList<ParsedMediaItemDto> ParseMangalibJson()
    {
        return MangalibParser.Parse(_mangalibJson);
    }

    [Benchmark]
    public IReadOnlyList<Dictionary<string, string>> ReadAnyRecordsCsv()
    {
        return CsvHelperMini.ReadAnyRecords(_sampleCsv);
    }
}
