using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddLastActivityAtToMediaItem : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "LastActivityAt",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.Sql("UPDATE MediaItems SET LastActivityAt = COALESCE(StartedAt, UpdatedAt, CreatedAt) WHERE LastActivityAt IS NULL;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LastActivityAt",
                table: "MediaItems");
        }
    }
}
