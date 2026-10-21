using FluentValidation;

namespace MediaTracker.Server.Features.Media.UpdateProgress;

public sealed class UpdateProgressRequestValidator : AbstractValidator<UpdateProgressRequest>
{
    public UpdateProgressRequestValidator()
    {
        RuleFor(x => x.CurrentProgress)
            .GreaterThanOrEqualTo(0);
    }
}
