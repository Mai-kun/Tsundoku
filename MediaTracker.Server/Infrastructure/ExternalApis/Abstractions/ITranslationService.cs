namespace MediaTracker.Server.Infrastructure.ExternalApis;

public interface ITranslationService
{
    Task<string> TranslateAsync(string text, string targetLanguage, CancellationToken ct = default);
}
