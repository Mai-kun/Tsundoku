<script lang="ts">
    import CalendarDays from "lucide-svelte/icons/calendar-days";
    import Sparkles from "lucide-svelte/icons/sparkles";
    import { i18n } from "$lib/i18n/index.svelte";
</script>

<div class="mx-auto max-w-3xl space-y-6">
    <div>
        <p
            class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
        >
            {i18n.t.library.collectionLabel}
        </p>
        <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">
            {i18n.t.views.calendarTitle}
        </h2>
        <p class="mt-2 text-sm text-muted">{i18n.t.views.calendarHint}</p>
    </div>

    <div
        class="flex min-h-[50vh] flex-col items-center justify-center rounded-xl border border-dashed border-white/10 bg-field/50 p-8 text-center sm:p-12"
    >
        <div
            class="relative grid h-16 w-16 place-items-center rounded-2xl border border-border/60 bg-card shadow-sm"
        >
            <CalendarDays
                size={28}
                class="text-accent-soft"
                aria-hidden="true"
            />
            <span
                class="absolute -right-1 -top-1 grid h-5 w-5 place-items-center rounded-full bg-accent text-[10px] text-white"
            >
                <Sparkles size={11} aria-hidden="true" />
            </span>
        </div>

        <span
            class="mt-6 rounded-full bg-accent/10 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-accent-soft"
        >
            {i18n.t.common.comingSoon}
        </span>

        <h3 class="mt-3 text-lg font-bold text-ink">
            {i18n.t.views.calendarPlaceholderTitle}
        </h3>
        <p class="mt-2 max-w-md text-sm leading-relaxed text-muted">
            {i18n.t.views.calendarPlaceholderHint}
        </p>
    </div>
</div>
