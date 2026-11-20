using System.Data;
using System.Data.Common;
using System.Globalization;
using System.Text;
using MediaTracker.Server.Features.Settings.NavigationCategories;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// SQL-фрагменты сопоставления «элемент библиотеки ↔ вынесенная подкатегория». Все значения
/// идут параметрами (никакой конкатенации пользовательских строк в SQL), условие считается
/// по элементу независимо от типа: формат издания — точным равенством колонки формата,
/// жанр/тег — точным совпадением элемента comma-списка.
/// </summary>
public static class PromotedSubcategorySql
{
    /// <summary>
    /// Условие совпадения строки MediaItems с подкатегорией. <paramref name="columnPrefix"/> —
    /// алиас таблицы в запросе ("m." или пустая строка).
    /// </summary>
    public static string MatchCondition(PromotedSubcategory sub, string columnPrefix)
    {
        var column = MatchColumn(sub.ParentType, sub.MatchKind);
        var param = ParameterName(sub);

        return sub.MatchKind switch
        {
            PromotedMatchKind.Format =>
                $"LOWER(COALESCE({columnPrefix}{column}, '')) = @{param}",
            // Жанры/теги хранятся comma-строкой; пробелы вырезаются с ОБЕИХ сторон (значение и
            // колонка), а границы элементов задаются запятыми в самой строке: "...,Комиксы,..."
            // содержит ",комиксы," но не ",комикс," — целый элемент, не подстрока. Сравнение
            // через contains_ci: встроенный LOWER()/LIKE в SQLite ASCII-only и не берёт кириллицу.
            PromotedMatchKind.Genre =>
                $"contains_ci(',' || REPLACE(COALESCE({columnPrefix}{column}, ''), ' ', '') || ',', ',' || @{param} || ',') = 1",
            PromotedMatchKind.Tag =>
                $"contains_ci(',' || REPLACE(COALESCE({columnPrefix}{column}, ''), ' ', '') || ',', ',' || @{param} || ',') = 1",
            _ => "1 = 0",
        };
    }

    /// <summary>Значение параметра условия (нормализация как в SQL-фрагменте).</summary>
    public static string ParameterValue(PromotedSubcategory sub) =>
        Needle(sub.MatchValue, sub.MatchKind);

    /// <summary>
    /// Готовый клауз исключения для WHERE/CASE без префикса колонок: "" когда подкатегорий нет,
    /// иначе " AND NOT (frag1 OR frag2)".
    /// </summary>
    public static string ExclusionClause(
        IReadOnlyList<PromotedSubcategory> subcategories,
        string columnPrefix) =>
        subcategories.Count == 0
            ? string.Empty
            : " AND NOT (" +
              string.Join(" OR ", subcategories.Select(s => MatchCondition(s, columnPrefix))) +
              ")";

    /// <summary>
    /// Имя параметра условия — по slug подкатегории: у двух форматов Book ("comics" и
    /// "light-novels") колонка одна, и имя параметра обязано различаться.
    /// </summary>
    public static string ParameterName(PromotedSubcategory sub) =>
        $"sub_{sub.Id.Replace('-', '_')}";

    /// <summary>
    /// Добавляет в запрос исключение всех активных подкатегорий родительского типа: элементы,
    /// попавшие в любую вынесенную категорию, из родительской выборки пропадают.
    /// </summary>
    public static void AppendExclusions(
        StringBuilder sb,
        IReadOnlyList<PromotedSubcategory> subcategories,
        string columnPrefix)
    {
        if (subcategories.Count == 0)
        {
            return;
        }

        sb.Append(ExclusionClause(subcategories, columnPrefix));
    }

    /// <summary>Привязывает параметры условий к команде (ADO.NET путь — списки и статистика).</summary>
    public static void BindParameters(DbCommand cmd, IEnumerable<PromotedSubcategory> subcategories)
    {
        foreach (var sub in subcategories)
        {
            cmd.Parameters.Add(new SqliteParameter(
                $"@{ParameterName(sub)}", ParameterValue(sub)));
        }
    }

    /// <summary>Привязывает параметры для Dapper-запросов статистики.</summary>
    public static void BindParameters(Dapper.DynamicParameters parameters, IEnumerable<PromotedSubcategory> subcategories)
    {
        foreach (var sub in subcategories)
        {
            parameters.Add($"@{ParameterName(sub)}", ParameterValue(sub));
        }
    }

    private static string Needle(string matchValue, string matchKind)
    {
        var value = matchValue.Trim().ToLower(CultureInfo.InvariantCulture);
        return matchKind == PromotedMatchKind.Format ? value : value.Replace(" ", string.Empty);
    }

    private static string MatchColumn(string parentType, string matchKind) =>
        (parentType, matchKind) switch
        {
            ("Book", PromotedMatchKind.Format) => "Book_Format",
            ("Book", PromotedMatchKind.Genre) => "Genres",
            ("Book", PromotedMatchKind.Tag) => "Tags",
            ("Manga", PromotedMatchKind.Format) => "Manga_Format",
            ("Manga", PromotedMatchKind.Genre) => "Genres",
            ("Manga", PromotedMatchKind.Tag) => "Tags",
            // У остальных типов нет колонок формата/тегов как у книг — жанр общий.
            (_, PromotedMatchKind.Genre) => "Genres",
            (_, PromotedMatchKind.Tag) => "Tags",
            _ => "Genres",
        };
}
