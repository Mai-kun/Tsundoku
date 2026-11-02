using MediaTracker.Server.Infrastructure.ExternalApis.Offline;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class UniversalOfflineMetadataProvider : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "offline",
        Name: "Offline Database",
        Description: "Локальная база метаданных (offline)",
        MediaTypes: ["anime", "movie", "tvshow", "game"],
        BaseAddress: "http://127.0.0.1/",
        IsDefault: false,
        Priority: 0,
        Aliases: ["offline_anime", "offline_db"]);

    private readonly OfflineDatabaseManager _dbManager;
    private readonly ILogger<UniversalOfflineMetadataProvider>? _logger;
    private readonly string? _targetType;

    public UniversalOfflineMetadataProvider(
        OfflineDatabaseManager? dbManager = null,
        AppPaths? appPaths = null,
        ILogger<UniversalOfflineMetadataProvider>? logger = null,
        [ServiceKey] string? serviceKey = null) : base(Source)
    {
        _dbManager = dbManager ?? new OfflineDatabaseManager(appPaths);
        _logger = logger;

        if (!string.IsNullOrEmpty(serviceKey) && serviceKey.Contains(':'))
        {
            _targetType = serviceKey.Split(':')[0];
        }
    }

    public bool IsDatabaseAvailable => _dbManager.HasAnyDatabase;
    public OfflineDatabaseManager DatabaseManager => _dbManager;

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        return await _dbManager.ExecuteSearchAsync(_targetType, query, 10, ct);
    }

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, string? type, CancellationToken ct)
    {
        return await _dbManager.ExecuteSearchAsync(type ?? _targetType, query, 10, ct);
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        return await _dbManager.GetDetailsAsync(externalId, title, _targetType, ct);
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, string? type, CancellationToken ct)
    {
        return await _dbManager.GetDetailsAsync(externalId, title, type ?? _targetType, ct);
    }

    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        return await _dbManager.TestConnectionAsync(ct);
    }
}
