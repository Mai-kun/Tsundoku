namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal interface IAniListEnvelope<TData>
    where TData : class
{
    TData? Data { get; }
}

internal sealed record AniListSearchResponse(AniListData? Data);
internal sealed record AniListDetailResponse(AniListDetailData? Data);
internal sealed record AniListDetailData(AniListMedia? Media);
internal sealed record AniListData(AniListPage? Page);
internal sealed record AniListPage(List<AniListMedia>? Media);

internal sealed record AniListCreatorSearchResponse(AniListCreatorData? Data);
internal sealed record AniListCreatorData(AniListStudioPayload? Studio, AniListStaffPayload? Staff);
internal sealed record AniListStudioPayload(string? Name, AniListCreatorMediaConnection? Media);
internal sealed record AniListStaffPayload(AniListName? Name, AniListCreatorMediaConnection? StaffMedia);
internal sealed record AniListCreatorMediaConnection(List<AniListMedia>? Nodes);

internal sealed record AniListRelationsResponse(AniListRelationsData? Data)
    : IAniListEnvelope<AniListRelationsData>;

internal sealed record AniListRelationsData(AniListRelationsPayload? Media);

internal sealed record AniListRelationsPayload(AniListRelationEdges? Relations);

internal sealed record AniListRelationEdges(List<AniListRelationEdge?>? Edges);

internal sealed record AniListRelationEdge(string? RelationType, AniListMedia? Node);

internal sealed record AniListRecommendationsResponse(AniListRecommendationsData? Data)
    : IAniListEnvelope<AniListRecommendationsData>;

internal sealed record AniListRecommendationsData(AniListRecommendationsPayload? Media);

internal sealed record AniListRecommendationsPayload(AniListRecommendationNodes? Recommendations);

internal sealed record AniListRecommendationNodes(List<AniListRecommendationNode?>? Nodes);

internal sealed record AniListRecommendationNode(double? Rating, AniListRecommendedMedia? MediaRecommendation);

internal sealed record AniListRecommendedMedia(
    int Id,
    string? Type,
    AniListTitle? Title,
    AniListCoverImage? CoverImage,
    int? AverageScore);

internal sealed record AniListMedia(
    int Id,
    string? Type,
    string? Format,
    AniListTitle? Title,
    string? Description,
    AniListTrailer? Trailer,
    AniListCoverImage? CoverImage,
    AniListDate? StartDate,
    AniListDate? EndDate,
    string? Status,
    string? CountryOfOrigin,
    int? Duration,
    int? Episodes,
    int? Chapters,
    int? Volumes,
    int? AverageScore,
    int? MeanScore,
    List<AniListStreamingEpisode>? StreamingEpisodes,
    AniListStudios? Studios,
    AniListStaff? Staff,
    AniListCharacters? Characters,
    List<string>? Genres);

internal sealed record AniListStreamingEpisode(string? Title);
internal sealed record AniListTrailer(string? Id, string? Site);
internal sealed record AniListTitle(string? Romaji, string? English, string? Native);
internal sealed record AniListCoverImage(string? ExtraLarge);
internal sealed record AniListDate(int? Year, int? Month, int? Day);
internal sealed record AniListStudios(List<AniListStudio>? Nodes);
internal sealed record AniListStudio(string? Name);
internal sealed record AniListStaff(List<AniListStaffEdge>? Edges);
internal sealed record AniListStaffEdge(string? Role, AniListStaffNode? Node);
internal sealed record AniListStaffNode(AniListName? Name, AniListCharacterImage? Image);
internal sealed record AniListCharacters(List<AniListCharacterEdge>? Edges);
internal sealed record AniListCharacterEdge(string? Role, AniListCharacter? Node, List<AniListVoiceActor>? VoiceActors);
internal sealed record AniListCharacter(AniListName? Name, AniListCharacterImage? Image);
internal sealed record AniListVoiceActor(AniListName? Name, AniListCharacterImage? Image);
internal sealed record AniListCharacterImage(string? Large, string? Medium)
{
    /// <summary>Large when the source has one: small portraits blur in the big people cards.</summary>
    public string? Best => Large ?? Medium;
}
internal sealed record AniListName(string? Full);
