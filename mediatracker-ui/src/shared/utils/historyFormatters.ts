import { Flag, Play, Plus, Star, Trash2 } from "$shared/ui/Icons";
import { i18n } from "$shared/i18n/index.svelte";
import type { HistoryEvent, HistoryEventType } from "$shared/types";

export function formatStatusName(status: string | null | undefined): string {
  if (!status) return "—";
  switch (status) {
    case "Planned":
    case "0":
      return i18n.t.status.planned;
    case "InProgress":
    case "1":
      return i18n.t.status.inProgress;
    case "Completed":
    case "2":
      return i18n.t.status.completed;
    case "OnHold":
    case "3":
      return i18n.t.status.paused;
    case "Dropped":
    case "4":
      return i18n.t.status.dropped;
    default:
      return status;
  }
}

export function formatScoreName(score: string | null | undefined): string {
  if (!score || score === "0") return "—";
  return `${score} ★`;
}

export function formatHistoryEventLabel(event: HistoryEvent): string {
  switch (event.type) {
    case "Added":
      return i18n.t.views.titleAdded;

    case "Deleted":
      return i18n.t.views.titleDeleted;

    case "StatusChanged": {
      const oldStatus = formatStatusName(event.oldValue);
      const newStatus = formatStatusName(event.newValue);
      return `${i18n.t.views.statusPrefix} ${oldStatus} → ${newStatus}`;
    }

    case "ScoreChanged": {
      const oldScore = formatScoreName(event.oldValue);
      const newScore = formatScoreName(event.newValue);
      return `${i18n.t.views.scorePrefix} ${oldScore} → ${newScore}`;
    }

    case "ProgressChanged": {
      const isPages =
        (event.oldValue &&
          (event.oldValue.includes("стр") ||
            event.oldValue.includes("pp") ||
            event.oldValue.includes("page"))) ||
        (event.newValue &&
          (event.newValue.includes("стр") ||
            event.newValue.includes("pp") ||
            event.newValue.includes("page")));
      const prefix = isPages ? i18n.t.views.readPrefix : i18n.t.views.progressPrefix;

      if (event.oldValue && event.newValue) {
        return `${prefix} ${event.oldValue} → ${event.newValue}`;
      }
      if (event.newValue) {
        return `${prefix} ${event.newValue}`;
      }
      return prefix;
    }

    case "AchievementUnlocked":
      return `${i18n.t.stats.achievements} ${event.newValue ?? ""}`.trim();

    default: {
      const parts: string[] = [event.type];
      if (event.oldValue) parts.push(`${event.oldValue} → `);
      if (event.newValue) parts.push(event.newValue);
      return parts.join(" ").trim();
    }
  }
}

export const HISTORY_EVENT_ICONS: Record<HistoryEventType, typeof Flag> = {
  Added: Plus,
  StatusChanged: Flag,
  ScoreChanged: Star,
  ProgressChanged: Play,
  Deleted: Trash2,
  AchievementUnlocked: Star,
};

export function formatHistoryTime(value: string): string {
  return new Intl.DateTimeFormat(i18n.current, {
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

export function formatHistoryDate(value: string): string {
  return new Intl.DateTimeFormat(i18n.current, {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(new Date(value));
}
