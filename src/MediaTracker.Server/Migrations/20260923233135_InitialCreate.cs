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
                name: "MediaItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    Title = table.Column<string>(type: "TEXT", nullable: false),
                    Status = table.Column<int>(type: "INTEGER", nullable: false),
                    Score = table.Column<int>(type: "INTEGER", nullable: true),
                    StartedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    FinishedAt = table.Column<DateTime>(type: "TEXT", nullable: true),
                    Notes = table.Column<string>(type: "TEXT", nullable: true),
                    CoverUrl = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    FranchiseId = table.Column<Guid>(type: "TEXT", nullable: true),
                    FranchiseOrder = table.Column<int>(type: "INTEGER", nullable: true),
                    MediaType = table.Column<string>(type: "TEXT", maxLength: 13, nullable: false),
                    Author = table.Column<string>(type: "TEXT", nullable: true),
                    CurrentPage = table.Column<int>(type: "INTEGER", nullable: true),
                    TotalPages = table.Column<int>(type: "INTEGER", nullable: true),
                    CurrentChapter = table.Column<int>(type: "INTEGER", nullable: true),
                    TotalChapters = table.Column<int>(type: "INTEGER", nullable: true),
                    CurrentVolume = table.Column<int>(type: "INTEGER", nullable: true),
                    DurationMinutes = table.Column<int>(type: "INTEGER", nullable: true),
                    Director = table.Column<string>(type: "TEXT", nullable: true),
                    Movie_IsAnime = table.Column<bool>(type: "INTEGER", nullable: true),
                    Movie_Studio = table.Column<string>(type: "TEXT", nullable: true),
                    Movie_RomajiTitle = table.Column<string>(type: "TEXT", nullable: true),
                    Network = table.Column<string>(type: "TEXT", nullable: true),
                    TvShow_IsAnime = table.Column<bool>(type: "INTEGER", nullable: true),
                    TvShow_Studio = table.Column<string>(type: "TEXT", nullable: true),
                    TvShow_RomajiTitle = table.Column<string>(type: "TEXT", nullable: true),
                    Platform = table.Column<string>(type: "TEXT", nullable: true),
                    HoursPlayed = table.Column<int>(type: "INTEGER", nullable: true)
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
                name: "IX_MediaItems_FranchiseId",
                table: "MediaItems",
                column: "FranchiseId");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_Movie_IsAnime",
                table: "MediaItems",
                column: "Movie_IsAnime");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_TvShow_IsAnime",
                table: "MediaItems",
                column: "TvShow_IsAnime");

            migrationBuilder.CreateIndex(
                name: "IX_TvSeasons_TvShowId",
                table: "TvSeasons",
                column: "TvShowId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TvSeasons");

            migrationBuilder.DropTable(
                name: "MediaItems");

            migrationBuilder.DropTable(
                name: "Franchises");
        }
    }
}
