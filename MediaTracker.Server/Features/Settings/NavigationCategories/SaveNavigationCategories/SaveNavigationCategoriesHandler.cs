using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.NavigationCategories;

public sealed record SaveNavigationCategoriesCommand(PromotedSubcategory[] Categories);

public interface ISaveNavigationCategoriesHandler
{
    Task<Result<PromotedSubcategory[]>> HandleAsync(SaveNavigationCategoriesCommand command, CancellationToken ct);
}

/// <summary>
/// Сохраняет полный список вынесенных категорий навигации (клиент присылает итоговый список:
/// добавление/удаление/порядок — одна запись) и сразу накатывает снимок в сервис: SQL-фильтры
/// списков и статистики, сайдбар и «Книги» перестраиваются на лету, без рестарта.
/// </summary>
public sealed class SaveNavigationCategoriesHandler(
    AppDbContext db,
    INavigationCategoriesService service) : ISaveNavigationCategoriesHandler
{
    private const string SettingKey = "App_NavigationCategories";

    public async Task<Result<PromotedSubcategory[]>> HandleAsync(
        SaveNavigationCategoriesCommand command,
        CancellationToken ct)
    {
        var (categories, error) = PromotedSubcategory.NormalizeList(command.Categories ?? []);
        if (error is not null)
        {
            return Result<PromotedSubcategory[]>.Failure(Domain.Common.Error.Validation(error));
        }

        await AppSettingStore.SetAsync(db, SettingKey, JsonSettings.Serialize(categories), ct);
        service.Update(categories);

        // Состав категорий меняет выборку «Книг»/родителей — кэш списков обязан уйти,
        // иначе клиенты увидят старый состав до истечения TTL.
        MediaTracker.Server.Features.Media.GetMediaList.MediaListCache.Invalidate();

        return Result<PromotedSubcategory[]>.Success(categories);
    }
}
