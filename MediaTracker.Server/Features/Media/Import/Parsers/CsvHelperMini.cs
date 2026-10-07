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
}
