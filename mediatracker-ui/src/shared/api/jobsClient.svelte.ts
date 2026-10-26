import type { JobProgress, PendingMatchItemDto } from "$shared/types";
import { getPendingMatches } from "$shared/api/api";

/** A finished job stays visible long enough for the eye to catch the 100% before it vanishes. */
const COMPLETED_TTL_MS = 4000;

/**
 * The queue '+ results' pair must not be hammered on every SSE tick: a running batch job re-reads
 * the review list at most this often, so the count shows up within seconds, not twice a second.
 */
const PENDING_REFRESH_MS = 5000;

const isActive = (job: JobProgress) => job.status === "Running" || job.status === "Queued";

/**
 * The single live view of the background queue. A plain EventSource on the native API rather than a
 * library: the server already speaks `text/event-stream`, and reconnection is the browser's job.
 */
class JobsClient {
  jobs = $state<JobProgress[]>([]);
  activeCount = $derived(this.jobs.filter(isActive).length);

  /** "Фоновые процессы" modal visibility and its active tab. */
  isModalOpen = $state(false);
  modalTab = $state<"jobs" | "review">("jobs");

  /** Titles the enrichment job could not match confidently; the user picks one or skips. */
  pendingMatches = $state<PendingMatchItemDto[]>([]);
  pendingCount = $derived(this.pendingMatches.length);

  #source: EventSource | null = null;
  #evictionTimers = new Map<string, ReturnType<typeof setTimeout>>();
  #pendingRefreshedAt = 0;
  #pendingSequence = 0;
  #jobSettledListeners = new Set<(job: JobProgress) => void>();

  onJobSettled(cb: (job: JobProgress) => void): () => void {
    this.#jobSettledListeners.add(cb);
    return () => this.#jobSettledListeners.delete(cb);
  }

  connect() {
    // The socket is opened lazily so importing this module never touches the network from a
    // non-browser context (the self-check scripts import the same graph).
    if (this.#source || typeof window === "undefined") return;

    const source = new EventSource("/api/jobs/stream");
    this.#source = source;
    source.onmessage = (event) => this.#apply(event.data);
    void this.refreshPendingMatches();
  }

  disconnect() {
    this.#source?.close();
    this.#source = null;
  }

  openModal(tab: "jobs" | "review" = "jobs") {
    this.modalTab = tab;
    this.isModalOpen = true;
    // The review list goes stale while the modal is closed; opening is the cheap moment to reread.
    void this.refreshPendingMatches();
  }

  closeModal() {
    this.isModalOpen = false;
  }

  /** Removes one resolved/skipped title from the review list without a round trip. */
  dropPendingMatch(id: string) {
    this.pendingMatches = this.pendingMatches.filter((item) => item.id !== id);
  }

  refreshPendingMatches(): Promise<void> {
    if (typeof window === "undefined") return Promise.resolve();
    this.#pendingRefreshedAt = Date.now();
    const sequence = ++this.#pendingSequence;
    return getPendingMatches()
      .then((items) => {
        // A stale response must not resurrect a title the user just resolved.
        if (sequence === this.#pendingSequence) this.pendingMatches = items;
      })
      .catch(() => {});
  }

  cancel(jobId: string) {
    return fetch(`/api/jobs/${jobId}/cancel`, { method: "POST" }).catch((error) =>
      console.error("Failed to cancel job", jobId, error),
    );
  }

  /** The job currently enriching this media item, if any. Drives the detail screen skeletons. */
  jobFor(mediaId: string): JobProgress | undefined {
    return this.jobs.find((job) => job.mediaId === mediaId);
  }

  #apply(raw: string) {
    let job: JobProgress;
    try {
      job = JSON.parse(raw) as JobProgress;
    } catch {
      return;
    }

    const index = this.jobs.findIndex((entry) => entry.jobId === job.jobId);
    const previous = index === -1 ? null : this.jobs[index];
    if (index === -1) {
      this.jobs = [...this.jobs, job];
    } else {
      // Every event carries the full state, so this replaces rather than merges.
      this.jobs = this.jobs.map((entry) => (entry.jobId === job.jobId ? job : entry));
    }

    const wasTerminal = previous !== null && !isActive(previous);
    const nowTerminal = !isActive(job);
    if (nowTerminal && !wasTerminal) {
      for (const listener of this.#jobSettledListeners) {
        try {
          listener(job);
        } catch (e) {
          console.error("Error in jobSettled listener", e);
        }
      }
    }

    const settled = previous !== null && isActive(previous) !== isActive(job);
    if (isActive(job)) {
      // A batch job re-checks ambiguous rows as it walks through the import.
      this.#refreshPendingMatchesThrottled(false);
    } else if (settled) {
      // Completed / failed / cancelled jobs can leave newly parked rows behind.
      this.#refreshPendingMatchesThrottled(true);
    }

    if (isActive(job)) return;

    const timer = this.#evictionTimers.get(job.jobId);
    if (timer) clearTimeout(timer);

    this.#evictionTimers.set(
      job.jobId,
      setTimeout(() => {
        this.#evictionTimers.delete(job.jobId);
        this.jobs = this.jobs.filter((entry) => entry.jobId !== job.jobId);
      }, COMPLETED_TTL_MS),
    );
  }

  #refreshPendingMatchesThrottled(force: boolean) {
    const now = Date.now();
    if (!force && now - this.#pendingRefreshedAt < PENDING_REFRESH_MS) return;
    void this.refreshPendingMatches();
  }
}

export const jobsClient = new JobsClient();
