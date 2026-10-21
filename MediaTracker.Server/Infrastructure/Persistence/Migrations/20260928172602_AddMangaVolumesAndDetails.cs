using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddMangaVolumesAndDetails : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Manga_Author",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Manga_RomajiTitle",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Manga_TotalVolumes",
                table: "MediaItems",
                type: "INTEGER",
                nullable: true);

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

            migrationBuilder.CreateIndex(
                name: "IX_MangaVolumes_MangaId",
                table: "MangaVolumes",
                column: "MangaId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "MangaVolumes");

            migrationBuilder.DropColumn(
                name: "Manga_Author",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "Manga_RomajiTitle",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "Manga_TotalVolumes",
                table: "MediaItems");
        }
    }
}
