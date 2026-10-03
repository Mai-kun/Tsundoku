using FluentValidation;

namespace MediaTracker.Server.Features.Volumes.AddVolume;

public sealed class CreateVolumeRequestValidator : AbstractValidator<CreateVolumeRequest>
{
    public CreateVolumeRequestValidator()
    {
        RuleFor(x => x.Title)
            .NotEmpty()
            .MaximumLength(250);

        RuleFor(x => x.VolumeNumber)
            .GreaterThanOrEqualTo(0);

        RuleFor(x => x.TotalPages)
            .GreaterThanOrEqualTo(0);

        RuleFor(x => x.CurrentPage)
            .GreaterThanOrEqualTo(0);

        RuleFor(x => x.TotalChapters)
            .GreaterThanOrEqualTo(0);

        RuleFor(x => x.CurrentChapter)
            .GreaterThanOrEqualTo(0);

        RuleFor(x => x.Score)
            .InclusiveBetween(1, 10)
            .When(x => x.Score.HasValue);
    }
}
