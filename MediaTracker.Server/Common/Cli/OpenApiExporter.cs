using System.Globalization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi;

namespace MediaTracker.Server.Common.Cli;

/// <summary>
/// CLI-экспорт OpenAPI-схемы (--export-openapi): документ генерируется в памяти из зарегистрированных
/// Minimal API эндпоинтов. Схемы DTO берутся из source-gen метаданных AppJsonSerializerContext через
/// TypeInfoResolverChain — без System.Text.Json рефлексии, поэтому путь остаётся AOT-совместимым.
/// Хост никогда не стартует (StartAsync не вызывается): Kestrel не занимает порт, трей, браузер и
/// фоновые воркеры не запускаются, миграции реальной БД не выполняются.
/// </summary>
public static class OpenApiExporter
{
    public static async Task<int> WriteAsync(WebApplication app, string outputPath, string tempDataDirectory)
    {
        // AddOpenApi регистрирует IOpenApiDocumentProvider как keyed-сервис с ключом = имени
        // документа ("v1" по умолчанию), поэтому резолвим через GetRequiredKeyedService.
        var openApiOptions = app.Services.GetRequiredService<IOptions<OpenApiOptions>>().Value;
        var provider = app.Services.GetRequiredKeyedService<IOpenApiDocumentProvider>(openApiOptions.DocumentName);
        var document = await provider.GetOpenApiDocumentAsync(CancellationToken.None);

        // Сериализуем в ту же версию спецификации, в которой документ был собран генератором
        // (OpenApiOptions.OpenApiVersion), чтобы JSON совпадал с тем, что отдаёт /openapi/v1.json.
        var specVersion = openApiOptions.OpenApiVersion;

        var fullPath = Path.GetFullPath(outputPath);
        var directory = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        using var textWriter = new StringWriter(CultureInfo.InvariantCulture);
        // OpenApiJsonWriter (Microsoft.OpenApi 2.x) не IDisposable — StringWriter закрывает буфер.
        var jsonWriter = new OpenApiJsonWriter(textWriter);
        document.SerializeAs(specVersion, jsonWriter);
        await File.WriteAllTextAsync(fullPath, textWriter.ToString(), CancellationToken.None);

        Console.WriteLine($"Tsundoku: OpenAPI schema written to '{fullPath}'.");
        Console.WriteLine(
            $"Tsundoku: {document.Paths?.Count ?? 0} paths, {document.Components?.Schemas?.Count ?? 0} schemas, " +
            $"securitySchemes: {string.Join(", ", document.Components?.SecuritySchemes?.Keys ?? [])}.");

        // Изолированный режим больше ничего не читает из временной папки данных — прибираем.
        try
        {
            Directory.Delete(tempDataDirectory, recursive: true);
        }
        catch
        {
            // Best effort cleanup: занятые/залоченные файлы не должны ронять успешный экспорт.
        }

        return 0;
    }
}
