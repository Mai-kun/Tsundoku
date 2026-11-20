using MediaTracker.Server.Domain.Common;

namespace MediaTracker.Server.Features.Settings.NavigationCategories;

public interface IGetNavigationCategoriesHandler
{
    Task<Result<PromotedSubcategory[]>> HandleAsync(CancellationToken ct);
}

/// <summary>
/// Отдаёт активные вынесенные категории навигации: фронтенд строит по ним сайдбар,
/// счётчики и фильтр Главной.
/// </summary>
public sealed class GetNavigationCategoriesHandler(INavigationCategoriesService service)
    : IGetNavigationCategoriesHandler
{
    public Task<Result<PromotedSubcategory[]>> HandleAsync(CancellationToken ct) =>
        Task.FromResult(Result<PromotedSubcategory[]>.Success([.. service.Current]));
}
