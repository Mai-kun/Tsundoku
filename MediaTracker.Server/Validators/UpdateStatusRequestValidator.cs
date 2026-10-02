using FluentValidation;
using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Validators;

public sealed class UpdateStatusRequestValidator : AbstractValidator<UpdateStatusRequest>
{
    public UpdateStatusRequestValidator()
    {
        RuleFor(x => x.Status)
            .IsInEnum();
    }
}