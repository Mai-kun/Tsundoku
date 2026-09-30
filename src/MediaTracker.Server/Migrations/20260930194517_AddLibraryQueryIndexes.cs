using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddLibraryQueryIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_TvSeasons_TvShowId_SeasonNumber",
                table: "TvSeasons",
                columns: new[] { "TvShowId", "SeasonNumber" });

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_CreatedAt",
                table: "MediaItems",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_MediaType",
                table: "MediaItems",
                column: "MediaType");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_MediaType_Status_CreatedAt",
                table: "MediaItems",
                columns: new[] { "MediaType", "Status", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_Status",
                table: "MediaItems",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_Status_CreatedAt",
                table: "MediaItems",
                columns: new[] { "Status", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_MangaVolumes_MangaId_VolumeNumber",
                table: "MangaVolumes",
                columns: new[] { "MangaId", "VolumeNumber" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_TvSeasons_TvShowId_SeasonNumber",
                table: "TvSeasons");

            migrationBuilder.DropIndex(
                name: "IX_MediaItems_CreatedAt",
                table: "MediaItems");

            migrationBuilder.DropIndex(
                name: "IX_MediaItems_MediaType",
                table: "MediaItems");

            migrationBuilder.DropIndex(
                name: "IX_MediaItems_MediaType_Status_CreatedAt",
                table: "MediaItems");

            migrationBuilder.DropIndex(
                name: "IX_MediaItems_Status",
                table: "MediaItems");

            migrationBuilder.DropIndex(
                name: "IX_MediaItems_Status_CreatedAt",
                table: "MediaItems");

            migrationBuilder.DropIndex(
                name: "IX_MangaVolumes_MangaId_VolumeNumber",
                table: "MangaVolumes");
        }
    }
}
