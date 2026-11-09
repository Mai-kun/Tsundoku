using System.Text.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.OpenLibrary;

public sealed class OpenLibraryDescriptionConverter : JsonConverter<string?>
{
    public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            return reader.GetString();
        }

        if (reader.TokenType == JsonTokenType.StartObject)
        {
            using var doc = JsonDocument.ParseValue(ref reader);
            if (doc.RootElement.TryGetProperty("value", out var valueProp) && valueProp.ValueKind == JsonValueKind.String)
            {
                return valueProp.GetString();
            }
            return null;
        }

        if (reader.TokenType == JsonTokenType.Null)
        {
            return null;
        }

        reader.Skip();
        return null;
    }

    public override void Write(Utf8JsonWriter writer, string? value, JsonSerializerOptions options)
    {
        if (value is null)
        {
            writer.WriteNullValue();
        }
        else
        {
            writer.WriteStringValue(value);
        }
    }
}

internal sealed record OpenLibraryResponse(List<OpenLibraryDoc>? Docs);

internal sealed record OpenLibraryDoc(
    string? Key,
    string? Title,
    [property: JsonPropertyName("author_name")] List<string>? AuthorName,
    [property: JsonPropertyName("cover_i")] int? CoverId,
    [property: JsonPropertyName("first_publish_year")] int? FirstPublishYear,
    [property: JsonPropertyName("subtitle")] string? Subtitle,
    [property: JsonPropertyName("subject")] List<string>? Subject,
    [property: JsonPropertyName("number_of_pages_median")] int? NumberOfPagesMedian,
    [property: JsonPropertyName("number_of_pages")] List<int>? NumberOfPages,
    [property: JsonPropertyName("ratings_average")] double? RatingsAverage,
    [property: JsonPropertyName("ratings_count")] int? RatingsCount,
    [property: JsonPropertyName("publisher")] List<string>? Publisher,
    [property: JsonPropertyName("physical_format")] string? PhysicalFormat,
    [property: JsonPropertyName("isbn")] List<string>? Isbn);

internal sealed class OpenLibraryWork
{
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("description")]
    [JsonConverter(typeof(OpenLibraryDescriptionConverter))]
    public string? Description { get; set; }

    [JsonPropertyName("covers")]
    public List<int>? Covers { get; set; }

    [JsonPropertyName("subjects")]
    public List<string>? Subjects { get; set; }
}

/// <summary>
/// Edition answer of <c>openlibrary.org/books/{id}.json</c> or <c>openlibrary.org/isbn/{isbn}.json</c>.
/// </summary>
internal sealed class OpenLibraryEdition
{
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("description")]
    [JsonConverter(typeof(OpenLibraryDescriptionConverter))]
    public string? Description { get; set; }

    [JsonPropertyName("publishers")]
    public List<string>? Publishers { get; set; }

    [JsonPropertyName("physical_format")]
    public string? PhysicalFormat { get; set; }

    [JsonPropertyName("number_of_pages")]
    public int? NumberOfPages { get; set; }

    [JsonPropertyName("isbn_10")]
    public List<string>? Isbn10 { get; set; }

    [JsonPropertyName("isbn_13")]
    public List<string>? Isbn13 { get; set; }

    [JsonPropertyName("covers")]
    public List<int>? Covers { get; set; }

    [JsonPropertyName("works")]
    public List<OpenLibraryWorkRef>? Works { get; set; }
}

internal sealed class OpenLibraryWorkRef
{
    [JsonPropertyName("key")]
    public string? Key { get; set; }
}
