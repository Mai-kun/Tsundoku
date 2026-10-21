using MediaTracker.Server.Domain.Common;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Http;

/// <summary>
/// Produces the problem document a failure travels as. Keeping it here is what makes the same error
/// type answer identically from every slice.
/// </summary>
public static class ProblemDetailsFactory
{
    public const string FieldedValidationTitle = "One or more validation errors occurred.";
    public const string NotFoundTitle = "Resource not found.";

    public static ProblemDetails Create(Error error, int status, string? title = null) => new()
    {
        Title = title ?? error.Message,
        Detail = title is null ? null : error.Message,
        Status = status,
        Extensions = { ["code"] = error.Code },
    };

    public static ProblemDetails NotFound(Error error, string? title = null) =>
        Create(error, StatusCodes.Status404NotFound, title ?? NotFoundTitle);

    public static HttpValidationProblemDetails Validation(
        Error error,
        int status = StatusCodes.Status400BadRequest) =>
        new(error.Fields is { Count: > 0 } fields
            ? fields.ToDictionary(pair => pair.Key, pair => pair.Value)
            : new Dictionary<string, string[]> { ["request"] = [error.Message] })
        {
            Title = FieldedValidationTitle,
            Status = status,
            Extensions = { ["code"] = error.Code },
        };
}
