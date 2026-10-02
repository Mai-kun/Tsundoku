using FluentValidation;
using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Validators;

public sealed class UpdateMediaRequestValidator : AbstractValidator<UpdateMediaRequest>
{
    public UpdateMediaRequestValidator()
    {
        RuleFor(x => x.Title)
            .NotEmpty()
            .MaximumLength(250)
            .When(x => x.Title is not null);

        RuleFor(x => x.Score)
            .InclusiveBetween(1, 10)
            .When(x => x.Score.HasValue);
    }
}