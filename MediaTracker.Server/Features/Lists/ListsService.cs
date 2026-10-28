using Dapper;
using FluentValidation;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Features.Lists;

public sealed record CustomListSummaryDto(
    Guid Id, string Name, string? Description, string? Icon, string? Color,
    int ItemsCount, DateTime UpdatedAt, IReadOnlyList<string?> PreviewCovers,
    bool IsSmart, string? SmartQueryJson);

public sealed record CustomListDetailDto(
    Guid Id, string Name, string? Description, string? Icon, string? Color,
    DateTime CreatedAt, DateTime UpdatedAt, IReadOnlyList<MediaListDto> Items,
    bool IsSmart, string? SmartQueryJson);

public sealed record CreateListRequest(string Name, string? Description, string? Icon, string? Color, string? SmartQueryJson);
public sealed record UpdateListRequest(string Name, string? Description, string? Icon, string? Color, string? SmartQueryJson);
public sealed record AddMediaToListRequest(Guid MediaId);

public sealed class CreateListRequestValidator : AbstractValidator<CreateListRequest>
{
    public CreateListRequestValidator()
    {
        RuleFor(request => request.Name).Must(name => !string.IsNullOrWhiteSpace(name)).WithMessage("Name is required.").MaximumLength(100);
        RuleFor(request => request.Description).MaximumLength(500);
    }
}

public sealed class UpdateListRequestValidator : AbstractValidator<UpdateListRequest>
{
    public UpdateListRequestValidator()
    {
        RuleFor(request => request.Name).Must(name => !string.IsNullOrWhiteSpace(name)).WithMessage("Name is required.").MaximumLength(100);
        RuleFor(request => request.Description).MaximumLength(500);
    }
}

public sealed class ListsService(AppDbContext db)
{
    public async Task<IReadOnlyList<CustomListSummaryDto>> GetListsAsync(CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var lists = await db.GetCustomListsAsync(ct);

        // Load all media once if any smart list exists
        List<MediaItem>? allMedia = null;
        if (lists.Any(list => list.SmartQueryJson != null))
        {
            allMedia = (await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct));
        }

        var summaries = new List<CustomListSummaryDto>();
        foreach (var list in lists)
        {
            if (list.SmartQueryJson is { } json && SmartListEvaluator.ParseQuery(json) is { } query)
            {
                var matched = SmartListEvaluator.Evaluate(allMedia!, query);
                summaries.Add(new CustomListSummaryDto(
                    list.Id, list.Name, list.Description, list.Icon, list.Color,
                    matched.Count, list.UpdatedAt,
                    matched.Take(4).Select(item => item.CoverUrl).ToArray(),
                    IsSmart: true, SmartQueryJson: list.SmartQueryJson));
                continue;
            }

            var items = await db.GetCustomListItemsAsync(list.Id, ct);
            if (items.Count > 0 && allMedia is null)
            {
                allMedia = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);
            }
            summaries.Add(new CustomListSummaryDto(
                list.Id, list.Name, list.Description, list.Icon, list.Color,
                items.Count, list.UpdatedAt,
                items.Take(4).Select(item =>
                {
                    var media = allMedia?.FirstOrDefault(m => m.Id == item.MediaItemId);
                    return media?.CoverUrl;
                }).ToArray(),
                IsSmart: false, SmartQueryJson: null));
        }
        return summaries;
    }

    public async Task<CustomListDetailDto?> GetListDetailAsync(Guid id, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var list = await db.GetCustomListAsync(id, ct);
        if (list is null) return null;

        if (list.SmartQueryJson is { } json && SmartListEvaluator.ParseQuery(json) is { } query)
        {
            var allMedia = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);
            var matched = SmartListEvaluator.Evaluate(allMedia, query);
            return new CustomListDetailDto(
                list.Id, list.Name, list.Description, list.Icon, list.Color,
                list.CreatedAt, list.UpdatedAt,
                matched.Select(item => MediaResponseMapper.ToListDto(item)).ToArray(),
                IsSmart: true, SmartQueryJson: list.SmartQueryJson);
        }

        var items = await db.GetCustomListItemsAsync(id, ct);
        var allMedia2 = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);
        return new CustomListDetailDto(
            list.Id, list.Name, list.Description, list.Icon, list.Color,
            list.CreatedAt, list.UpdatedAt,
            items.Select(item => MediaResponseMapper.ToListDto(allMedia2.FirstOrDefault(m => m.Id == item.MediaItemId)!)).ToArray(),
            IsSmart: false, SmartQueryJson: null);
    }

    public async Task<Guid> CreateAsync(CreateListRequest request, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var list = new CustomList
        {
            Name = request.Name.Trim(),
            Description = request.Description?.Trim(),
            Icon = string.IsNullOrWhiteSpace(request.Icon) ? "list" : request.Icon,
            Color = request.Color,
            SmartQueryJson = string.IsNullOrWhiteSpace(request.SmartQueryJson) ? null : request.SmartQueryJson,
            CreatedAt = now,
            UpdatedAt = now,
        };
        await db.CreateCustomListAsync(list, ct);
        return list.Id;
    }

    public async Task<bool> UpdateAsync(Guid id, UpdateListRequest request, CancellationToken ct)
    {
        var list = await db.GetCustomListAsync(id, ct);
        if (list is null) return false;
        list.Name = request.Name.Trim();
        list.Description = request.Description?.Trim();
        list.Icon = string.IsNullOrWhiteSpace(request.Icon) ? "list" : request.Icon;
        list.Color = request.Color;
        list.SmartQueryJson = string.IsNullOrWhiteSpace(request.SmartQueryJson) ? null : request.SmartQueryJson;
        list.UpdatedAt = DateTime.UtcNow;
        return await db.UpdateCustomListAsync(list, ct);
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct)
    {
        return await db.DeleteCustomListAsync(id, ct);
    }

    public async Task<bool> AddMediaAsync(Guid listId, Guid mediaId, CancellationToken ct)
    {
        return await db.AddCustomListItemAsync(listId, mediaId, ct);
    }

    public async Task<bool> RemoveMediaAsync(Guid listId, Guid mediaId, CancellationToken ct)
    {
        return await db.RemoveCustomListItemAsync(listId, mediaId, ct);
    }

    public Task<List<Guid>> GetListsForMediaAsync(Guid mediaId, CancellationToken ct) =>
        db.GetCustomListIdsForMediaAsync(mediaId, ct);
}
