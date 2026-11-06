namespace MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

public interface ITranslationService
{
    Task<string> TranslateAsync(string text, string targetLanguage, CancellationToken ct = default);
}
