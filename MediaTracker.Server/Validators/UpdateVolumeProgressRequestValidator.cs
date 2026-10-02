using FluentValidation;
using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Validators;

public sealed class UpdateVolumeProgressRequestValidator : AbstractValidator<UpdateVolumeProgressRequest>
{
    public UpdateVolumeProgressRequestValidator()
    {
        RuleFor(x => x.CurrentPage)
            .GreaterThanOrEqualTo(0)
            .When(x => x.CurrentPage.HasValue);

        RuleFor(x => x.CurrentChapter)
            .GreaterThanOrEqualTo(0)
            .When(x => x.CurrentChapter.HasValue);
    }
}
