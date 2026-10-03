using FluentValidation.Results;
using MediaTracker.Server.Domain.Common;

namespace MediaTracker.Server.Common.Http;

/// <summary>
/// Turns a FluentValidation result into a domain <see cref="Error"/>. Slices call this once instead of
/// each re-implementing the "invalid payload -> ValidationProblem" translation.
/// </summary>
public static class ValidationErrorFactory
{
    public static Error? ToError(this ValidationResult validationResult)
    {
        if (validationResult.IsValid)
        {
            return null;
        }

        var fields = new Dictionary<string, string[]>(StringComparer.Ordinal);

        foreach (var failure in validationResult.Errors)
        {
            var key = string.IsNullOrWhiteSpace(failure.PropertyName) ? "request" : failure.PropertyName;

            if (fields.TryGetValue(key, out var existing))
            {
                var merged = new string[existing.Length + 1];
                existing.CopyTo(merged, 0);
                merged[^1] = failure.ErrorMessage;
                fields[key] = merged;
            }
            else
            {
                fields[key] = [failure.ErrorMessage];
            }
        }

        return Error.Validation(fields);
    }
}
