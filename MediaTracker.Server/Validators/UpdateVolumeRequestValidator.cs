using FluentValidation;
using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Validators;

public sealed class UpdateVolumeRequestValidator : AbstractValidator<UpdateVolumeRequest>
{
    public UpdateVolumeRequestValidator()
    {
        RuleFor(x => x.Title)
            .MaximumLength(250)
            .When(x => x.Title is not null);

        RuleFor(x => x.TotalPages)
            .GreaterThanOrEqualTo(0)
            .When(x => x.TotalPages.HasValue);

        RuleFor(x => x.CurrentPage)
            .GreaterThanOrEqualTo(0)
            .When(x => x.CurrentPage.HasValue);

        RuleFor(x => x.TotalChapters)
            .GreaterThanOrEqualTo(0)
            .When(x => x.TotalChapters.HasValue);

        RuleFor(x => x.CurrentChapter)
            .GreaterThanOrEqualTo(0)
            .When(x => x.CurrentChapter.HasValue);

        RuleFor(x => x.Score)
            .InclusiveBetween(1, 10)
            .When(x => x.Score.HasValue);
    }
}
