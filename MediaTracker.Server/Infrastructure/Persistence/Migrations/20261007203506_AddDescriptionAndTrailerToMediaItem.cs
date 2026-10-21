using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddDescriptionAndTrailerToMediaItem : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Description",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TrailerVideoId",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            // Older releases stored provider synopses in Notes. Preserve rows explicitly edited by
            // the user, while moving the known provider-only values into their own field.
            migrationBuilder.Sql("""
                UPDATE MediaItems
                SET Description = Notes, Notes = NULL
                WHERE IsCustomEdited = 0
                  AND Description IS NULL
                  AND ExternalId IS NOT NULL
                  AND Notes IS NOT NULL
                  AND trim(Notes) <> '';
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Description",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "TrailerVideoId",
                table: "MediaItems");
        }
    }
}
