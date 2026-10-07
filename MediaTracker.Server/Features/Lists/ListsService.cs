using FluentValidation;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Lists;

public sealed record CustomListSummaryDto(
    Guid Id, string Name, string? Description, string? Icon, string? Color,
    int ItemsCount, DateTime UpdatedAt, IReadOnlyList<string?> PreviewCovers);

public sealed record CustomListDetailDto(
    Guid Id, string Name, string? Description, string? Icon, string? Color,
    DateTime CreatedAt, DateTime UpdatedAt, IReadOnlyList<MediaListDto> Items);

public sealed record CreateListRequest(string Name, string? Description, string? Icon, string? Color);
public sealed record UpdateListRequest(string Name, string? Description, string? Icon, string? Color);
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
        var lists = await db.CustomLists
            .AsNoTracking()
            .Include(list => list.Items.OrderBy(item => item.Order).ThenBy(item => item.AddedAt))
            .ThenInclude(item => item.MediaItem)
            .OrderByDescending(list => list.UpdatedAt)
            .ToListAsync(ct);

        return lists.Select(list => new CustomListSummaryDto(
            list.Id, list.Name, list.Description, list.Icon, list.Color,
            list.Items.Count, list.UpdatedAt,
            list.Items.Take(4).Select(item => item.MediaItem.CoverUrl).ToArray())).ToArray();
    }

    public async Task<CustomListDetailDto?> GetListDetailAsync(Guid id, CancellationToken ct)
    {
        var list = await db.CustomLists.AsNoTracking()
            .Include(value => value.Items.OrderBy(item => item.Order).ThenBy(item => item.AddedAt))
            .ThenInclude(item => item.MediaItem)
            .ThenInclude(media => media.Franchise)
            .Include(value => value.Items)
            .ThenInclude(item => item.MediaItem)
            .ThenInclude(media => (media as TvShow)!.Seasons)
            .SingleOrDefaultAsync(value => value.Id == id, ct);
        if (list is null) return null;

        return new CustomListDetailDto(
            list.Id, list.Name, list.Description, list.Icon, list.Color,
            list.CreatedAt, list.UpdatedAt,
            list.Items.Select(item => MediaResponseMapper.ToListDto(item.MediaItem)).ToArray());
    }

    public async Task<Guid> CreateAsync(CreateListRequest request, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var list = new CustomList
        {
            Name = request.Name.Trim(), Description = request.Description?.Trim(),
            Icon = string.IsNullOrWhiteSpace(request.Icon) ? "list" : request.Icon,
            Color = request.Color, CreatedAt = now, UpdatedAt = now,
        };
        db.CustomLists.Add(list);
        await db.SaveChangesAsync(ct);
        return list.Id;
    }

    public async Task<bool> UpdateAsync(Guid id, UpdateListRequest request, CancellationToken ct)
    {
        var list = await db.CustomLists.FindAsync([id], ct);
        if (list is null) return false;
        list.Name = request.Name.Trim();
        list.Description = request.Description?.Trim();
        list.Icon = string.IsNullOrWhiteSpace(request.Icon) ? "list" : request.Icon;
        list.Color = request.Color;
        list.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct)
    {
        var list = await db.CustomLists.FindAsync([id], ct);
        if (list is null) return false;
        db.CustomLists.Remove(list);
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> AddMediaAsync(Guid listId, Guid mediaId, CancellationToken ct)
    {
        if (!await db.CustomLists.AnyAsync(list => list.Id == listId, ct) ||
            !await db.MediaItems.AnyAsync(media => media.Id == mediaId, ct)) return false;
        if (await db.CustomListItems.AnyAsync(item => item.ListId == listId && item.MediaItemId == mediaId, ct)) return true;
        var order = await db.CustomListItems.Where(item => item.ListId == listId)
            .Select(item => (int?)item.Order).MaxAsync(ct) ?? -1;
        db.CustomListItems.Add(new CustomListItem
        {
            ListId = listId, MediaItemId = mediaId, Order = order + 1, AddedAt = DateTime.UtcNow,
        });
        var list = await db.CustomLists.FindAsync([listId], ct);
        if (list is not null) list.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> RemoveMediaAsync(Guid listId, Guid mediaId, CancellationToken ct)
    {
        var item = await db.CustomListItems.SingleOrDefaultAsync(
            value => value.ListId == listId && value.MediaItemId == mediaId, ct);
        if (item is null) return false;
        db.CustomListItems.Remove(item);
        var list = await db.CustomLists.FindAsync([listId], ct);
        if (list is not null) list.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    public Task<List<Guid>> GetListsForMediaAsync(Guid mediaId, CancellationToken ct) =>
        db.CustomListItems.AsNoTracking().Where(item => item.MediaItemId == mediaId)
            .Select(item => item.ListId).ToListAsync(ct);
}
