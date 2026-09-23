using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<MediaItem> MediaItems => Set<MediaItem>();

    public DbSet<Franchise> Franchises => Set<Franchise>();

    public DbSet<TvSeason> TvSeasons => Set<TvSeason>();

    public DbSet<VideoGame> Games => Set<VideoGame>();

    public DbSet<Book> Books => Set<Book>();

    public DbSet<Manga> Manga => Set<Manga>();

    public DbSet<Movie> Movies => Set<Movie>();

    public DbSet<TvShow> TvShows => Set<TvShow>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
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
            entity.HasIndex(show => show.IsAnime);

            entity.HasMany(show => show.Seasons)
                .WithOne(season => season.TvShow)
                .HasForeignKey(season => season.TvShowId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.Ignore(show => show.TotalEpisodesWatched)
                .Ignore(show => show.TotalEpisodesCount);
        });
    }
}
