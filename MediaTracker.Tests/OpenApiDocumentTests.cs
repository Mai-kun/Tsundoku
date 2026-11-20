using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Контракт OpenAPI-спецификации: документ строится из тех же регистраций эндпоинтов, что и
/// рабочий сервер (единый MapAllEndpoints в Program.cs), поэтому тест ловит появление новой
/// группы API без описания в схеме и потерю описания авторизации по токену.
/// </summary>
public class OpenApiDocumentTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public OpenApiDocumentTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Document_contains_all_API_endpoint_groups()
    {
        var document = await GetDocumentAsync();

        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/media"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/external"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/lists"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/settings"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/jobs"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/logs"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/goals"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/system"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/history"));
        // Сезоны и календарь вложены в группы: /api/seasons, /api/media/calendar*.
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/seasons"));
        document.Paths.Keys.Should().Contain(p => p.StartsWith("/api/media/calendar"));
    }

    [Fact]
    public async Task Document_describes_token_authorization_from_middleware()
    {
        var document = await GetDocumentAsync();

        // Ровно те способы передачи токена, что понимает ApiKeyAuthMiddleware:
        // Authorization: Bearer <token> или заголовок X-Api-Key.
        var schemes = document.Components!.SecuritySchemes!;
        schemes.Should().ContainKey("Bearer");
        schemes.Should().ContainKey("ApiKey");
        schemes["Bearer"].Type.Should().Be(SecuritySchemeType.Http);
        schemes["Bearer"].Scheme.Should().Be("bearer");
        schemes["ApiKey"].Type.Should().Be(SecuritySchemeType.ApiKey);
        schemes["ApiKey"].Name.Should().Be("X-Api-Key");
        schemes["ApiKey"].In.Should().Be(ParameterLocation.Header);
    }

    [Fact]
    public async Task Document_contains_sourcegen_DTO_schemas_and_serializes_to_valid_json()
    {
        var document = await GetDocumentAsync();

        // Схемы DTO идут из source-gen метаданных AppJsonSerializerContext — без рефлексии.
        document.Components!.Schemas!.Should().NotBeEmpty();
        document.Components.Schemas.Should().ContainKey("CreateMediaRequest");

        var specVersion = _factory.Services.GetRequiredService<IOptions<OpenApiOptions>>().Value.OpenApiVersion;
        using var textWriter = new StringWriter();
        var jsonWriter = new OpenApiJsonWriter(textWriter);
        document.SerializeAs(specVersion, jsonWriter);

        using var parsed = JsonDocument.Parse(textWriter.ToString());
        parsed.RootElement.TryGetProperty("openapi", out var version).Should().BeTrue();
        version.GetString().Should().StartWith("3.").And.NotBeNullOrEmpty();
    }

    private async Task<OpenApiDocument> GetDocumentAsync()
    {
        // AddOpenApi регистрирует IOpenApiDocumentProvider keyed-сервисом с ключом = имени документа.
        var provider = _factory.Services.GetRequiredKeyedService<IOpenApiDocumentProvider>("v1");
        return await provider.GetOpenApiDocumentAsync(CancellationToken.None);
    }
}
