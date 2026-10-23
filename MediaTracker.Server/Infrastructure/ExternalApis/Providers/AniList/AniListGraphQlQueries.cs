namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal static class AniListGraphQlQueries
{
internal const string MediaFields = """
    id
    type
    format
    title { romaji english native }
    description(asHtml: false)
    trailer { id site }
    coverImage { extraLarge }
    startDate { year month day }
    endDate { year month day }
    status
    countryOfOrigin
    duration
    episodes
    chapters
    volumes
    averageScore
    meanScore
    streamingEpisodes { title }
    studios(isMain: true) { nodes { name } }
    staff(perPage: 10, sort: [RELEVANCE, ID]) { edges { role node { name { full } image { large medium } } } }
    characters(perPage: 12, sort: [ROLE, RELEVANCE, ID]) {
      edges {
        role
        node { name { full } image { large medium } }
        voiceActors(language: JAPANESE, sort: [RELEVANCE, ID]) { name { full } image { large medium } }
      }
    }
    genres
    """;

internal const string GraphQLSearchQuery = $$"""
    query Search($search: String, $type: MediaType) {
      Page(perPage: 10) {
        media(search: $search, type: $type, sort: SEARCH_MATCH) {
          {{MediaFields}}
        }
      }
    }
    """;

/// <summary>A leaner field set for the studio/author listing: no cast or episodes, just the work.</summary>
internal const string CreatorMediaFields = """
    id
    type
    format
    title { romaji english native }
    description(asHtml: false)
    coverImage { extraLarge }
    startDate { year month day }
    endDate { year month day }
    status
    countryOfOrigin
    duration
    episodes
    chapters
    volumes
    averageScore
    studios(isMain: true) { nodes { name } }
    staff(perPage: 1) { edges { role node { name { full } } } }
    """;

internal const string GraphQLStudioSearchQuery = $$"""
    query StudioWorks($search: String) {
      Studio(search: $search) {
        name
        media(sort: POPULARITY_DESC, perPage: 15) {
          nodes { {{CreatorMediaFields}} }
        }
      }
    }
    """;

internal const string GraphQLStaffSearchQuery = $$"""
    query StaffWorks($search: String) {
      Staff(search: $search) {
        name { full }
        staffMedia(sort: POPULARITY_DESC, perPage: 15) {
          nodes { {{CreatorMediaFields}} }
        }
      }
    }
    """;

internal const string GraphQLDetailQuery = $$"""
    query Detail($id: Int, $type: MediaType) {
      Media(id: $id, type: $type) {
        {{MediaFields}}
      }
    }
    """;

internal const string GraphQLRelationsQuery = $$"""
    query Relations($id: Int, $idMal: Int, $search: String, $type: MediaType) {
      Media(id: $id, idMal: $idMal, search: $search, type: $type) {
        relations {
          edges {
            relationType
            node {
              {{MediaFields}}
            }
          }
        }
      }
    }
    """;

internal const string GraphQLRecommendationsQuery = $$"""
    query Recommendations($id: Int, $idMal: Int, $search: String, $type: MediaType) {
      Media(id: $id, idMal: $idMal, search: $search, type: $type) {
        recommendations(sort: RATING_DESC, perPage: 12) {
          nodes {
            rating
            mediaRecommendation {
              id
              type
              title { romaji english native }
              coverImage { extraLarge }
              averageScore
            }
          }
        }
      }
    }
    """;
}
