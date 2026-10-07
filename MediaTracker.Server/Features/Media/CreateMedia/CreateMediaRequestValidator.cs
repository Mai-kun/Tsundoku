using FluentValidation;

namespace MediaTracker.Server.Features.Media.CreateMedia;

public sealed class CreateMediaRequestValidator : AbstractValidator<CreateMediaRequest>
{
    private static readonly HashSet<string> AllowedTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "game", "book", "manga", "movie", "tvshow",
    };

    public CreateMediaRequestValidator()
    {
        RuleFor(x => x.Type)
            .NotEmpty()
            .Must(AllowedTypes.Contains)
            .WithMessage("Type must be one of: game, book, manga, movie, tvshow.");

        RuleFor(x => x.Title)
            .NotEmpty()
            .MaximumLength(250);

        RuleFor(x => x.Score)
            .InclusiveBetween(1, 10)
            .When(x => x.Score.HasValue);

        RuleFor(x => x.HoursPlayed)
            .GreaterThanOrEqualTo(0)
            .When(x => x.HoursPlayed.HasValue);

        RuleFor(x => x.Platform)
            .NotEmpty()
            .When(x => IsType(x, "game"));

        RuleFor(x => x.Author)
            .NotEmpty()
            .When(x => IsType(x, "book"));

        RuleFor(x => x.TotalPages)
            .GreaterThanOrEqualTo(0)
            .When(x => x.TotalPages.HasValue);

        RuleFor(x => x.TotalChapters)
            .GreaterThanOrEqualTo(0)
            .When(x => x.TotalChapters.HasValue);

        RuleFor(x => x.CurrentVolume)
            .GreaterThanOrEqualTo(0)
            .When(x => x.CurrentVolume.HasValue);

        RuleFor(x => x.DurationMinutes)
            .GreaterThanOrEqualTo(0)
            .When(x => x.DurationMinutes.HasValue);

        RuleForEach(x => x.Seasons)
            .SetValidator(new CreateSeasonRequestValidator());
    }

    private static bool IsType(CreateMediaRequest request, string type) =>
        string.Equals(request.Type?.Trim(), type, StringComparison.OrdinalIgnoreCase);
}
