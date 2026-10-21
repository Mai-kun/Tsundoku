using System.Text.Json.Serialization;

namespace MediaTracker.Server.Features.Jobs;

/// <summary>
/// Serialised by name ("Running"), unlike <c>MediaStatus</c> which the REST surface sends as a
/// number: this one has no legacy shape to keep, and a readable event name is worth more than
/// packing two bytes.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter<JobStatus>))]
public enum JobStatus
{
    Queued = 0,
    Running = 1,
    Completed = 2,
    Failed = 3,
    Cancelled = 4,
}