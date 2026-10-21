using MediaTracker.Server.Domain.Common;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Http;

/// <summary>
/// The seam between the domain's <see cref="Result"/> and the wire. Every failure is mapped by
/// <see cref="HttpResultMapper.CreateProblem"/>, so the same error type answers the same status from
/// every slice. The Task overloads exist because handlers return the awaited domain result.
/// </summary>
public static class ResultEndpointExtensions
{
    public static Results<Ok<TValue>, ProblemHttpResult> ToOk<TValue>(this Result<TValue> result) =>
        result is { IsSuccess: true, Value: { } value }
            ? TypedResults.Ok(value)
            : ToProblem(result.Error!);

    public static Results<Created<TValue>, ProblemHttpResult> ToCreated<TValue>(
        this Result<TValue> result,
        string uri) =>
        result is { IsSuccess: true, Value: { } value }
            ? TypedResults.Created(uri, value)
            : ToProblem(result.Error!);

    public static Results<NoContent, ProblemHttpResult> ToNoContent(this Result result) =>
        result is { IsSuccess: true }
            ? TypedResults.NoContent()
            : ToProblem(result.Error!);

    public static async Task<Results<Ok<TValue>, ProblemHttpResult>> ToOk<TValue>(
        this Task<Result<TValue>> result) =>
        (await result.ConfigureAwait(false)).ToOk();

    public static async Task<Results<Created<TValue>, ProblemHttpResult>> ToCreated<TValue>(
        this Task<Result<TValue>> result,
        string uri) =>
        (await result.ConfigureAwait(false)).ToCreated(uri);

    public static async Task<Results<NoContent, ProblemHttpResult>> ToNoContent(
        this Task<Result> result) =>
        (await result.ConfigureAwait(false)).ToNoContent();

    private static ProblemHttpResult ToProblem(Error error) =>
        TypedResults.Problem(HttpResultMapper.CreateProblem(error));
}
