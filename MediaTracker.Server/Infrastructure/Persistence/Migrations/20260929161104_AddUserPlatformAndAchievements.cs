using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddUserPlatformAndAchievements : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "UnlockedAchievements",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "UserPlatform",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "UnlockedAchievements",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "UserPlatform",
                table: "MediaItems");
        }
    }
}
