using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.External.TranslateText;

public sealed record TranslateTextCommand(string? Text, string? TargetLanguage);

public sealed record TranslateResponse(string TranslatedText);

public interface ITranslateTextHandler
{
    Task<Result<TranslateResponse>> HandleAsync(TranslateTextCommand command, CancellationToken ct);
}

public sealed class TranslateTextHandler(ITranslationService translationService) : ITranslateTextHandler
{
    public async Task<Result<TranslateResponse>> HandleAsync(
        TranslateTextCommand command,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(command.Text))
        {
            return Result<TranslateResponse>.Failure(Error.Validation("Text is required."));
        }

        var translated = await translationService.TranslateAsync(
            command.Text,
            command.TargetLanguage ?? "ru",
            ct);

        return Result<TranslateResponse>.Success(new TranslateResponse(translated));
    }
}
