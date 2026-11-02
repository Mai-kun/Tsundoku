<script lang="ts">
  import { Activity, X } from "$shared/ui/Icons";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import { getRateLimits } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { ApiRateLimitStatus, JobProgress } from "$shared/types";
  import { onMount } from "svelte";

  const popoverId = "activity-popover";

  let rateLimits = $state<ApiRateLimitStatus[]>([]);
  let timerId: number | null = null;
  let pollIntervalId: number | null = null;

  async function refreshRateLimits() {
    try {
      rateLimits = await getRateLimits();
    } catch {
      // Ignore polling errors
    }
  }

  function startRateLimitTracking() {
    void refreshRateLimits();
    stopRateLimitTracking();

    timerId = window.setInterval(() => {
      if (rateLimits.length === 0) return;
      rateLimits = rateLimits.map((item) => ({
        ...item,
        resetSecondsRemaining: Math.max(0, item.resetSecondsRemaining - 1),
      }));
    }, 1000);

    pollIntervalId = window.setInterval(() => {
      void refreshRateLimits();
    }, 10000);
  }

  function stopRateLimitTracking() {
    if (timerId !== null) {
      clearInterval(timerId);
      timerId = null;
    }
    if (pollIntervalId !== null) {
      clearInterval(pollIntervalId);
      pollIntervalId = null;
    }
  }

  function onPopoverToggle(event: ToggleEvent) {
    if (event.newState === "open") {
      startRateLimitTracking();
    } else {
      stopRateLimitTracking();
    }
  }

  // The queue is global and outlives any single view, so the socket is opened once on mount
  // rather than per panel open: closing the dropdown must not drop the progress feed.
  onMount(() => {
    jobsClient.connect();
    return () => {
      jobsClient.disconnect();
      stopRateLimitTracking();
    };
  });

  let popoverElement = $state<HTMLDivElement | null>(null);

  function openProcesses(tab: "jobs" | "review") {
    popoverElement?.hidePopover();
    jobsClient.openModal(tab);
  }

  function statusLabel(job: JobProgress): string {
    switch (job.status) {
      case "Queued":
        return i18n.t.activity.queued;
      case "Completed":
        return i18n.t.activity.completed;
      case "Failed":
        return i18n.t.activity.failed;
      case "Cancelled":
        return i18n.t.activity.cancelled;
      default:
        return job.currentStep;
    }
  }

  function isCancellable(job: JobProgress): boolean {
    return job.status === "Queued" || job.status === "Running";
  }
</script>

<div class="relative" style="anchor-name: --activity-anchor">
  <button
    type="button"
    popovertarget={popoverId}
    aria-label={i18n.t.activity.open}
    title={i18n.t.activity.open}
    class="bg-elevated text-muted hover:text-ink relative inline-flex h-9 w-9 cursor-pointer items-center justify-center rounded-lg border border-white/[0.08] transition hover:border-indigo-500/40 focus:ring-1 focus:ring-indigo-500/30 focus:outline-none"
  >
    <Activity
      size={17}
      class={jobsClient.activeCount > 0 ? "animate-[spin_3s_linear_infinite]" : ""}
      aria-hidden="true"
    />
    {#if jobsClient.activeCount > 0}
      <span
        class="absolute -top-1 -right-1 min-w-4 rounded-full bg-[#5844e0] px-1 text-[10px] leading-4 font-bold text-white tabular-nums"
      >
        {jobsClient.activeCount}
      </span>
    {:else if jobsClient.pendingCount > 0}
      <span
        class="absolute -top-1 -right-1 min-w-4 rounded-full bg-amber-500 px-1 text-[10px] leading-4 font-bold text-black tabular-nums"
      >
        {jobsClient.pendingCount}
      </span>
    {/if}
  </button>

  <div
    id={popoverId}
    bind:this={popoverElement}
    ontoggle={onPopoverToggle}
    popover="auto"
    role="dialog"
    aria-label={i18n.t.activity.label}
    class="z-30 mt-2 w-80 rounded-lg border border-white/10 bg-[#181b24] p-3 shadow-2xl shadow-black/70 outline-none sm:w-96"
    style="position: fixed; inset: auto; margin: 0; position-anchor: --activity-anchor; top: calc(anchor(bottom) + 8px); right: anchor(right);"
  >
    <div class="mb-2 flex items-center justify-between gap-2">
      <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
        {i18n.t.activity.label}
      </h2>
      {#if jobsClient.activeCount > 0}
        <span
          class="rounded-full bg-[#5844e0]/20 px-2 py-0.5 text-[10px] font-bold text-[#8f7fff] tabular-nums"
        >
          {jobsClient.activeCount}
        </span>
      {/if}
    </div>

    {#if jobsClient.pendingCount > 0}
      <button
        type="button"
        class="mb-2 flex w-full cursor-pointer items-center justify-center gap-2 rounded-md bg-amber-500 px-3 py-2 text-xs font-bold text-black transition hover:bg-amber-400"
        onclick={() => openProcesses("review")}
      >
        {i18n.t.backgroundJobs.pendingCount(jobsClient.pendingCount)}
      </button>
    {/if}

    {#if jobsClient.jobs.length === 0}
      <div class="px-1 py-6 text-center">
        <p class="text-ink text-sm font-medium">{i18n.t.activity.empty}</p>
        <p class="text-muted mt-1 text-xs">
          {i18n.t.activity.emptyHint}
        </p>
      </div>
    {:else}
      <ul class="max-h-80 space-y-2 overflow-y-auto">
        {#each jobsClient.jobs as job (job.jobId)}
          <li class="rounded-md border border-white/[0.06] bg-white/[0.03] p-2.5">
            <div class="flex items-center gap-2">
              <p class="text-ink min-w-0 flex-1 truncate text-xs font-semibold" title={job.title}>
                {job.title}
              </p>
              {#if isCancellable(job)}
                <button
                  type="button"
                  class="tap text-muted grid h-6 w-6 shrink-0 cursor-pointer place-items-center rounded-full transition hover:bg-rose-500/20 hover:text-rose-300 focus:ring-1 focus:ring-rose-500/40 focus:outline-none"
                  title={i18n.t.activity.cancel}
                  aria-label={i18n.t.activity.cancelAria(job.title)}
                  onclick={() => void jobsClient.cancel(job.jobId)}
                >
                  <X size={13} aria-hidden="true" />
                </button>
              {/if}
            </div>
            <div
              class="mt-2 h-1 overflow-hidden rounded-full bg-white/[0.08]"
              role="progressbar"
              aria-label={job.title}
              aria-valuenow={job.progressPercent}
              aria-valuemin="0"
              aria-valuemax="100"
            >
              <div
                class="h-full w-full origin-left rounded-full bg-[#5844e0] transition-transform duration-300 ease-out"
                style={`transform: scaleX(${job.progressPercent / 100})`}
              ></div>
            </div>

            <div class="mt-1.5 flex items-center justify-between gap-2 text-[11px]">
              <span class="truncate {job.status === 'Failed' ? 'text-rose-300' : 'text-muted'}">
                {job.errorMessage ?? statusLabel(job)}
              </span>
              <span class="shrink-0 font-medium text-slate-400 tabular-nums">
                {job.progressPercent}%
              </span>
            </div>
          </li>
        {/each}
      </ul>
    {/if}

    {#if rateLimits.length > 0}
      <div class="mt-3 border-t border-white/[0.08] pt-2.5">
        <h3 class="mb-2 text-[11px] font-bold tracking-wider text-slate-400 uppercase">
          {i18n.t.activity.rateLimitsTitle}
        </h3>
        <div class="space-y-2">
          {#each rateLimits as limit (limit.provider)}
            {@const ratio =
              limit.limit > 0 ? limit.remaining / limit.limit : limit.remaining > 0 ? 1 : 0}
            {@const percent = Math.max(0, Math.min(100, Math.round(ratio * 100)))}
            {@const barColor =
              limit.remaining <= 0
                ? "bg-rose-500"
                : ratio < 0.3
                  ? "bg-amber-500"
                  : "bg-emerald-500"}
            <div class="rounded-md border border-white/[0.06] bg-white/[0.03] p-2">
              <div class="flex items-center justify-between gap-2 text-xs">
                <span class="truncate font-medium text-slate-200">{limit.provider}</span>
                <span class="text-[11px] font-medium text-slate-400 tabular-nums">
                  {i18n.t.activity.remaining(limit.remaining, limit.limit)}
                </span>
              </div>
              <div
                class="mt-1.5 h-1 overflow-hidden rounded-full bg-white/[0.08]"
                role="progressbar"
                aria-label={limit.provider}
                aria-valuenow={percent}
                aria-valuemin="0"
                aria-valuemax="100"
              >
                <div
                  class="h-full rounded-full transition duration-300 ease-out {barColor}"
                  style="width: {percent}%"
                ></div>
              </div>
              <div class="text-muted mt-1 flex items-center justify-between text-[10px]">
                <span>
                  {limit.resetSecondsRemaining > 0
                    ? i18n.t.activity.resetInSeconds(limit.resetSecondsRemaining)
                    : i18n.t.activity.resetReady}
                </span>
                <span class="font-mono tabular-nums">{percent}%</span>
              </div>
            </div>
          {/each}
        </div>
      </div>
    {/if}

    <button
      type="button"
      class="bg-field text-ink hover:bg-elevated mt-3 flex w-full cursor-pointer items-center justify-center gap-2 rounded-md border border-white/10 px-3 py-2 text-xs font-semibold transition hover:text-white"
      onclick={() => openProcesses("jobs")}
    >
      {i18n.t.backgroundJobs.openWindow}
    </button>
  </div>
</div>
