using System.Text;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class CsvHelperMini
{
    public static IReadOnlyList<string[]> Parse(string text)
    {
        var rows = new List<string[]>();
        var row = new List<string>();
        var field = new StringBuilder();
        var quoted = false;
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (quoted)
            {
                if (c == '"' && i + 1 < text.Length && text[i + 1] == '"') { field.Append('"'); i++; }
                else if (c == '"') quoted = false;
                else field.Append(c);
            }
            else if (c == '"' && field.Length == 0) quoted = true;
            else if (c == ',') { row.Add(field.ToString()); field.Clear(); }
            else if (c is '\r' or '\n')
            {
                if (c == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
                row.Add(field.ToString()); field.Clear();
                if (row.Any(value => value.Length > 0)) rows.Add(row.ToArray());
                row.Clear();
            }
            else field.Append(c);
        }
        if (field.Length > 0 || row.Count > 0) { row.Add(field.ToString()); rows.Add(row.ToArray()); }
        return rows;
    }

    public static IEnumerable<Dictionary<string, string>> ReadRecords(string text)
    {
        var rows = Parse(text);
        if (rows.Count < 2) yield break;
        var headers = rows[0].Select((value, index) => (value: value.Trim().TrimStart('\uFEFF'), index))
            .ToDictionary(x => x.value, x => x.index, StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows.Skip(1))
            yield return headers.ToDictionary(x => x.Key, x => x.Value < row.Length ? row[x.Value].Trim() : "", StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Script exports come as whichever the author felt like writing: a JSON array of flat objects or
    /// a CSV with a header row. Both reduce to the same case-insensitive row dictionaries so the
    /// callers don't branch on the format.
    /// </summary>
    public static IReadOnlyList<Dictionary<string, string>> ReadAnyRecords(string text)
    {
        var trimmed = text.TrimStart();
        return trimmed.StartsWith('[') || trimmed.StartsWith('{')
            ? ReadJsonRecords(trimmed)
            : ReadRecords(text).ToList();
    }

    private static IReadOnlyList<Dictionary<string, string>> ReadJsonRecords(string text)
    {
        using var document = global::System.Text.Json.JsonDocument.Parse(text);
        var root = document.RootElement;
        if (root.ValueKind == global::System.Text.Json.JsonValueKind.Object)
        {
            // Common wrappers used by export scripts; an unwrapped single object becomes one row.
            foreach (var wrapper in new[] { "data", "items", "list", "entries" })
                if (root.TryGetProperty(wrapper, out var nested) && nested.ValueKind == global::System.Text.Json.JsonValueKind.Array)
                    root = nested;
            if (root.ValueKind != global::System.Text.Json.JsonValueKind.Array)
                return [Flatten(root)];
        }
        if (root.ValueKind != global::System.Text.Json.JsonValueKind.Array)
            throw new FormatException("JSON must contain an array of records.");
        return [.. root.EnumerateArray().Where(item => item.ValueKind == global::System.Text.Json.JsonValueKind.Object).Select(Flatten)];
    }

    private static Dictionary<string, string> Flatten(global::System.Text.Json.JsonElement item)
    {
        var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var property in item.EnumerateObject())
            row[property.Name] = property.Value.ValueKind == global::System.Text.Json.JsonValueKind.String
                ? property.Value.GetString() ?? ""
                : property.Value.ToString();
        return row;
    }
}
