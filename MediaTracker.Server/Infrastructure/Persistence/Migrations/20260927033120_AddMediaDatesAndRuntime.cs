using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddMediaDatesAndRuntime : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "EndDate",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ReleaseDate",
                table: "MediaItems",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "TvShow_EpisodeDurationMinutes",
                table: "MediaItems",
                type: "INTEGER",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EndDate",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "ReleaseDate",
                table: "MediaItems");

            migrationBuilder.DropColumn(
                name: "TvShow_EpisodeDurationMinutes",
                table: "MediaItems");
        }
    }
}
