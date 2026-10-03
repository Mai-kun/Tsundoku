using FluentValidation;
using MediaTracker.Server.Features.External.EnrichMetadata;
using MediaTracker.Server.Features.External.GetExternalDetails;
using MediaTracker.Server.Features.External.GetExternalRelations;
using MediaTracker.Server.Features.External.GetGameAchievements;
using MediaTracker.Server.Features.External.GetGameRecommendations;
using MediaTracker.Server.Features.External.GetGameRelated;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.External.RelinkMedia;
using MediaTracker.Server.Features.External.SearchExternal;
using MediaTracker.Server.Features.External.TranslateText;
using MediaTracker.Server.Features.History.ClearHistory;
using MediaTracker.Server.Features.History.DeleteHistoryEvent;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Logs.ClientLog;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.DeleteMedia;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Features.Media.UpdateStatus;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Features.Settings.GetCategoryOrder;
using MediaTracker.Server.Features.Settings.GetSourcePriority;
using MediaTracker.Server.Features.Settings.SaveCategoryOrder;
using MediaTracker.Server.Features.Settings.SaveSourceKey;
using MediaTracker.Server.Features.Settings.SaveSourcePriority;
using MediaTracker.Server.Features.Settings.TestSource;
using MediaTracker.Server.Features.Settings.ToggleSource;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Features.Volumes.AddVolume;
using MediaTracker.Server.Features.Volumes.DeleteVolume;
using MediaTracker.Server.Features.Volumes.UpdateVolume;
using MediaTracker.Server.Features.Volumes.UpdateVolumeProgress;

namespace MediaTracker.Server.Features;

/// <summary>
/// Registers every vertical slice. The list is explicit on purpose: a slice whose handler is not
/// registered fails at startup, not on the first request that happens to hit it.
/// </summary>
public static class FeatureRegistration
{
    public static IServiceCollection AddFeatures(this IServiceCollection services)
    {
        services.AddValidatorsFromAssemblyContaining<CreateMediaHandler>(
            ServiceLifetime.Scoped,
            includeInternalTypes: true);

        // Media
        services.AddScoped<IGetMediaListHandler, GetMediaListHandler>();
        services.AddScoped<IGetMediaStatsHandler, GetMediaStatsHandler>();
        services.AddScoped<IGetMediaDetailHandler, GetMediaDetailHandler>();
        services.AddScoped<ICreateMediaHandler, CreateMediaHandler>();
        services.AddScoped<IUpdateMediaHandler, UpdateMediaHandler>();
        services.AddScoped<IUpdateStatusHandler, UpdateStatusHandler>();
        services.AddScoped<IUpdateProgressHandler, UpdateProgressHandler>();
        services.AddScoped<IDeleteMediaHandler, DeleteMediaHandler>();

        // Seasons
        services.AddScoped<IUpdateSeasonProgressHandler, UpdateSeasonProgressHandler>();

        // Volumes
        services.AddScoped<IUpdateVolumeProgressHandler, UpdateVolumeProgressHandler>();
        services.AddScoped<IAddVolumeHandler, AddVolumeHandler>();
        services.AddScoped<IUpdateVolumeHandler, UpdateVolumeHandler>();
        services.AddScoped<IDeleteVolumeHandler, DeleteVolumeHandler>();

        // External
        services.AddScoped<ISearchExternalHandler, SearchExternalHandler>();
        services.AddScoped<IGetExternalDetailsHandler, GetExternalDetailsHandler>();
        services.AddScoped<ITranslateTextHandler, TranslateTextHandler>();
        services.AddScoped<IGetGameAchievementsHandler, GetGameAchievementsHandler>();
        services.AddScoped<IGetGameRelatedHandler, GetGameRelatedHandler>();
        services.AddScoped<IGetGameRecommendationsHandler, GetGameRecommendationsHandler>();
        services.AddScoped<IGetExternalRelationsHandler, GetExternalRelationsHandler>();
        services.AddScoped<IRefreshMetadataHandler, RefreshMetadataHandler>();
        services.AddScoped<IRelinkMediaHandler, RelinkMediaHandler>();
        services.AddScoped<IEnrichMetadataHandler, EnrichMetadataHandler>();

        // History
        services.AddScoped<IGetHistoryEventsHandler, GetHistoryEventsHandler>();
        services.AddScoped<IClearHistoryHandler, ClearHistoryHandler>();
        services.AddScoped<IDeleteHistoryEventHandler, DeleteHistoryEventHandler>();

        // System and settings
        services.AddScoped<IGetSourcesHandler, GetSourcesHandler>();
        services.AddScoped<ISaveSourceKeyHandler, SaveSourceKeyHandler>();
        services.AddScoped<IToggleSourceHandler, ToggleSourceHandler>();
        services.AddScoped<ITestSourceHandler, TestSourceHandler>();
        services.AddScoped<IGetCategoryOrderHandler, GetCategoryOrderHandler>();
        services.AddScoped<ISaveCategoryOrderHandler, SaveCategoryOrderHandler>();
        services.AddScoped<IGetSourcePriorityHandler, GetSourcePriorityHandler>();
        services.AddScoped<ISaveSourcePriorityHandler, SaveSourcePriorityHandler>();

        // Logs
        services.AddScoped<IClientLogHandler, ClientLogHandler>();

        return services;
    }
}
