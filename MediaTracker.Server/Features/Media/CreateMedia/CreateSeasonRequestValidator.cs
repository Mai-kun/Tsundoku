using FluentValidation;

namespace MediaTracker.Server.Features.Media.CreateMedia;

public sealed class CreateSeasonRequestValidator : AbstractValidator<CreateSeasonRequest>
{
    public CreateSeasonRequestValidator()
    {
        RuleFor(x => x.SeasonNumber)
            .GreaterThanOrEqualTo(1);

        RuleFor(x => x.Title)
            .NotEmpty()
            .MaximumLength(250);

        RuleFor(x => x.TotalEpisodes)
            .GreaterThanOrEqualTo(0);

        RuleFor(x => x.Score)
            .InclusiveBetween(1, 10)
            .When(x => x.Score.HasValue);
    }
}
