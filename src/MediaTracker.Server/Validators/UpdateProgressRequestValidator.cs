using FluentValidation;
using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Validators;

public sealed class UpdateProgressRequestValidator : AbstractValidator<UpdateProgressRequest>
{
    public UpdateProgressRequestValidator()
    {
        RuleFor(x => x.CurrentProgress)
            .GreaterThanOrEqualTo(0);
    }
}