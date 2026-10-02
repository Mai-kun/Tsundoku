using FluentValidation;
using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Validators;

public sealed class UpdateSeasonProgressRequestValidator : AbstractValidator<UpdateSeasonProgressRequest>
{
    public UpdateSeasonProgressRequestValidator()
    {
        RuleFor(x => x.CurrentEpisode)
            .GreaterThanOrEqualTo(0);
    }
}