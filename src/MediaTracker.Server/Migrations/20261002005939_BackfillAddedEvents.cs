using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MediaTracker.Server.Migrations
{
    /// <inheritdoc />
    public partial class BackfillAddedEvents : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // The library already held items when the event log was introduced, so the activity
            // screen came up empty. Seed one "Added" row per existing item, stamped with the item's
            // own CreatedAt so the timeline lines up with when it really entered the library.
            // lower(hex(randomblob(16))) mirrors how SQLite stores a GUID in this schema.
            migrationBuilder.Sql(
                """
                INSERT INTO "Events" ("Id", "MediaId", "Type", "OldValue", "NewValue", "CreatedAt")
                SELECT
                    lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(6))),
                    m."Id",
                    0,
                    NULL,
                    m."Title",
                    m."CreatedAt"
                FROM "MediaItems" AS m
                WHERE NOT EXISTS (SELECT 1 FROM "Events" AS e WHERE e."MediaId" = m."Id");
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Only the seeded rows are removed; anything the user did afterwards is kept.
            migrationBuilder.Sql(
                """
                DELETE FROM "Events"
                WHERE "OldValue" IS NULL AND "Type" = 0;
                """);
        }
    }
}
