using MediaTracker.Server.Domain.Common;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Http;

/// <summary>
/// Translates a domain <see cref="Result"/> into an <see cref="IResult"/> and owns the single
/// error-type-to-status-code mapping, so every slice answers a given business failure identically.
/// </summary>
public static class HttpResultMapper
{
    public const string NotFoundTitle = ProblemDetailsFactory.NotFoundTitle;

    public static IResult ToHttpResult<T>(this Result<T> result) =>
        result is { IsSuccess: true } ? Results.Ok(result.Value) : result.Problem();

    public static IResult ToHttpResult<T>(this Result<T> result, string createdAtRoute) =>
        result is { IsSuccess: true } ? Results.Created(createdAtRoute, result.Value) : result.Problem();

    public static IResult ToHttpResult(this Result result) =>
        result is { IsSuccess: true } ? Results.NoContent() : result.Problem();

    public static IResult Problem(this Result result) => Problem(result.Error!);

    /// <summary>Maps a business failure onto the response shape it deserves.</summary>
    public static IResult Problem(Error error) =>
        error.Type switch
        {
            ErrorType.Validation when error.Fields is { Count: > 0 } =>
                Results.ValidationProblem(
                    error.Fields.ToDictionary(pair => pair.Key, pair => pair.Value)),

            ErrorType.Unavailable => Results.Json(
                ProblemDetailsFactory.Create(error, StatusCodes.Status502BadGateway),
                statusCode: StatusCodes.Status502BadGateway),

            _ => Results.Problem(CreateProblem(error)),
        };

    /// <summary>The problem document (carrying the status) a failure travels as.</summary>
    public static ProblemDetails CreateProblem(Error error) =>
        error.Type switch
        {
            ErrorType.Validation when error.Fields is { Count: > 0 } => ProblemDetailsFactory.Validation(error),
            ErrorType.Validation => ProblemDetailsFactory.Create(error, StatusCodes.Status400BadRequest),
            ErrorType.NotFound => ProblemDetailsFactory.NotFound(error),
            ErrorType.Conflict => ProblemDetailsFactory.Create(error, StatusCodes.Status409Conflict),
            ErrorType.Unsupported => ProblemDetailsFactory.Create(error, StatusCodes.Status400BadRequest),
            ErrorType.Unavailable => ProblemDetailsFactory.Create(error, StatusCodes.Status502BadGateway),
            _ => ProblemDetailsFactory.Create(error, StatusCodes.Status400BadRequest),
        };
}
