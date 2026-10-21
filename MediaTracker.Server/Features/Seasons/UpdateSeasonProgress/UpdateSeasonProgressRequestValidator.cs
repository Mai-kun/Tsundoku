using FluentValidation;

namespace MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;

public sealed class UpdateSeasonProgressRequestValidator : AbstractValidator<UpdateSeasonProgressRequest>
{
    public UpdateSeasonProgressRequestValidator()
    {
        RuleFor(x => x.CurrentEpisode)
            .GreaterThanOrEqualTo(0);
    }
}
