namespace MediaTracker.Server.Common.Json;

/// <summary>Typed replacements for the anonymous objects the endpoints used to serialize.</summary>

/// <summary><c>{"detail": "..."}</c> — the shape Results.BadRequest/NotFound carried for every client-facing error.</summary>
public sealed record ApiErrorDetail(string Detail);

/// <summary><c>{"id": "..."}</c> — the 201-Created body of POST /api/lists.</summary>
public sealed record CreatedEntityId(Guid Id);

/// <summary><c>{"dismissed": N}</c> — the count of rows POST /api/media/dismiss-all-matches reset.</summary>
public sealed record DismissedCount(int Dismissed);

/// <summary>GET /api/settings/storage response.</summary>
public sealed record StorageInfoResponse(
    string Mode,
    string DataDirectory,
    string PortableDirectory,
    string DefaultDirectory,
    bool IsFirstRunSetupRequired);
