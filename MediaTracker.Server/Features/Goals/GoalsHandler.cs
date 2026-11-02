using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Goals;

/// <summary>Wire shape of <c>GET /api/goals</c> rows: goal plus its live progress.</summary>
public sealed record GoalDto(
    Guid Id,
    string Title,
    string? Description,
    string Icon,
    int Year,
    int TargetCount,
    int CurrentCount,
    bool IsCompleted,
    string? Category,
    string? SmartQueryJson,
    IReadOnlyList<MediaListDto> CompletedItems);

/// <summary>Body of <c>POST /api/goals</c>.</summary>
public sealed record CreateGoalRequest(
    string Title,
    string? Description,
    string? Icon,
    int Year,
    int TargetCount,
    string? Category,
    string? SmartQueryJson);

public interface IGoalsHandler
{
    Task<Result<IReadOnlyList<GoalDto>>> GetGoalsAsync(int year, CancellationToken ct);

    Task<Result<GoalDto>> CreateAsync(CreateGoalRequest request, CancellationToken ct);

    Task<Result> DeleteAsync(Guid id, CancellationToken ct);
}

/// <summary>
/// Goals are stored without progress: every read recomputes it from the completed media, so a
/// title finished moments ago immediately lands in the matching goal (no cache to invalidate).
/// </summary>
public sealed class GoalsHandler(AppDbContext db) : IGoalsHandler
{
    /// <summary>Cover-strip size under each goal's progress bar.</summary>
    private const int PreviewCount = 6;

    public async Task<Result<IReadOnlyList<GoalDto>>> GetGoalsAsync(int year, CancellationToken ct)
    {
        if (year is < 1900 or > 2200)
        {
            return Result<IReadOnlyList<GoalDto>>.Failure(
                Error.Validation($"Year '{year}' is out of range."));
        }

        await db.EnsureDefaultGoalsAsync(year, ct);
        var goals = await db.GetGoalsByYearAsync(year, ct);
        if (goals.Count == 0)
        {
            return Result<IReadOnlyList<GoalDto>>.Success([]);
        }

        var completed = await LoadCompletedAsync(ct);

        var dtos = new List<GoalDto>(goals.Count);
        foreach (var goal in goals)
        {
            var matched = MatchGoal(goal, completed);
            dtos.Add(ToDto(goal, matched));
        }

        return Result<IReadOnlyList<GoalDto>>.Success(dtos);
    }

    public async Task<Result<GoalDto>> CreateAsync(CreateGoalRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Title))
        {
            return Result<GoalDto>.Failure(Error.Validation("Goal title is required."));
        }
        if (request.TargetCount is < 1 or > 100_000)
        {
            return Result<GoalDto>.Failure(Error.Validation("TargetCount must be between 1 and 100000."));
        }
        if (request.Year is < 1900 or > 2200)
        {
            return Result<GoalDto>.Failure(Error.Validation($"Year '{request.Year}' is out of range."));
        }

        var goal = new Goal
        {
            Title = request.Title.Trim(),
            Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim(),
            Icon = string.IsNullOrWhiteSpace(request.Icon) ? "🎯" : request.Icon.Trim(),
            Year = request.Year,
            TargetCount = request.TargetCount,
            Category = string.IsNullOrWhiteSpace(request.Category) ? "all" : request.Category.Trim().ToLowerInvariant(),
            SmartQueryJson = string.IsNullOrWhiteSpace(request.SmartQueryJson) ? null : request.SmartQueryJson,
        };

        await db.CreateGoalAsync(goal, ct);

        // A brand-new goal starts at zero, but compute anyway so the response shape matches GET.
        var completed = await LoadCompletedAsync(ct);
        return Result<GoalDto>.Success(ToDto(goal, MatchGoal(goal, completed)));
    }

    public async Task<Result> DeleteAsync(Guid id, CancellationToken ct)
    {
        var deleted = await db.DeleteGoalAsync(id, ct);
        return deleted > 0
            ? Result.Success()
            : Result.Failure(Error.NotFound($"Goal '{id}' was not found."));
    }

    /// <summary>Paged read of every completed item — the count must be exact, never a 500-row page.</summary>
    private async Task<List<MediaItem>> LoadCompletedAsync(CancellationToken ct)
    {
        var all = new List<MediaItem>();
        const int pageSize = 2000;
        while (true)
        {
            var page = await db.LoadMediaItemsAsync(
                null, MediaStatus.Completed, null, null, null, null, ct, pageSize, all.Count);
            all.AddRange(page);
            if (page.Count < pageSize)
            {
                return all;
            }
        }
    }

    private static List<MediaItem> MatchGoal(Goal goal, List<MediaItem> completed)
    {
        var matched = new List<MediaItem>();
        foreach (var item in completed)
        {
            var finishedYear = item.FinishedAt?.Year 
                               ?? (item.Status == MediaStatus.Completed ? item.UpdatedAt.Year : (int?)null);
            if (finishedYear != goal.Year) continue;

            // Category always applies — a smart query narrows the category further, never widens it.
            var category = goal.Category;
            if (!string.IsNullOrEmpty(category) && category != "all" && !MatchesCategory(item, category))
            {
                continue;
            }

            matched.Add(item);
        }

        if (goal.SmartQueryJson is not null)
        {
            var query = SmartListEvaluator.ParseQuery(goal.SmartQueryJson);
            if (query is not null)
            {
                return SmartListEvaluator.Evaluate(matched, query).ToList();
            }
        }

        return matched;
    }

    /// <summary>Goal categories map intuitively: "movie"/"tvshow" match the type regardless of
    /// the anime flag, "anime" matches the flag — unlike smart-list categories, where
    /// "movie" excludes anime movies.</summary>
    private static bool MatchesCategory(MediaItem item, string category) => category.ToLowerInvariant() switch
    {
        "anime" => item is TvShow { IsAnime: true } or Movie { IsAnime: true },
        "tvshow" => item is TvShow,
        "movie" => item is Movie,
        "game" => item is VideoGame,
        "manga" => item is Manga,
        "book" => item is Book,
        _ => true,
    };

    private static GoalDto ToDto(Goal goal, List<MediaItem> matched)
    {
        var previews = matched
            .OrderByDescending(item => item.FinishedAt ?? (item.Status == MediaStatus.Completed ? item.UpdatedAt : DateTime.MinValue))
            .Take(PreviewCount)
            .Select(MediaResponseMapper.ToListDto)
            .ToList();

        return new GoalDto(
            goal.Id,
            goal.Title,
            goal.Description,
            string.IsNullOrWhiteSpace(goal.Icon) ? "🎯" : goal.Icon,
            goal.Year,
            goal.TargetCount,
            matched.Count,
            matched.Count >= goal.TargetCount,
            goal.Category,
            goal.SmartQueryJson,
            previews);
    }
}
