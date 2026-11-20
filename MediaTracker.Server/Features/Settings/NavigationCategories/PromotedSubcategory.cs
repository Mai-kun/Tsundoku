using System.Text.Json.Serialization;

namespace MediaTracker.Server.Features.Settings.NavigationCategories;

/// <summary>Способы сопоставления элемента библиотеки с вынесенной подкатегорией.</summary>
public static class PromotedMatchKind
{
    public const string Format = "format";
    public const string Genre = "genre";
    public const string Tag = "tag";

    public static readonly string[] All = [Format, Genre, Tag];

    /// <summary>Формат издания хранится только у Book и Manga.</summary>
    public static readonly string[] FormatCapableParents = ["Book", "Manga"];
}

/// <summary>
/// Виртуальная категория боковой навигации, вынесенная из родительского типа медиа: часть
/// элементов «Книг» (комиксы, ранобэ) показывается как отдельный раздел и исчезает из
/// родительской категории, пока подкатегория активна. Аналог выноса «Аниме» из
/// «Сериалов»/«Фильмов», но конфигурируемый пользователем.
/// </summary>
/// <param name="Id">Slug категории в навигации ("comics", "light-novels").</param>
/// <param name="Label">Отображаемое название ("Комиксы").</param>
/// <param name="Icon">Имя иконки из согласованного набора фронтенда.</param>
/// <param name="ParentType">Родительский MediaType ("Book", "Manga", "Game", "TvShow", "Movie").</param>
/// <param name="MatchKind">format | genre | tag.</param>
/// <param name="MatchValue">Значение для сопоставления ("comics", "Комиксы", "light_novel").</param>
public sealed record PromotedSubcategory(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("label")] string Label,
    [property: JsonPropertyName("icon")] string Icon,
    [property: JsonPropertyName("parentType")] string ParentType,
    [property: JsonPropertyName("matchKind")] string MatchKind,
    [property: JsonPropertyName("matchValue")] string MatchValue)
{
    public static readonly string[] ReservedIds = ["anime", "home", "stats", "lists", "history", "calendar", "goals", "settings", "detail", "seasons"];
    public static readonly string[] KnownParents = ["Book", "Manga", "Game", "TvShow", "Movie"];

    /// <summary>Базовые категории навигации, которые нельзя перекрывать вынесенными.</summary>
    public static readonly string[] BaseCategories =
        ["tvshow", "movie", "anime", "manga", "game", "book"];

    /// <summary>
    /// Нормализует пользовательский ввод (slug, регистр родителя, вид сопоставления) и возвращает
    /// ошибку валидации либо нормализованную копию. Список категорий проверяется целиком в
    /// <see cref="NormalizeList"/> — там же ловятся дубликаты id.
    /// </summary>
    public static (PromotedSubcategory? Category, string? Error) Normalize(PromotedSubcategory category)
    {
        var id = category.Id?.Trim().ToLowerInvariant() ?? string.Empty;
        if (id.Length is < 2 or > 40 || !IsSlug(id))
        {
            return (null, $"Subcategory id '{category.Id}' must be a 2-40 char slug (a-z, 0-9, '-').");
        }

        if (BaseCategories.Contains(id) || ReservedIds.Contains(id))
        {
            return (null, $"Subcategory id '{id}' collides with a built-in navigation category.");
        }

        var label = category.Label?.Trim() ?? string.Empty;
        if (label.Length is 0 or > 64)
        {
            return (null, "Subcategory label is required (1-64 chars).");
        }

        var icon = string.IsNullOrWhiteSpace(category.Icon) ? "bookmark" : category.Icon.Trim();

        var parent = NormalizeParentType(category.ParentType);
        if (parent is null)
        {
            return (null,
                $"Parent type '{category.ParentType}' is not a media type. Expected one of: {string.Join(", ", KnownParents)}.");
        }

        var kind = category.MatchKind?.Trim().ToLowerInvariant() ?? string.Empty;
        if (!PromotedMatchKind.All.Contains(kind))
        {
            return (null, $"Match kind '{category.MatchKind}' is not supported. Expected: format, genre or tag.");
        }

        if (kind == PromotedMatchKind.Format && !PromotedMatchKind.FormatCapableParents.Contains(parent))
        {
            return (null, $"Match kind 'format' is only available for {string.Join(" and ", PromotedMatchKind.FormatCapableParents)}.");
        }

        var value = category.MatchValue?.Trim() ?? string.Empty;
        if (value.Length is 0 or > 120)
        {
            return (null, "Match value is required (1-120 chars).");
        }

        return (new PromotedSubcategory(id, label, icon, parent, kind, value), null);
    }

    /// <summary>Валидирует весь список: нормализация каждого элемента + уникальность id.</summary>
    public static (PromotedSubcategory[] Categories, string? Error) NormalizeList(
        IEnumerable<PromotedSubcategory> categories)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<PromotedSubcategory>();
        foreach (var category in categories)
        {
            var (normalized, error) = Normalize(category);
            if (error is not null)
            {
                return ([], error);
            }

            if (!seen.Add(normalized!.Id))
            {
                return ([], $"Subcategory id '{normalized.Id}' is duplicated.");
            }

            result.Add(normalized);
        }

        return (result.ToArray(), null);
    }

    /// <summary>Приводит slug родителя ("book") к каноническому MediaType ("Book").</summary>
    public static string? NormalizeParentType(string? parentType)
    {
        var value = parentType?.Trim() ?? string.Empty;
        return KnownParents.FirstOrDefault(p =>
            p.Equals(value, StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsSlug(string id) =>
        id.All(c => char.IsAsciiLetterOrDigit(c) || c == '-');
}
