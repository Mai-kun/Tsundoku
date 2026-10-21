using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSyncStatusToMediaItem : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "SyncStatus",
                table: "MediaItems",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SyncStatus",
                table: "MediaItems");
        }
    }
}
