using System.Diagnostics.CodeAnalysis;

namespace MediaTracker.Server.Domain.Common;

/// <summary>Marks a successful call that carries no payload.</summary>
public readonly record struct Unit
{
    public static readonly Unit Value = default;
}

/// <summary>
/// A value or a business failure. Handlers return this instead of throwing for expected outcomes,
/// so the endpoint layer only has to map a result onto an HTTP response.
/// </summary>
public class Result
{
    protected Result(bool isSuccess, Error? error)
    {
        IsSuccess = isSuccess;
        Error = error;
    }

    public bool IsSuccess { get; }

    public bool IsFailure => !IsSuccess;

    public Error? Error { get; }

    public static Result Success() => new(true, null);

    public static Result Failure(Error error) => new(false, error);
}

public sealed class Result<T> : Result
{
    private Result(bool isSuccess, T? value, Error? error)
        : base(isSuccess, error)
    {
        Value = value;
    }

    public T? Value { get; }

    public static Result<T> Success(T value) => new(true, value, null);

    public new static Result<T> Failure(Error error) => new(false, default, error);

    public bool TryGetValue([NotNullWhen(true)] out T? value)
    {
        value = Value;
        return IsSuccess;
    }

    public Result<TOut> Map<TOut>(Func<T, TOut> map) =>
        IsSuccess && Value is not null
            ? Result<TOut>.Success(map(Value))
            : Result<TOut>.Failure(Error!);

    public TOut Match<TOut>(Func<T, TOut> onSuccess, Func<Error, TOut> onFailure) =>
        IsSuccess && Value is not null ? onSuccess(Value) : onFailure(Error!);
}

public static class ResultExtensions
{
    public static Result<T> ToResult<T>(this T value) => Result<T>.Success(value);
}
