using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddGamePayloadCache : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AchievementsJson",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RecommendationsJson",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AchievementsJson",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "RecommendationsJson",
                table: "MediaItems");
        }
    }
}
