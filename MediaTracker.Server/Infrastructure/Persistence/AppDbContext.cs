using MediaTracker.Server.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Infrastructure.Persistence;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<MediaItem> MediaItems => Set<MediaItem>();

    public DbSet<Franchise> Franchises => Set<Franchise>();

    public DbSet<TvSeason> TvSeasons => Set<TvSeason>();

    public DbSet<MangaVolume> MangaVolumes => Set<MangaVolume>();

    public DbSet<VideoGame> Games => Set<VideoGame>();

    public DbSet<Book> Books => Set<Book>();

    public DbSet<Manga> Manga => Set<Manga>();

    public DbSet<Movie> Movies => Set<Movie>();

    public DbSet<TvShow> TvShows => Set<TvShow>();

    public DbSet<AppSetting> Settings => Set<AppSetting>();

    public DbSet<MediaEvent> Events => Set<MediaEvent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AppSetting>(entity => entity.HasKey(s => s.Key));

        modelBuilder.Entity<MediaEvent>(entity =>
        {
            entity.HasKey(e => e.Id);
            // The history screen reads the newest first, so the index carries the sort column.
            entity.HasIndex(e => e.CreatedAt);
            entity.HasOne(e => e.Media)
                .WithMany()
                .HasForeignKey(e => e.MediaId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<MediaItem>(entity =>
        {
            entity.UseTphMappingStrategy();
            entity.HasDiscriminator<string>("MediaType")
                .HasValue<VideoGame>("Game")
                .HasValue<Book>("Book")
                .HasValue<Manga>("Manga")
                .HasValue<Movie>("Movie")
                .HasValue<TvShow>("TvShow");

            entity.HasOne(item => item.Franchise)
                .WithMany(franchise => franchise.Items)
                .HasForeignKey(item => item.FranchiseId)
                .OnDelete(DeleteBehavior.SetNull);

            // The library screens filter and sort on these columns on every request; without the
            // indexes SQLite falls back to a full scan and a temp b-tree for the ORDER BY.
            entity.HasIndex(item => item.Status);
            entity.HasIndex(item => item.CreatedAt);
            entity.HasIndex("MediaType");
            entity.HasIndex(item => new { item.Status, item.CreatedAt });
            entity.HasIndex("MediaType", nameof(MediaItem.Status), nameof(MediaItem.CreatedAt));
        });

        modelBuilder.Entity<Movie>(entity =>
        {
            entity.Property(movie => movie.IsAnime).HasColumnName("Movie_IsAnime");
            entity.Property(movie => movie.Studio).HasColumnName("Movie_Studio");
            entity.Property(movie => movie.RomajiTitle).HasColumnName("Movie_RomajiTitle");
            entity.HasIndex(movie => movie.IsAnime);
        });

        modelBuilder.Entity<TvShow>(entity =>
        {
            entity.Property(show => show.IsAnime).HasColumnName("TvShow_IsAnime");
            entity.Property(show => show.Studio).HasColumnName("TvShow_Studio");
            entity.Property(show => show.RomajiTitle).HasColumnName("TvShow_RomajiTitle");
            entity.Property(show => show.EpisodeDurationMinutes).HasColumnName("TvShow_EpisodeDurationMinutes");
            entity.HasIndex(show => show.IsAnime);

            entity.HasMany(show => show.Seasons)
                .WithOne(season => season.TvShow)
                .HasForeignKey(season => season.TvShowId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Ignore(show => show.TotalEpisodesWatched)
                .Ignore(show => show.TotalEpisodesCount);
        });

        modelBuilder.Entity<TvSeason>(entity =>
        {
            entity.HasIndex(season => season.TvShowId);
            entity.HasIndex(season => new { season.TvShowId, season.SeasonNumber });
        });

        modelBuilder.Entity<MangaVolume>(entity =>
        {
            entity.HasIndex(volume => volume.MangaId);
            entity.HasIndex(volume => new { volume.MangaId, volume.VolumeNumber });
        });

        modelBuilder.Entity<Manga>(entity =>
        {
            entity.Property(manga => manga.Author).HasColumnName("Manga_Author");
            entity.Property(manga => manga.RomajiTitle).HasColumnName("Manga_RomajiTitle");
            entity.Property(manga => manga.TotalVolumes).HasColumnName("Manga_TotalVolumes");
            entity.Property(manga => manga.Format).HasColumnName("Manga_Format");

            entity.HasMany(manga => manga.Volumes)
                .WithOne(volume => volume.Manga)
                .HasForeignKey(volume => volume.MangaId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
