<script lang="ts">
  import { Sparkles } from "$shared/ui/Icons.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { RadarAxis } from "$shared/types";
  import { genreLabel } from "./genreLabel";

  interface Props {
    axes: RadarAxis[];
  }

  let { axes }: Props = $props();

  const CENTER = 170;
  const R = 100;

  function axisPoint(index: number, radius: number): { x: number; y: number } {
    const angle = ((index * 60 - 90) * Math.PI) / 180;
    return {
      x: CENTER + radius * Math.cos(angle),
      y: CENTER + radius * Math.sin(angle),
    };
  }

  function polygonPath(radius: number): string {
    return Array.from({ length: 6 }, (_, index) => {
      const point = axisPoint(index, radius);
      return `${point.x.toFixed(1)},${point.y.toFixed(1)}`;
    }).join(" ");
  }

  const gridLevels = [R / 3, (R * 2) / 3, R];

  function dataPath(): string {
    return (
      axes
        .slice(0, 6)
        .map((axis, index) => {
          const radius = (Math.max(axis.volumeScore, 0) / 100) * R;
          const point = axisPoint(index, radius);
          return `${point.x.toFixed(1)},${point.y.toFixed(1)}`;
        })
        .join(" ") || ""
    );
  }

  function labelAnchor(index: number): "middle" | "start" | "end" {
    const cos = Math.cos(((index * 60 - 90) * Math.PI) / 180);
    return Math.abs(cos) < 0.35 ? "middle" : cos > 0 ? "start" : "end";
  }

  function hasScore(axis: RadarAxis): boolean {
    return axis.averageScore > 0;
  }
</script>

<div class="rounded-xl border border-white/5 bg-[#151a26] p-5">
  <div class="mb-3 flex items-center gap-2">
    <Sparkles class="size-4 text-indigo-400" aria-hidden="true" />
    <h3 class="text-base font-semibold tracking-tight text-white">
      {i18n.t.stats.taste.radarTitle}
    </h3>
  </div>
  <p class="mb-2 text-xs text-slate-400">{i18n.t.stats.taste.radarHint}</p>

  {#if axes.length === 0}
    <p class="text-muted flex min-h-64 items-center justify-center text-xs">
      {i18n.t.stats.taste.emptyData}
    </p>
  {:else}
    <svg
      viewBox="-45 0 430 340"
      class="mx-auto block h-auto w-full max-w-md"
      role="img"
      aria-label={i18n.t.stats.taste.radarTitle}
    >
      {#each gridLevels as level (level)}
        <polygon
          points={polygonPath(level)}
          fill="none"
          stroke="rgba(255,255,255,0.08)"
          stroke-width="1"
        />
      {/each}
      {#each axes.slice(0, 6) as axis, index (axis.genre)}
        {@const spoke = axisPoint(index, R)}
        {@const vertex = axisPoint(index, (Math.max(axis.volumeScore, 0) / 100) * R)}
        {@const scoreLabel = axisPoint(index, (Math.max(axis.volumeScore, 0) / 100) * R + 16)}
        {@const label = axisPoint(index, R + 30)}
        <line
          x1={CENTER}
          y1={CENTER}
          x2={spoke.x.toFixed(1)}
          y2={spoke.y.toFixed(1)}
          stroke="rgba(255,255,255,0.08)"
          stroke-width="1"
        />
        <circle cx={vertex.x.toFixed(1)} cy={vertex.y.toFixed(1)} r="4" fill="#818cf8" />
        {#if hasScore(axis)}
          <text
            x={scoreLabel.x.toFixed(1)}
            y={scoreLabel.y.toFixed(1)}
            text-anchor="middle"
            dominant-baseline="middle"
            fill="#c7d2fe"
            font-size="11"
            font-weight="600">★ {axis.averageScore}</text
          >
        {/if}
        <text
          x={label.x.toFixed(1)}
          y={label.y.toFixed(1)}
          text-anchor={labelAnchor(index)}
          dominant-baseline="middle"
          fill="#94a3b8"
          font-size="12">{genreLabel(axis.genre)}</text
        >
      {/each}
      <polygon
        points={dataPath()}
        fill="#5844e0"
        fill-opacity="0.25"
        stroke="#818cf8"
        stroke-width="2"
        stroke-linejoin="round"
      />
    </svg>
  {/if}
</div>
