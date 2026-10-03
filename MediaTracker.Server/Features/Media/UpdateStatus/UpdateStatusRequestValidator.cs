using FluentValidation;

namespace MediaTracker.Server.Features.Media.UpdateStatus;

public sealed class UpdateStatusRequestValidator : AbstractValidator<UpdateStatusRequest>
{
    public UpdateStatusRequestValidator()
    {
        RuleFor(x => x.Status)
            .IsInEnum();
    }
}
