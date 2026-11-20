namespace MediaTracker.Server.Features.Settings.NavigationCategories;

public interface INavigationCategoriesService
{
    /// <summary>Текущий снимок активных вынесенных подкатегорий (порядок = порядок в сайдбаре).</summary>
    IReadOnlyList<PromotedSubcategory> Current { get; }

    /// <summary>Накатывает новый снимок (после сохранения или восстановления при старте).</summary>
    void Update(IReadOnlyList<PromotedSubcategory> categories);

    /// <summary>Активные подкатегории одного родительского типа (в порядке конфигурации).</summary>
    IReadOnlyList<PromotedSubcategory> ActiveForParent(string parentType);

    /// <summary>Находит категорию по id (case-insensitive) или null.</summary>
    PromotedSubcategory? Find(string id);
}

/// <summary>
/// Живой снимок вынесенных категорий навигации. Клиенты (SQL-фильтры списков и статистики,
/// выдача конфигурации фронтенду) читают <see cref="Current"/> на каждом обращении, поэтому
/// сохранение в настройках применяется мгновенно — рестарт не нужен. Тот же паттерн, что
/// и у настроек прокси.
/// </summary>
public sealed class NavigationCategoriesService : INavigationCategoriesService
{
    private volatile IReadOnlyList<PromotedSubcategory> _current =
        Array.Empty<PromotedSubcategory>();

    public IReadOnlyList<PromotedSubcategory> Current => _current;

    public void Update(IReadOnlyList<PromotedSubcategory> categories) =>
        _current = categories.Count == 0
            ? Array.Empty<PromotedSubcategory>()
            : categories;

    public IReadOnlyList<PromotedSubcategory> ActiveForParent(string parentType) =>
        _current.Where(c => c.ParentType.Equals(parentType, StringComparison.OrdinalIgnoreCase))
            .ToArray();

    public PromotedSubcategory? Find(string id) =>
        _current.FirstOrDefault(c => c.Id.Equals(id?.Trim(), StringComparison.OrdinalIgnoreCase));
}
