using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ApiTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Name = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    TokenHash = table.Column<string>(type: "TEXT", nullable: false),
                    TokenPrefix = table.Column<string>(type: "TEXT", maxLength: 32, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    LastUsedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    ExpiresAt = table.Column<DateTime>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ApiTokens", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "CustomLists",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Name = table.Column<string>(type: "TEXT", maxLength: 100, nullable: false),
                    Description = table.Column<string>(type: "TEXT", maxLength: 500, nullable: true),
                    Icon = table.Column<string>(type: "TEXT", nullable: true, defaultValue: "list"),
                    Color = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    SmartQueryJson = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CustomLists", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Franchises",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Name = table.Column<string>(type: "TEXT", nullable: false),
                    Description = table.Column<string>(type: "TEXT", nullable: true),
                    CoverUrl = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Franchises", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Settings",
                columns: table => new
                {
                    Key = table.Column<string>(type: "TEXT", nullable: false),
                    Value = table.Column<string>(type: "TEXT", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Settings", x => x.Key);
                });

            migrationBuilder.CreateTable(
                name: "MediaItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Title = table.Column<string>(type: "TEXT", nullable: false),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    Score = table.Column<int>(type: "INTEGER", nullable: true),
                    DetailedScoreJson = table.Column<string>(type: "TEXT", nullable: true),
                    StartedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    FinishedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    LastActivityAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    Notes = table.Column<string>(type: "TEXT", nullable: true),
                    DropReason = table.Column<string>(type: "TEXT", nullable: true),
                    DropNotes = table.Column<string>(type: "TEXT", nullable: true),
                    QuotesJson = table.Column<string>(type: "TEXT", nullable: true),
                    Description = table.Column<string>(type: "TEXT", nullable: true),
                    TrailerVideoId = table.Column<string>(type: "TEXT", nullable: true),
                    CoverUrl = table.Column<string>(type: "TEXT", nullable: true),
                    CreatorImageUrl = table.Column<string>(type: "TEXT", nullable: true),
                    SyncStatus = table.Column<int>(type: "INTEGER", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    FranchiseId = table.Column<Guid>(type: "TEXT", nullable: true),
                    FranchiseOrder = table.Column<int>(type: "INTEGER", nullable: true),
                    ExternalId = table.Column<string>(type: "TEXT", nullable: true),
                    ExternalSource = table.Column<string>(type: "TEXT", nullable: true),
                    ImportSource = table.Column<string>(type: "TEXT", nullable: true),
                    ExternalRating = table.Column<double>(type: "REAL", nullable: true),
                    ExternalRatingVotes = table.Column<int>(type: "INTEGER", nullable: true),
                    ExternalRatingsJson = table.Column<string>(type: "TEXT", nullable: true),
                    NextAutoRefreshAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    AutoRefreshIntervalDays = table.Column<int>(type: "INTEGER", nullable: false),
                    LastAutoRefreshedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    ReleaseDate = table.Column<DateTime>(type: "TEXT", nullable: true),
                    ReleaseYear = table.Column<int>(type: "INTEGER", nullable: true),
                    EndDate = table.Column<DateTime>(type: "TEXT", nullable: true),
                    WatchedOn = table.Column<string>(type: "TEXT", nullable: true),
                    ReleaseStatus = table.Column<string>(type: "TEXT", nullable: true),
                    OriginalLanguage = table.Column<string>(type: "TEXT", nullable: true),
                    CountryOfOrigin = table.Column<string>(type: "TEXT", nullable: true),
                    OriginalTitle = table.Column<string>(type: "TEXT", nullable: true),
                    CastJson = table.Column<string>(type: "TEXT", nullable: true),
                    StaffJson = table.Column<string>(type: "TEXT", nullable: true),
                    TranslatedSynopsis = table.Column<string>(type: "TEXT", nullable: true),
                    TranslationLanguage = table.Column<string>(type: "TEXT", nullable: true),
                    Genres = table.Column<string>(type: "TEXT", nullable: true),
                    Tags = table.Column<string>(type: "TEXT", nullable: true),
                    UnlockedAchievements = table.Column<string>(type: "TEXT", nullable: true),
                    UserPlatform = table.Column<string>(type: "TEXT", nullable: true),
                    RelatedMediaJson = table.Column<string>(type: "TEXT", nullable: true),
                    PendingMatchesJson = table.Column<string>(type: "TEXT", nullable: true),
                    RelatedSource = table.Column<string>(type: "TEXT", nullable: true),
                    AchievementsJson = table.Column<string>(type: "TEXT", nullable: true),
                    RecommendationsJson = table.Column<string>(type: "TEXT", nullable: true),
                    RecommendationsUpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    IsCustomEdited = table.Column<bool>(type: "INTEGER", nullable: false),
                    MediaType = table.Column<string>(type: "TEXT", maxLength: 13, nullable: false),
                    Author = table.Column<string>(type: "TEXT", nullable: true),
                    CurrentPage = table.Column<int>(type: "INTEGER", nullable: true),
                    TotalPages = table.Column<int>(type: "INTEGER", nullable: true),
                    CurrentChapter = table.Column<int>(type: "INTEGER", nullable: true),
                    TotalChapters = table.Column<int>(type: "INTEGER", nullable: true),
                    Manga_Author = table.Column<string>(type: "TEXT", nullable: true),
                    Manga_RomajiTitle = table.Column<string>(type: "TEXT", nullable: true),
                    Manga_Format = table.Column<string>(type: "TEXT", nullable: true),
                    CurrentVolume = table.Column<int>(type: "INTEGER", nullable: true),
                    Manga_TotalVolumes = table.Column<int>(type: "INTEGER", nullable: true),
                    DurationMinutes = table.Column<int>(type: "INTEGER", nullable: true),
                    Director = table.Column<string>(type: "TEXT", nullable: true),
                    Movie_IsAnime = table.Column<bool>(type: "INTEGER", nullable: true),
                    Movie_Studio = table.Column<string>(type: "TEXT", nullable: true),
                    Movie_RomajiTitle = table.Column<string>(type: "TEXT", nullable: true),
                    Network = table.Column<string>(type: "TEXT", nullable: true),
                    TvShow_IsAnime = table.Column<bool>(type: "INTEGER", nullable: true),
                    TvShow_Studio = table.Column<string>(type: "TEXT", nullable: true),
                    TvShow_RomajiTitle = table.Column<string>(type: "TEXT", nullable: true),
                    TvShow_EpisodeDurationMinutes = table.Column<int>(type: "INTEGER", nullable: true),
                    Platform = table.Column<string>(type: "TEXT", nullable: true),
                    HoursPlayed = table.Column<int>(type: "INTEGER", nullable: true),
                    Studio = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MediaItems", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MediaItems_Franchises_FranchiseId",
                        column: x => x.FranchiseId,
                        principalTable: "Franchises",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "CustomListItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    ListId = table.Column<Guid>(type: "TEXT", nullable: false),
                    MediaItemId = table.Column<Guid>(type: "TEXT", nullable: false),
                    Order = table.Column<int>(type: "INTEGER", nullable: false),
                    AddedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CustomListItems", x => x.Id);
                    table.ForeignKey(
                        name: "FK_CustomListItems_CustomLists_ListId",
                        column: x => x.ListId,
                        principalTable: "CustomLists",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_CustomListItems_MediaItems_MediaItemId",
                        column: x => x.MediaItemId,
                        principalTable: "MediaItems",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Events",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    MediaId = table.Column<Guid>(type: "TEXT", nullable: false),
                    Type = table.Column<int>(type: "INTEGER", nullable: false),
                    OldValue = table.Column<string>(type: "TEXT", nullable: true),
                    NewValue = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Events", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Events_MediaItems_MediaId",
                        column: x => x.MediaId,
                        principalTable: "MediaItems",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MangaVolumes",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    VolumeNumber = table.Column<int>(type: "INTEGER", nullable: false),
                    Title = table.Column<string>(type: "TEXT", nullable: false),
                    CoverUrl = table.Column<string>(type: "TEXT", nullable: true),
                    CurrentPage = table.Column<int>(type: "INTEGER", nullable: false),
                    TotalPages = table.Column<int>(type: "INTEGER", nullable: false),
                    CurrentChapter = table.Column<int>(type: "INTEGER", nullable: false),
                    TotalChapters = table.Column<int>(type: "INTEGER", nullable: false),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    Score = table.Column<int>(type: "INTEGER", nullable: true),
                    Notes = table.Column<string>(type: "TEXT", nullable: true),
                    ReleaseDate = table.Column<DateTime>(type: "TEXT", nullable: true),
                    MangaId = table.Column<Guid>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MangaVolumes", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MangaVolumes_MediaItems_MangaId",
                        column: x => x.MangaId,
                        principalTable: "MediaItems",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TvSeasons",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    SeasonNumber = table.Column<int>(type: "INTEGER", nullable: false),
                    Title = table.Column<string>(type: "TEXT", nullable: false),
                    CoverUrl = table.Column<string>(type: "TEXT", nullable: true),
                    CurrentEpisode = table.Column<int>(type: "INTEGER", nullable: false),
                    TotalEpisodes = table.Column<int>(type: "INTEGER", nullable: false),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    Score = table.Column<int>(type: "INTEGER", nullable: true),
                    Notes = table.Column<string>(type: "TEXT", nullable: true),
                    AirDate = table.Column<DateTime>(type: "TEXT", nullable: true),
                    EpisodesData = table.Column<string>(type: "TEXT", nullable: true),
                    TvShowId = table.Column<Guid>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TvSeasons", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TvSeasons_MediaItems_TvShowId",
                        column: x => x.TvShowId,
                        principalTable: "MediaItems",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ApiTokens_TokenHash",
                table: "ApiTokens",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_CustomListItems_ListId_MediaItemId",
                table: "CustomListItems",
                columns: new[] { "ListId", "MediaItemId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_CustomListItems_MediaItemId",
                table: "CustomListItems",
                column: "MediaItemId");

            migrationBuilder.CreateIndex(
                name: "IX_Events_CreatedAt",
                table: "Events",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_Events_MediaId",
                table: "Events",
                column: "MediaId");

            migrationBuilder.CreateIndex(
                name: "IX_MangaVolumes_MangaId",
                table: "MangaVolumes",
                column: "MangaId");

            migrationBuilder.CreateIndex(
                name: "IX_MangaVolumes_MangaId_VolumeNumber",
                table: "MangaVolumes",
                columns: new[] { "MangaId", "VolumeNumber" });

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_CreatedAt",
                table: "MediaItems",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_FranchiseId",
                table: "MediaItems",
                column: "FranchiseId");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_MediaType",
                table: "MediaItems",
                column: "MediaType");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_MediaType_Status_CreatedAt",
                table: "MediaItems",
                columns: new[] { "MediaType", "Status", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_Movie_IsAnime",
                table: "MediaItems",
                column: "Movie_IsAnime");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_NextAutoRefreshAt",
                table: "MediaItems",
                column: "NextAutoRefreshAt");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_Status",
                table: "MediaItems",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_Status_CreatedAt",
                table: "MediaItems",
                columns: new[] { "Status", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_TvShow_IsAnime",
                table: "MediaItems",
                column: "TvShow_IsAnime");

            migrationBuilder.CreateIndex(
                name: "IX_TvSeasons_TvShowId",
                table: "TvSeasons",
                column: "TvShowId");

            migrationBuilder.CreateIndex(
                name: "IX_TvSeasons_TvShowId_SeasonNumber",
                table: "TvSeasons",
                columns: new[] { "TvShowId", "SeasonNumber" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ApiTokens");

            migrationBuilder.DropTable(
                name: "CustomListItems");

            migrationBuilder.DropTable(
                name: "Events");

            migrationBuilder.DropTable(
                name: "MangaVolumes");

            migrationBuilder.DropTable(
                name: "Settings");

            migrationBuilder.DropTable(
                name: "TvSeasons");

            migrationBuilder.DropTable(
                name: "CustomLists");

            migrationBuilder.DropTable(
                name: "MediaItems");

            migrationBuilder.DropTable(
                name: "Franchises");
        }
    }
}
