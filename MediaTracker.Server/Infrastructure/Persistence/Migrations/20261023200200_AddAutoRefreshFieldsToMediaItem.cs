using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAutoRefreshFieldsToMediaItem : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AutoRefreshIntervalDays",
                table: "MediaItems",
                type: "INTEGER",
                nullable: false,
                defaultValue: 7);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastAutoRefreshedAt",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "NextAutoRefreshAt",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            // Existing ongoings get their initial checks spread over the next week, so the first
            // cycle polls five titles instead of firing the whole library at one provider at once.
            migrationBuilder.Sql("""
                UPDATE MediaItems
                SET AutoRefreshIntervalDays = 7,
                    NextAutoRefreshAt = datetime('now', '+' || ((abs(random()) % 7) + 1) || ' days')
                WHERE (ReleaseStatus IS NULL OR ReleaseStatus != 'FINISHED')
                  AND MediaType IN ('Manga', 'TvShow');
                """);

            migrationBuilder.CreateIndex(
                name: "IX_MediaItems_NextAutoRefreshAt",
                table: "MediaItems",
                column: "NextAutoRefreshAt");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_MediaItems_NextAutoRefreshAt",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "AutoRefreshIntervalDays",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "LastAutoRefreshedAt",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "NextAutoRefreshAt",
                table: "MediaItems");
        }
    }
}
