<script lang="ts">
  import {
    BarChart3,
    BookOpen,
    CalendarDays,
    Clapperboard,
    Film,
    Gamepad2,
    History,
    Home,
    Library,
    List,
    Menu,
    Plus,
    Settings,
    Trophy,
    Tv,
  } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { AppView } from "$shared/types";
  import { crossfade } from "svelte/transition";

  interface Props {
    activeView: AppView;
    onNavigate: (view: AppView) => void;
    onCreate: () => void;
  }

  let { activeView, onNavigate, onCreate }: Props = $props();

  let toolsOpen = $state(false);

  /** CSS-equivalent cubic-bezier(0.2, 0, 0, 1) for the crossfade transition. */
  function cubicBezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
    const cx = 3 * x1;
    const bx = 3 * (x2 - x1) - cx;
    const ax = 1 - cx - bx;
    const cy = 3 * y1;
    const by = 3 * (y2 - y1) - cy;
    const ay = 1 - cy - by;
    const sampleX = (t: number) => ((ax * t + bx) * t + cx) * t;
    const sampleY = (t: number) => ((ay * t + by) * t + cy) * t;
    return (x) => {
      let t = x;
      for (let i = 0; i < 8; i++) {
        const delta = sampleX(t) - x;
        if (Math.abs(delta) < 1e-5) break;
        const derivative = (3 * ax * t + 2 * bx) * t + cx;
        if (Math.abs(derivative) < 1e-6) break;
        t -= delta / derivative;
      }
      return sampleY(t);
    };
  }

  /* One shared key makes the highlight physically slide between nav items;
     the tools block gets its own key so categories and tools never crossfade
     into each other. */
  const [sendActive, receiveActive] = crossfade({
    duration: 220,
    easing: cubicBezier(0.2, 0, 0, 1),
  });
  const [sendTools, receiveTools] = crossfade({
    duration: 220,
    easing: cubicBezier(0.2, 0, 0, 1),
  });

  function navigate(view: AppView) {
    toolsOpen = false;
    onNavigate(view);
  }

  function itemClass(view: AppView): string {
    return activeView === view
      ? "font-medium text-[#a5b4fc] [&>svg]:text-[#a5b4fc]"
      : "text-muted hover:bg-card/60 hover:text-ink [&>svg]:text-muted hover:[&>svg]:text-ink";
  }
</script>

{#snippet mainNavItem(view: AppView, label: string, Icon: typeof Home)}
  <button
    type="button"
    class={`relative inline-flex h-10 w-10 items-center justify-center rounded-md transition lg:w-full lg:justify-start lg:gap-3 lg:px-3 ${itemClass(
      view,
    )}`}
    aria-label={label}
    title={label}
    onclick={() => navigate(view)}
  >
    {#if activeView === view}
      <span
        class="bg-accent-bright/15 absolute inset-0 rounded-md"
        in:receiveActive={{ key: "active-indicator" }}
        out:sendActive={{ key: "active-indicator" }}
      ></span>
    {/if}
    <Icon size={18} class="relative z-10" aria-hidden="true" />
    <span class="relative z-10 hidden text-sm font-medium lg:inline">{label}</span>
  </button>
{/snippet}

{#snippet toolsNavItem(
  view: AppView,
  label: string,
  Icon: typeof Home,
  iconSize: number,
  py: string,
)}
  <button
    type="button"
    class={`relative inline-flex w-full items-center gap-3 rounded-md px-3 ${py} text-sm font-medium transition ${itemClass(view)}`}
    onclick={() => navigate(view)}
    aria-label={label}
    title={label}
  >
    {#if activeView === view}
      <span
        class="bg-accent-bright/15 absolute inset-0 rounded-md"
        in:receiveTools={{ key: "tools-indicator" }}
        out:sendTools={{ key: "tools-indicator" }}
      ></span>
    {/if}
    <Icon size={iconSize} class="relative z-10" aria-hidden="true" />
    <span class="relative z-10 truncate">{label}</span>
  </button>
{/snippet}

<div
  class="flex h-full items-center justify-around gap-1 lg:flex-col lg:items-stretch lg:justify-between"
>
  <div
    class="flex flex-1 items-center justify-around gap-1 lg:flex-none lg:flex-col lg:items-stretch lg:justify-start"
  >
    <div class="hidden px-3 pb-7 lg:block">
      <p class="text-ink text-sm font-bold tracking-tight">Tsundoku</p>
      <p class="text-muted mt-1 text-[10px] font-semibold tracking-[0.18em] uppercase">
        {i18n.t.navigation.brand}
      </p>
    </div>

    <nav
      class="flex flex-1 items-center justify-around gap-1 lg:flex-none lg:flex-col lg:items-stretch lg:justify-start"
      aria-label={i18n.t.navigation.mainLabel}
    >
      {@render mainNavItem("home", i18n.t.navigation.home, Home)}
      {@render mainNavItem("tvshow", i18n.t.navigation.tvshow, Tv)}
      {@render mainNavItem("movie", i18n.t.navigation.movie, Film)}
      {@render mainNavItem("anime", i18n.t.navigation.anime, Clapperboard)}
      {@render mainNavItem("manga", i18n.t.navigation.manga, Library)}
      {@render mainNavItem("game", i18n.t.navigation.game, Gamepad2)}
      {@render mainNavItem("book", i18n.t.navigation.book, BookOpen)}
    </nav>
  </div>

  <div class="lg:hidden">
    <button
      type="button"
      class="text-muted hover:bg-card hover:text-ink inline-flex h-10 w-10 items-center justify-center rounded-md transition"
      aria-label={i18n.t.navigation.toolsLabel}
      aria-expanded={toolsOpen}
      onclick={() => (toolsOpen = !toolsOpen)}
    >
      <Menu size={18} aria-hidden="true" />
    </button>
  </div>

  {#if toolsOpen}
    <div
      class="bg-elevated absolute inset-x-2 bottom-full mb-2 space-y-1 rounded-lg border border-white/[0.08] p-2 shadow-2xl shadow-black/60 lg:hidden"
    >
      <p class="text-muted px-3 py-1 text-[10px] font-semibold tracking-[0.16em] uppercase">
        {i18n.t.navigation.toolsLabel}
      </p>
      <button
        type="button"
        class="text-muted hover:bg-card hover:text-ink inline-flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition"
        onclick={() => {
          toolsOpen = false;
          onCreate();
        }}><Plus size={18} aria-hidden="true" />{i18n.t.navigation.create}</button
      >
      {@render toolsNavItem("stats", i18n.t.navigation.stats, BarChart3, 18, "py-2.5")}
      {@render toolsNavItem("lists", i18n.t.navigation.lists, List, 18, "py-2.5")}
      {@render toolsNavItem("history", i18n.t.navigation.history, History, 18, "py-2.5")}
      {@render toolsNavItem("calendar", i18n.t.navigation.calendar, CalendarDays, 18, "py-2.5")}
      {@render toolsNavItem("goals", i18n.t.navigation.goals, Trophy, 18, "py-2.5")}
      {@render toolsNavItem("settings", i18n.t.navigation.settings, Settings, 18, "py-2.5")}
    </div>
  {/if}

  <div class="border-border hidden border-t pt-4 lg:mt-auto lg:block">
    <p class="text-muted px-3 pb-2 text-[10px] font-semibold tracking-[0.16em] uppercase">
      {i18n.t.navigation.toolsLabel}
    </p>
    <div class="space-y-1">
      <button
        type="button"
        class="text-muted hover:bg-card hover:text-ink inline-flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition"
        onclick={onCreate}><Plus size={17} />{i18n.t.navigation.create}</button
      >
      {@render toolsNavItem("stats", i18n.t.navigation.stats, BarChart3, 17, "py-2")}
      {@render toolsNavItem("lists", i18n.t.navigation.lists, List, 17, "py-2")}
      {@render toolsNavItem("history", i18n.t.navigation.history, History, 17, "py-2")}
      {@render toolsNavItem("calendar", i18n.t.navigation.calendar, CalendarDays, 17, "py-2")}
      {@render toolsNavItem("goals", i18n.t.navigation.goals, Trophy, 17, "py-2")}
      {@render toolsNavItem("settings", i18n.t.navigation.settings, Settings, 17, "py-2")}
    </div>
  </div>
</div>
