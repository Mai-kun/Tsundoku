import type { JobProgress } from "$shared/types";

/** A finished job stays visible long enough for the eye to catch the 100% before it vanishes. */
const COMPLETED_TTL_MS = 4000;

const isActive = (job: JobProgress) =>
    job.status === "Running" || job.status === "Queued";

/**
 * The single live view of the background queue. A plain EventSource on the native API rather than a
 * library: the server already speaks `text/event-stream`, and reconnection is the browser's job.
 */
class JobsClient {
    jobs = $state<JobProgress[]>([]);
    activeCount = $derived(this.jobs.filter(isActive).length);

    #source: EventSource | null = null;
    #evictionTimers = new Map<string, ReturnType<typeof setTimeout>>();

    connect() {
        // The socket is opened lazily so importing this module never touches the network from a
        // non-browser context (the self-check scripts import the same graph).
        if (this.#source || typeof window === "undefined") return;

        const source = new EventSource("/api/jobs/stream");
        this.#source = source;
        source.onmessage = (event) => this.#apply(event.data);
    }

    disconnect() {
        this.#source?.close();
        this.#source = null;
    }

    cancel(jobId: string) {
        return fetch(`/api/jobs/${jobId}/cancel`, { method: "POST" }).catch(
            (error) => console.error("Failed to cancel job", jobId, error),
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
        if (index === -1) {
            this.jobs = [...this.jobs, job];
        } else {
            // Every event carries the full state, so this replaces rather than merges.
            this.jobs = this.jobs.map((entry) =>
                entry.jobId === job.jobId ? job : entry,
            );
        }

        if (isActive(job)) return;

        const previous = this.#evictionTimers.get(job.jobId);
        if (previous) clearTimeout(previous);

        this.#evictionTimers.set(
            job.jobId,
            setTimeout(() => {
                this.#evictionTimers.delete(job.jobId);
                this.jobs = this.jobs.filter((entry) => entry.jobId !== job.jobId);
            }, COMPLETED_TTL_MS),
        );
    }
}

export const jobsClient = new JobsClient();