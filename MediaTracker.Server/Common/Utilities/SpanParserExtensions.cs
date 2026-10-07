using System.Globalization;

namespace MediaTracker.Server.Common.Utilities;

public static class SpanParserExtensions
{
    public static int? ParseDurationMinutes(ReadOnlySpan<char> text)
    {
        text = text.Trim();
        if (text.IsEmpty)
        {
            return null;
        }

        var hourMarker = text.IndexOf('h');
        if (hourMarker < 0)
        {
            hourMarker = text.IndexOf('H');
        }

        var minuteMarker = text.IndexOf('m');
        if (minuteMarker < 0)
        {
            minuteMarker = text.IndexOf('M');
        }

        if (hourMarker < 0 && minuteMarker < 0)
        {
            return int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var total) ? total : null;
        }

        var hourText = hourMarker >= 0 ? text[..hourMarker].Trim() : ReadOnlySpan<char>.Empty;
        var minuteText = minuteMarker >= 0
            ? text[(hourMarker >= 0 ? hourMarker + 1 : 0)..minuteMarker].Trim()
            : ReadOnlySpan<char>.Empty;

        var hours = 0;
        var minutes = 0;
        if ((hourMarker >= 0 && !int.TryParse(hourText, NumberStyles.None, CultureInfo.InvariantCulture, out hours))
            || (minuteMarker >= 0 && !int.TryParse(minuteText, NumberStyles.None, CultureInfo.InvariantCulture, out minutes)))
        {
            return null;
        }

        return hours <= (int.MaxValue - minutes) / 60 ? hours * 60 + minutes : null;
    }

    public static int? ParseYearFromDateString(ReadOnlySpan<char> dateText) =>
        dateText.Length >= 4 && int.TryParse(dateText[..4], NumberStyles.None, CultureInfo.InvariantCulture, out var year)
            ? year
            : null;
}
