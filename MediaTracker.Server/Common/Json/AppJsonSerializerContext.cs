using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using MediaTracker.Server.Common.Endpoints;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RelinkMedia;
using MediaTracker.Server.Features.External.TranslateText;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Features.Logs.ClientLog;
using MediaTracker.Server.Features.Media.Calendar;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.GetCreatorSummary;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.PendingMatches;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Features.Media.UpdateStatus;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Features.Settings.ApiTokens;
using MediaTracker.Server.Features.Settings.ReadingSettings;
using MediaTracker.Server.Features.Settings.ResetData;
using MediaTracker.Server.Features.Settings.SaveSourceKey;
using MediaTracker.Server.Features.Settings.ToggleSource;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Features.System.Updates;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.SelfChecks;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Json;

/// <summary>
/// Central reflection-free JSON contract for NativeAOT. Every type that crosses a Minimal API
/// boundary, a cached database blob, a settings row, an external provider payload or a typed
/// HttpClient call is registered here; the source generator walks each root type's property graph.
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    PropertyNameCaseInsensitive = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    NumberHandling = JsonNumberHandling.AllowReadingFromString)]
// --- Minimal API: media contract ---
[JsonSerializable(typeof(MediaListDto))]
[JsonSerializable(typeof(MediaDetailDto))]
[JsonSerializable(typeof(IReadOnlyList<MediaListDto>))]
[JsonSerializable(typeof(List<MediaListDto>))]
[JsonSerializable(typeof(IReadOnlyList<MediaDetailDto>))]
[JsonSerializable(typeof(MediaCoverItemDto))]
[JsonSerializable(typeof(List<MediaCoverItemDto>))]
[JsonSerializable(typeof(IReadOnlyList<MediaCoverItemDto>))]
// --- Minimal API: requests ---
[JsonSerializable(typeof(AddCoverRequest))]
[JsonSerializable(typeof(CreateMediaRequest))]
[JsonSerializable(typeof(UpdateMediaRequest))]
[JsonSerializable(typeof(UpdateStatusRequest))]
[JsonSerializable(typeof(UpdateProgressRequest))]
[JsonSerializable(typeof(UpdateSeasonProgressRequest))]
[JsonSerializable(typeof(RefreshMetadataRequest))]
[JsonSerializable(typeof(EnrichMetadataRequest))]
[JsonSerializable(typeof(RelinkMediaRequest))]
[JsonSerializable(typeof(SteamImportRequest))]
[JsonSerializable(typeof(AniListProfileRequest))]
[JsonSerializable(typeof(MangaLibProfileRequest))]
[JsonSerializable(typeof(ResolveMatchRequest))]
[JsonSerializable(typeof(TranslateRequest))]
[JsonSerializable(typeof(ClientLogRequest))]
[JsonSerializable(typeof(ResetDataRequest))]
[JsonSerializable(typeof(StorageRequest))]
[JsonSerializable(typeof(ToggleSourceRequest))]
[JsonSerializable(typeof(UpdateKeyRequest))]
[JsonSerializable(typeof(CreateListRequest))]
[JsonSerializable(typeof(UpdateListRequest))]
[JsonSerializable(typeof(AddMediaToListRequest))]
[JsonSerializable(typeof(CreateApiTokenRequest))]
// --- Minimal API: responses ---
[JsonSerializable(typeof(MediaStatsDto))]
[JsonSerializable(typeof(AdvancedStatsDto))]
[JsonSerializable(typeof(TasteProfileDto))]
[JsonSerializable(typeof(CreatorSummaryDto))]
[JsonSerializable(typeof(CalendarScheduleDto))]
[JsonSerializable(typeof(CalendarItemDto))]
[JsonSerializable(typeof(PendingMatchReviewDto))]
[JsonSerializable(typeof(IReadOnlyList<PendingMatchReviewDto>))]
[JsonSerializable(typeof(ResolveAllByPriorityResult))]
[JsonSerializable(typeof(ImportResultDto))]
[JsonSerializable(typeof(CustomListSummaryDto))]
[JsonSerializable(typeof(IReadOnlyList<CustomListSummaryDto>))]
[JsonSerializable(typeof(CustomListDetailDto))]
[JsonSerializable(typeof(HistoryEventDto))]
[JsonSerializable(typeof(IReadOnlyList<HistoryEventDto>))]
[JsonSerializable(typeof(JobProgressDto))]
[JsonSerializable(typeof(IReadOnlyList<JobProgressDto>))]
[JsonSerializable(typeof(SourceInfo))]
[JsonSerializable(typeof(IReadOnlyList<SourceInfo>))]
[JsonSerializable(typeof(ToggleSourceResponse))]
[JsonSerializable(typeof(SaveSourceKeyResponse))]
[JsonSerializable(typeof(ConnectionTestResult))]
[JsonSerializable(typeof(ReadingSettingsDto))]
[JsonSerializable(typeof(ApiTokenDto))]
[JsonSerializable(typeof(IReadOnlyList<ApiTokenDto>))]
[JsonSerializable(typeof(CreatedApiTokenResponse))]
[JsonSerializable(typeof(TranslateResponse))]
[JsonSerializable(typeof(UpdateCheckResultDto))]
[JsonSerializable(typeof(GitHubReleaseDto))]
[JsonSerializable(typeof(GitHubAssetDto))]
[JsonSerializable(typeof(GameAchievementsResponse))]
[JsonSerializable(typeof(IReadOnlyList<GameRelatedItem>))]
// --- Minimal API: typed responses replacing anonymous objects ---
[JsonSerializable(typeof(ApiErrorDetail))]
[JsonSerializable(typeof(CreatedEntityId))]
[JsonSerializable(typeof(DismissedCount))]
[JsonSerializable(typeof(StorageInfoResponse))]
// --- External media payload graph (search, details, relations, recommendations) ---
[JsonSerializable(typeof(ExternalMediaDto))]
[JsonSerializable(typeof(IReadOnlyList<ExternalMediaDto>))]
[JsonSerializable(typeof(List<ExternalMediaDto>))]
[JsonSerializable(typeof(ExternalRatingDto))]
[JsonSerializable(typeof(CastMemberDto))]
[JsonSerializable(typeof(IReadOnlyList<CastMemberDto>))]
[JsonSerializable(typeof(List<CastMemberDto>))]
[JsonSerializable(typeof(ExternalStaffMemberDto))]
[JsonSerializable(typeof(IReadOnlyList<ExternalStaffMemberDto>))]
[JsonSerializable(typeof(List<ExternalStaffMemberDto>))]
[JsonSerializable(typeof(ExternalEpisodeDto))]
[JsonSerializable(typeof(IReadOnlyList<ExternalEpisodeDto>))]
[JsonSerializable(typeof(List<ExternalEpisodeDto>))]
[JsonSerializable(typeof(ExternalSeasonDto))]
[JsonSerializable(typeof(IReadOnlyList<ExternalSeasonDto>))]
[JsonSerializable(typeof(ExternalRecommendationDto))]
[JsonSerializable(typeof(IReadOnlyList<ExternalRecommendationDto>))]
[JsonSerializable(typeof(List<ExternalRecommendationDto>))]
[JsonSerializable(typeof(ExternalRelationDto))]
[JsonSerializable(typeof(IReadOnlyList<ExternalRelationDto>))]
[JsonSerializable(typeof(List<ExternalRelationDto>))]
// --- External provider response envelopes ---
[JsonSerializable(typeof(AniListSearchResponse))]
[JsonSerializable(typeof(AniListCreatorSearchResponse))]
[JsonSerializable(typeof(AniListDetailResponse))]
[JsonSerializable(typeof(AniListRelationsResponse))]
[JsonSerializable(typeof(AniListRecommendationsResponse))]
[JsonSerializable(typeof(AniListGraphQlPayload))]
[JsonSerializable(typeof(AniListProfileGraphQlPayload))]
[JsonSerializable(typeof(AniListVariables))]
[JsonSerializable(typeof(SimklItem))]
[JsonSerializable(typeof(IReadOnlyList<SimklItem>))]
[JsonSerializable(typeof(List<SimklItem>))]
[JsonSerializable(typeof(ShikimoriItem))]
[JsonSerializable(typeof(IReadOnlyList<ShikimoriItem>))]
[JsonSerializable(typeof(List<ShikimoriItem>))]
[JsonSerializable(typeof(MdMangaListResponse))]
[JsonSerializable(typeof(MdMangaSingleResponse))]
[JsonSerializable(typeof(MdStatisticsResponse))]
[JsonSerializable(typeof(MdCoverListResponse))]
[JsonSerializable(typeof(KitsuSearchResponse))]
[JsonSerializable(typeof(KitsuSingleResponse))]
[JsonSerializable(typeof(SteamStoreSearchResponse))]
[JsonSerializable(typeof(Dictionary<string, SteamAppDetailsWrapper>))]
[JsonSerializable(typeof(SteamReviewsResponse))]
[JsonSerializable(typeof(TmdbResponse))]
[JsonSerializable(typeof(TmdbItem))]
[JsonSerializable(typeof(TmdbPage))]
[JsonSerializable(typeof(MuSearchRequest))]
[JsonSerializable(typeof(MuSearchResponse))]
[JsonSerializable(typeof(MuSeriesRecord))]
[JsonSerializable(typeof(MuSearchRequest))]
[JsonSerializable(typeof(ImdbSuggestionResponse))]
[JsonSerializable(typeof(CinemetaResponse))]
[JsonSerializable(typeof(OpenLibraryResponse))]
[JsonSerializable(typeof(RawgResponse))]
[JsonSerializable(typeof(RawgGame))]
[JsonSerializable(typeof(RawgStoresResponse))]
[JsonSerializable(typeof(KinopoiskSearchResponse))]
[JsonSerializable(typeof(KinopoiskDetailItem))]
[JsonSerializable(typeof(KinopoiskSeasonsResponse))]
[JsonSerializable(typeof(List<KinopoiskStaffMember>))]
[JsonSerializable(typeof(KinopoiskVideosResponse))]
// --- Cached database blobs (ratings, cast, staff, episodes, relations, recommendations) ---
[JsonSerializable(typeof(RatingSnapshot))]
[JsonSerializable(typeof(List<RatingSnapshot>))]
[JsonSerializable(typeof(IReadOnlyList<RatingSnapshot>))]
[JsonSerializable(typeof(MediaMetadataApplier.StoredRating))]
[JsonSerializable(typeof(List<MediaMetadataApplier.StoredRating>))]
[JsonSerializable(typeof(MediaRatingSerializer.MediaRatingRow))]
[JsonSerializable(typeof(List<MediaRatingSerializer.MediaRatingRow>))]
[JsonSerializable(typeof(CachedAchievementsPayload))]
[JsonSerializable(typeof(SqliteQueryPlanEntry))]
[JsonSerializable(typeof(SqliteQueryPlanReport))]
[JsonSerializable(typeof(SmartListQueryDto))]
// --- Settings and configuration ---
[JsonSerializable(typeof(string[]))]
[JsonSerializable(typeof(List<string>))]
[JsonSerializable(typeof(IReadOnlyList<string>))]
[JsonSerializable(typeof(HashSet<string>))]
[JsonSerializable(typeof(Dictionary<string, string[]>))]
[JsonSerializable(typeof(Dictionary<string, CustomFolderSetting>))]
[JsonSerializable(typeof(StorageConfig))]
// --- Error surface ---
[JsonSerializable(typeof(ProblemDetails))]
[JsonSerializable(typeof(HttpValidationProblemDetails))]
[JsonSerializable(typeof(ValidationProblemDetails))]
internal sealed partial class AppJsonSerializerContext : JsonSerializerContext
{
    /// <summary>
    /// Reflection-free JsonTypeInfo lookup for generic helpers (provider envelopes, MediaJsonCache).
    /// Throws when the type was not registered, so a missing entry surfaces immediately in tests
    /// instead of falling back to reflection at runtime.
    /// </summary>
    internal static global::System.Text.Json.Serialization.Metadata.JsonTypeInfo<T> GetTypeInfo<T>() =>
        (global::System.Text.Json.Serialization.Metadata.JsonTypeInfo<T>)Default.Options.GetTypeInfo(typeof(T));
}
