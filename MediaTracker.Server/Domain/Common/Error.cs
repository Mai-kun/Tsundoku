namespace MediaTracker.Server.Domain.Common;

public enum ErrorType
{
    Validation,
    NotFound,
    Conflict,
    Unsupported,
    Unavailable,
}

/// <summary>
/// A business failure carried as a value instead of an exception. Expected outcomes (a missing row,
/// a rejected payload, an unsupported media type) travel back through <see cref="Result{T}"/>.
/// </summary>
public sealed record Error
{
    private Error(ErrorType type, string code, string message, IReadOnlyDictionary<string, string[]>? fields)
    {
        Type = type;
        Code = code;
        Message = message;
        Fields = fields;
    }

    public ErrorType Type { get; }

    public string Code { get; }

    public string Message { get; }

    /// <summary>Field-level messages, present only for a payload the API should answer 400 for.</summary>
    public IReadOnlyDictionary<string, string[]>? Fields { get; }

    public static Error Validation(string message, IReadOnlyDictionary<string, string[]>? fields = null) =>
        new(ErrorType.Validation, "validation_failure", message, fields);

    public static Error Validation(IReadOnlyDictionary<string, string[]> fields) =>
        new(ErrorType.Validation, "validation_failure", "One or more validation errors occurred.", fields);

    public static Error NotFound(string message) =>
        new(ErrorType.NotFound, "not_found", message, null);

    public static Error Conflict(string message) =>
        new(ErrorType.Conflict, "conflict", message, null);

    public static Error Unsupported(string message) =>
        new(ErrorType.Unsupported, "unsupported", message, null);

    public static Error Unavailable(string message) =>
        new(ErrorType.Unavailable, "source_unavailable", message, null);
}
