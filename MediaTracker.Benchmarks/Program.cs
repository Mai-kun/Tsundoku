using System.Diagnostics;
using System.Text;
using Microsoft.Data.Sqlite;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.Persistence;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Drawing.Processing;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using BenchmarkDotNet.Running;

namespace MediaTracker.Benchmarks;

public static class Program
{
    public static async Task Main(string[] args)
    {
        if (args.Length >= 3 && args[0] == "--seed-db")
        {
            var count = int.Parse(args[1]);
            var dbPath = args[2];
            var coversPool = ParseCoversPool(args);
            await SeedDb(count, dbPath, coversPool);
            return;
        }

        if (args.Length == 0)
        {
            args = ["--filter", "*"];
        }

        BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
    }

    private static int ParseCoversPool(string[] args)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--covers-pool" && int.TryParse(args[i + 1], out var pool))
            {
                return pool;
            }
        }
        return 2000; // default pool size
    }

    private static async Task SeedDb(int count, string dbPath, int coversPool)
    {
        if (File.Exists(dbPath)) File.Delete(dbPath);

        var dataDir = Path.GetDirectoryName(Path.GetFullPath(dbPath)) ?? Environment.CurrentDirectory;
        var coversDir = Path.Combine(dataDir, "covers");

        // 1. Procedural cover pool (generated once, reused by every seeded item).
        if (coversPool > 0 && (!Directory.Exists(coversDir) || !Directory.GetFiles(coversDir, "cover_*.webp").Any()))
        {
            GenerateCoverPool(coversDir, coversPool);
        }

        using var conn = new SqliteConnection($"Data Source={dbPath}");
        await conn.OpenAsync();

        // Create the full server-compatible schema (source of truth), then apply perf pragmas.
        await SqliteSchemaInitializer.InitializeAsync(conn);

        using (var pragma = conn.CreateCommand())
        {
            pragma.CommandText = "PRAGMA synchronous = OFF; PRAGMA journal_mode = MEMORY; PRAGMA cache_size = -64000; PRAGMA mmap_size = 268435456;";
            await pragma.ExecuteNonQueryAsync();
        }

        const int batchSize = 10_000;
        var sw = Stopwatch.StartNew();

        var transaction = conn.BeginTransaction();
        using var command = conn.CreateCommand();
        command.Transaction = transaction;

        command.CommandText = """
            INSERT INTO MediaItems (
                Id, Title, Status, Score, Description, CoverUrl, SyncStatus,
                CreatedAt, UpdatedAt, MediaType, Author, ReleaseYear, Genres,
                Studio, Director, DurationMinutes, Platform, HoursPlayed,
                Network, Movie_IsAnime, TvShow_IsAnime, TvShow_Studio,
                TvShow_RomajiTitle, TvShow_EpisodeDurationMinutes,
                CurrentPage, TotalPages, CurrentChapter, TotalChapters,
                CurrentVolume, Manga_TotalVolumes, Movie_RomajiTitle, Manga_Format,
                ReleaseDate, EndDate, OriginalLanguage, CountryOfOrigin, Tags,
                AutoRefreshIntervalDays, IsCustomEdited
            ) VALUES (
                @id, @title, @status, @score, @description, @coverUrl, @sync,
                @createdAt, @updatedAt, @mediaType, @author, @releaseYear, @genres,
                @studio, @director, @durationMinutes, @platform, @hoursPlayed,
                @network, @movieIsAnime, @tvShowIsAnime, @tvShowStudio,
                @tvShowRomajiTitle, @tvShowEpisodeDurationMinutes,
                @currentPage, @totalPages, @currentChapter, @totalChapters,
                @currentVolume, @totalVolumes, @movieRomajiTitle, @mangaFormat,
                @releaseDate, @endDate, @originalLanguage, @countryOfOrigin, @tags,
                @autoRefresh, @customEdited
            );
            """;

        var pId = command.CreateParameter(); pId.ParameterName = "@id"; command.Parameters.Add(pId);
        var pTitle = command.CreateParameter(); pTitle.ParameterName = "@title"; command.Parameters.Add(pTitle);
        var pStatus = command.CreateParameter(); pStatus.ParameterName = "@status"; command.Parameters.Add(pStatus);
        var pScore = command.CreateParameter(); pScore.ParameterName = "@score"; command.Parameters.Add(pScore);
        var pDescription = command.CreateParameter(); pDescription.ParameterName = "@description"; command.Parameters.Add(pDescription);
        var pCoverUrl = command.CreateParameter(); pCoverUrl.ParameterName = "@coverUrl"; command.Parameters.Add(pCoverUrl);
        var pSync = command.CreateParameter(); pSync.ParameterName = "@sync"; command.Parameters.Add(pSync);
        var pCreatedAt = command.CreateParameter(); pCreatedAt.ParameterName = "@createdAt"; command.Parameters.Add(pCreatedAt);
        var pUpdatedAt = command.CreateParameter(); pUpdatedAt.ParameterName = "@updatedAt"; command.Parameters.Add(pUpdatedAt);
        var pMediaType = command.CreateParameter(); pMediaType.ParameterName = "@mediaType"; command.Parameters.Add(pMediaType);
        var pAuthor = command.CreateParameter(); pAuthor.ParameterName = "@author"; command.Parameters.Add(pAuthor);
        var pReleaseYear = command.CreateParameter(); pReleaseYear.ParameterName = "@releaseYear"; command.Parameters.Add(pReleaseYear);
        var pGenres = command.CreateParameter(); pGenres.ParameterName = "@genres"; command.Parameters.Add(pGenres);
        var pStudio = command.CreateParameter(); pStudio.ParameterName = "@studio"; command.Parameters.Add(pStudio);
        var pDirector = command.CreateParameter(); pDirector.ParameterName = "@director"; command.Parameters.Add(pDirector);
        var pDurationMinutes = command.CreateParameter(); pDurationMinutes.ParameterName = "@durationMinutes"; command.Parameters.Add(pDurationMinutes);
        var pPlatform = command.CreateParameter(); pPlatform.ParameterName = "@platform"; command.Parameters.Add(pPlatform);
        var pHoursPlayed = command.CreateParameter(); pHoursPlayed.ParameterName = "@hoursPlayed"; command.Parameters.Add(pHoursPlayed);
        var pNetwork = command.CreateParameter(); pNetwork.ParameterName = "@network"; command.Parameters.Add(pNetwork);
        var pMovieIsAnime = command.CreateParameter(); pMovieIsAnime.ParameterName = "@movieIsAnime"; command.Parameters.Add(pMovieIsAnime);
        var pTvShowIsAnime = command.CreateParameter(); pTvShowIsAnime.ParameterName = "@tvShowIsAnime"; command.Parameters.Add(pTvShowIsAnime);
        var pTvShowStudio = command.CreateParameter(); pTvShowStudio.ParameterName = "@tvShowStudio"; command.Parameters.Add(pTvShowStudio);
        var pTvShowRomaji = command.CreateParameter(); pTvShowRomaji.ParameterName = "@tvShowRomajiTitle"; command.Parameters.Add(pTvShowRomaji);
        var pTvShowEpDur = command.CreateParameter(); pTvShowEpDur.ParameterName = "@tvShowEpisodeDurationMinutes"; command.Parameters.Add(pTvShowEpDur);
        var pCurrentPage = command.CreateParameter(); pCurrentPage.ParameterName = "@currentPage"; command.Parameters.Add(pCurrentPage);
        var pTotalPages = command.CreateParameter(); pTotalPages.ParameterName = "@totalPages"; command.Parameters.Add(pTotalPages);
        var pCurrentChapter = command.CreateParameter(); pCurrentChapter.ParameterName = "@currentChapter"; command.Parameters.Add(pCurrentChapter);
        var pTotalChapters = command.CreateParameter(); pTotalChapters.ParameterName = "@totalChapters"; command.Parameters.Add(pTotalChapters);
        var pCurrentVolume = command.CreateParameter(); pCurrentVolume.ParameterName = "@currentVolume"; command.Parameters.Add(pCurrentVolume);
        var pTotalVolumes = command.CreateParameter(); pTotalVolumes.ParameterName = "@totalVolumes"; command.Parameters.Add(pTotalVolumes);
        var pMovieRomaji = command.CreateParameter(); pMovieRomaji.ParameterName = "@movieRomajiTitle"; command.Parameters.Add(pMovieRomaji);
        var pMangaFormat = command.CreateParameter(); pMangaFormat.ParameterName = "@mangaFormat"; command.Parameters.Add(pMangaFormat);
        var pReleaseDate = command.CreateParameter(); pReleaseDate.ParameterName = "@releaseDate"; command.Parameters.Add(pReleaseDate);
        var pEndDate = command.CreateParameter(); pEndDate.ParameterName = "@endDate"; command.Parameters.Add(pEndDate);
        var pOriginalLanguage = command.CreateParameter(); pOriginalLanguage.ParameterName = "@originalLanguage"; command.Parameters.Add(pOriginalLanguage);
        var pCountryOfOrigin = command.CreateParameter(); pCountryOfOrigin.ParameterName = "@countryOfOrigin"; command.Parameters.Add(pCountryOfOrigin);
        var pTags = command.CreateParameter(); pTags.ParameterName = "@tags"; command.Parameters.Add(pTags);
        var pAutoRefresh = command.CreateParameter(); pAutoRefresh.ParameterName = "@autoRefresh"; command.Parameters.Add(pAutoRefresh);
        var pCustomEdited = command.CreateParameter(); pCustomEdited.ParameterName = "@customEdited"; command.Parameters.Add(pCustomEdited);

        var rng = new Random(42);
        var now = DateTime.UtcNow;

        for (var i = 0; i < count; i++)
        {
            var typeRoll = i % 100;
            string mediaType;
            bool isAnime = false;

            if (typeRoll < 30) mediaType = SqliteSchemaInitializer.MediaTypes.Manga;
            else if (typeRoll < 55) { mediaType = SqliteSchemaInitializer.MediaTypes.TvShow; isAnime = true; }
            else if (typeRoll < 75) mediaType = SqliteSchemaInitializer.MediaTypes.Game;
            else if (typeRoll < 90) mediaType = SqliteSchemaInitializer.MediaTypes.Movie;
            else mediaType = SqliteSchemaInitializer.MediaTypes.Book;

            var statusRoll = i % 100;
            var status = statusRoll < 35 ? MediaStatus.Completed
                : statusRoll < 75 ? MediaStatus.Planned
                : statusRoll < 95 ? MediaStatus.InProgress
                : MediaStatus.Dropped;

            var releaseYear = 1980 + rng.Next(0, 47); // 1980-2026
            var score = rng.Next(1, 11);
            var coverIndex = (i % coversPool) + 1;
            var coverUrl = $"/covers/cover_{coverIndex:D4}.webp";

            var stamp = now.AddDays(-rng.Next(0, 365 * 5)).ToString("O");

            pId.Value = Guid.NewGuid().ToString().ToUpperInvariant();
            pTitle.Value = GenerateTitle(rng, i);
            pStatus.Value = (int)status;
            pScore.Value = score;
            pDescription.Value = GenerateDescription(rng);
            pCoverUrl.Value = coverUrl;
            pSync.Value = 0; // SyncStatus.Ready
            pCreatedAt.Value = stamp;
            pUpdatedAt.Value = stamp;
            pMediaType.Value = mediaType;
            pReleaseYear.Value = releaseYear;
            pGenres.Value = GenerateGenres(rng);

            // Type-specific fields.
            pAuthor.Value = DBNull.Value;
            pStudio.Value = DBNull.Value;
            pDirector.Value = DBNull.Value;
            pDurationMinutes.Value = DBNull.Value;
            pPlatform.Value = DBNull.Value;
            pHoursPlayed.Value = DBNull.Value;
            pNetwork.Value = DBNull.Value;
            pMovieIsAnime.Value = DBNull.Value;
            pTvShowIsAnime.Value = DBNull.Value;
            pTvShowStudio.Value = DBNull.Value;
            pTvShowRomaji.Value = DBNull.Value;
            pTvShowEpDur.Value = DBNull.Value;
            pCurrentPage.Value = DBNull.Value;
            pTotalPages.Value = DBNull.Value;
            pCurrentChapter.Value = DBNull.Value;
            pTotalChapters.Value = DBNull.Value;
            pCurrentVolume.Value = DBNull.Value;
            pTotalVolumes.Value = DBNull.Value;
            pMovieRomaji.Value = DBNull.Value;
            pMangaFormat.Value = DBNull.Value;
            pReleaseDate.Value = DBNull.Value;
            pEndDate.Value = DBNull.Value;
            pOriginalLanguage.Value = DBNull.Value;
            pCountryOfOrigin.Value = DBNull.Value;
            pTags.Value = DBNull.Value;
            pAutoRefresh.Value = 7;
            pCustomEdited.Value = 0;

            switch (mediaType)
            {
                case SqliteSchemaInitializer.MediaTypes.Manga:
                    pAuthor.Value = $"Mangaka {rng.Next(0, 200)}";
                    pMangaFormat.Value = new[] { "Manga", "Manhwa", "Manhua", "OEL" }[rng.Next(0, 4)];
                    pTotalVolumes.Value = rng.Next(1, 30);
                    pCurrentVolume.Value = rng.Next(0, (int)pTotalVolumes.Value + 1);
                    pCurrentChapter.Value = rng.Next(0, 200);
                    pTotalChapters.Value = rng.Next(1, 400);
                    break;
                case SqliteSchemaInitializer.MediaTypes.Game:
                    pPlatform.Value = new[] { "PC", "PlayStation 5", "Xbox Series X", "Nintendo Switch", "Steam Deck" }[rng.Next(0, 5)];
                    pStudio.Value = $"Studio {rng.Next(0, 80)}";
                    pHoursPlayed.Value = rng.Next(0, 500);
                    break;
                case SqliteSchemaInitializer.MediaTypes.Movie:
                    pDurationMinutes.Value = rng.Next(80, 240);
                    pDirector.Value = $"Director {rng.Next(0, 120)}";
                    pStudio.Value = $"Studio {rng.Next(0, 60)}";
                    pMovieRomaji.Value = GenerateRomaji(rng);
                    break;
                case SqliteSchemaInitializer.MediaTypes.TvShow:
                    pTvShowIsAnime.Value = isAnime ? 1 : 0;
                    pNetwork.Value = $"Network {rng.Next(0, 40)}";
                    pTvShowStudio.Value = $"Studio {rng.Next(0, 60)}";
                    pTvShowRomaji.Value = GenerateRomaji(rng);
                    pTvShowEpDur.Value = rng.Next(20, 60);
                    break;
                case SqliteSchemaInitializer.MediaTypes.Book:
                    pAuthor.Value = $"Author {rng.Next(0, 300)}";
                    pTotalPages.Value = rng.Next(100, 1200);
                    pCurrentPage.Value = rng.Next(0, 1200);
                    break;
            }

            command.ExecuteNonQuery();

            if (i > 0 && (i + 1) % batchSize == 0)
            {
                transaction.Commit();
                transaction.Dispose();
                transaction = conn.BeginTransaction();
                command.Transaction = transaction;
            }
        }

        transaction.Commit();
        transaction.Dispose();
        sw.Stop();

        var targetMs = count switch
        {
            50_000 => 3000,
            500_000 => 25_000,
            _ => (int?)null
        };
        if (targetMs is { } target)
        {
            var ok = sw.ElapsedMilliseconds <= target;
            Console.WriteLine($"[Seed] {(ok ? "OK" : "SLOW")} generated {count} items in {sw.ElapsedMilliseconds} ms (target <= {target} ms).");
            if (!ok) Environment.ExitCode = 1;
        }
        else
        {
            Console.WriteLine($"[Seed] Successfully generated {count} items in {sw.ElapsedMilliseconds} ms.");
        }
    }

    private static void GenerateCoverPool(string coversDir, int poolSize)
    {
        Directory.CreateDirectory(coversDir);

        // Contrasting hue palettes: indigo, amber, emerald, crimson, cyan.
        var palettes = new (Rgba32 Dark, Rgba32 Light, Rgba32 Accent)[]
        {
            (new Rgba32(45, 30, 110), new Rgba32(90, 70, 180), new Rgba32(255, 215, 0)),   // indigo / gold
            (new Rgba32(160, 90, 0), new Rgba32(230, 160, 40), new Rgba32(20, 60, 140)),   // amber / blue
            (new Rgba32(15, 120, 90), new Rgba32(60, 200, 150), new Rgba32(180, 30, 60)),   // emerald / crimson
            (new Rgba32(140, 20, 40), new Rgba32(210, 70, 90), new Rgba32(0, 140, 180)),    // crimson / cyan
            (new Rgba32(0, 120, 140), new Rgba32(60, 200, 220), new Rgba32(160, 40, 0)),    // cyan / amber
        };

        var encoder = new SixLabors.ImageSharp.Formats.Webp.WebpEncoder { Quality = 60 };
        var rng = new Random(7);

        for (var i = 1; i <= poolSize; i++)
        {
            var (dark, light, accent) = palettes[(i - 1) % palettes.Length];
            using var image = new Image<Rgba32>(360, 480);

            image.Mutate(ctx =>
            {
                // Background: a few horizontal gradient bands from dark to light.
                var bands = 6;
                var bandHeight = 480f / bands;
                for (var b = 0; b < bands; b++)
                {
                    var t = b / (float)Math.Max(1, bands - 1);
                    var r = (byte)(dark.R + (light.R - dark.R) * t);
                    var g = (byte)(dark.G + (light.G - dark.G) * t);
                    var bb = (byte)(dark.B + (light.B - dark.B) * t);
                    ctx.Fill(new Rgba32(r, g, bb), new RectangleF(0, b * bandHeight, 360, bandHeight + 1));
                }

                // Contrasting procedural geometric badge: central ellipse accent.
                ctx.Fill(accent, new SixLabors.ImageSharp.Drawing.EllipsePolygon(180f, 240f, 90f, 130f));

                // Inner darker shape for contrast.
                ctx.Fill(dark, new SixLabors.ImageSharp.Drawing.EllipsePolygon(180f, 240f, 55f, 85f));

                // Corner squares.
                ctx.Fill(light, new RectangleF(20, 20, 40, 40));
                ctx.Fill(light, new RectangleF(300, 20, 40, 40));
                ctx.Fill(light, new RectangleF(20, 420, 40, 40));
                ctx.Fill(light, new RectangleF(300, 420, 40, 40));

                // Diagonal accent stripes.
                ctx.Fill(accent, new RectangleF(60, 300, 240, 6));
                ctx.Fill(accent, new RectangleF(60, 174, 240, 6));

                // Deterministic noise rectangles seeded by index so every cover differs.
                var nr = new Random(i * 31);
                for (var n = 0; n < 3; n++)
                {
                    var nx = nr.Next(0, 340);
                    var ny = nr.Next(0, 460);
                    var nw = nr.Next(10, 60);
                    var nh = nr.Next(10, 60);
                    var nc = new Rgba32((byte)nr.Next(0, 255), (byte)nr.Next(0, 255), (byte)nr.Next(0, 255), 90);
                    ctx.Fill(nc, new RectangleF(nx, ny, Math.Min(nw, 360 - nx), Math.Min(nh, 480 - ny)));
                }
            });

            using var ms = new System.IO.MemoryStream();
            image.SaveAsWebp(ms, encoder);
            System.IO.File.WriteAllBytes(Path.Combine(coversDir, $"cover_{i:D4}.webp"), ms.ToArray());
        }
    }

    private static string GenerateTitle(Random rng, int index)
    {
        var adjectives = new[]
        {
            "Neon", "Silent", "Crimson", "Eternal", "Broken", "Golden", "Shadow", "Frozen",
            "Wild", "Last", "Velvet", "Azure", "Quantum", "Lost", "Hidden", "Bright", "Dark",
            "Steel", "Pale", "Fierce", "Cobalt", "Amber", "Frost", "Rust", "Ivory", "Opal",
            "Glass", "Iron", "Crystal", "Ember", "Storm", "Void", "Solar", "Lunar"
        };
        var nouns = new[]
        {
            "Blade", "Chronicle", "Odyssey", "Garden", "Protocol", "Covenant", "Symphony",
            "Frontier", "Legend", "Paradox", "Vertex", "Rift", "Echo", "Nova", "Prime", "Orbit",
            "Spire", "Crown", "Vault", "Flux", "Rune", "Gate", "Well", "Mire", "Peak", "Hollow",
            "Haven", "Spoke", "Arc", "Mesh", "Glyph"
        };
        var subtitles = new[]
        {
            "Reborn", "Awakening", "Requiem", "Horizon", "Zero", "Legacy", "Protocol", "Rising",
            "Fallen", "Beyond", "Ascension", "Zenith", "Nexus", "Omega", "Alpha", "Delta", "Sigma",
            "Void", "Core", "Edge", "Shift", "Flare", "Tide", "Mark", "Sign", "Lock", "Key"
        };

        var sb = new StringBuilder();
        sb.Append(adjectives[index % adjectives.Length]).Append(' ');
        sb.Append(nouns[(index / 7) % nouns.Length]).Append(' ');
        sb.Append(subtitles[(index / 13) % subtitles.Length]).Append(' ');
        sb.Append('#').Append(index + 1);
        return sb.ToString();
    }

    private static string GenerateDescription(Random rng)
    {
        var openings = new[]
        {
            "A gripping story that follows a reluctant hero through a world on the brink of collapse.",
            "Critics praised the bold direction and the unforgettable performances throughout.",
            "Set in a sprawling metropolis, this title blends action with quiet introspection.",
            "A genre-defining work that still feels fresh decades after its first release.",
            "The journey of an unlikely team facing impossible odds across strange lands.",
            "Rich world-building meets tight pacing in this standout entry.",
        };
        var bodies = new[]
        {
            "The visual style is striking, and the soundtrack complements every scene perfectly.",
            "Characters are well written, with motivations that evolve as the story unfolds.",
            "It rewards patience, revealing new layers on each revisit.",
            "Not without flaws, but its ambition carries it past the rough edges.",
            "A cult classic that influenced an entire generation of creators.",
            "The ending splits opinion, yet the ride remains unforgettable.",
            "Solid craftsmanship from start to finish, with memorable set pieces.",
        };
        var endings = new[]
        {
            "Recommended for fans of the genre.",
            "A must-watch for anyone who appreciates strong storytelling.",
            "Worth your time, even if it does not stick the landing.",
            "An experience that lingers long after the credits roll.",
        };

        var sb = new StringBuilder();
        sb.Append(openings[rng.Next(openings.Length)]).Append(' ');
        sb.Append(bodies[rng.Next(bodies.Length)]).Append(' ');
        sb.Append(bodies[rng.Next(bodies.Length)]).Append(' ');
        sb.Append(endings[rng.Next(endings.Length)]);

        // Pad to at least 150 chars with filler sentences; trim toward 400 if needed.
        while (sb.Length < 150)
        {
            sb.Append(' ').Append(bodies[rng.Next(bodies.Length)]);
        }

        return sb.ToString();
    }

    private static string GenerateGenres(Random rng)
    {
        var pool = new[]
        {
            "Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Romance",
            "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller", "Psychological",
            "Historical", "Music", "Martial Arts", "Mecha", "Isekai", "Crime",
        };
        var count = rng.Next(1, 4);
        var chosen = new HashSet<string>();
        while (chosen.Count < count) chosen.Add(pool[rng.Next(pool.Length)]);
        return string.Join(",", chosen);
    }

    private static string GenerateRomaji(Random rng)
    {
        var parts = new[] { "Sen", "Ryu", "Kai", "Tsu", "Ne", "Ko", "Ra", "Mu", "To", "Ki", "Yo", "Za" };
        var sb = new StringBuilder();
        for (var i = 0; i < 3; i++) sb.Append(parts[rng.Next(parts.Length)]);
        return sb.ToString();
    }
}
