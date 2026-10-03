using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Keeps started/finished timestamps and type-specific progress counters consistent with a status
/// change, so a "completed" show does not keep un-watched seasons. The rules themselves live on the
/// entities; this entry point exists for callers that hold a <see cref="MediaItem"/> base reference.
/// </summary>
public static class MediaStatusTransitions
{
    public static void Apply(MediaItem item, MediaStatus status) => item.ChangeStatus(status);
}
