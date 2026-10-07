<script lang="ts">
    import type { Snippet } from "svelte";

    interface MenuItem {
        id: string;
        label: string;
        icon?: Snippet;
    }

    interface Props {
        items: readonly MenuItem[];
        active: string;
        onNavigate: (id: string) => void;
        compact?: boolean;
    }

    let { items, active, onNavigate, compact = false }: Props = $props();

    function itemClass(item: MenuItem): string {
        const isActive = active === item.id;
        return `
            group relative flex items-center gap-2 rounded-md px-3 py-2.5 text-sm font-medium transition
            ${isActive
                ? "bg-panel-raised text-ink"
                : "text-muted hover:text-ink hover:bg-card/60"
            }
        `.trim();
    }
</script>

<div
    class="flex flex-col rounded-lg bg-canvas/80 p-2 shadow-2xl shadow-black/40"
    role="tablist"
    aria-label="Navigation menu"
>
    {#each items as item (item.id)}
        <button
            type="button"
            class="value group relative flex items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition"
            class:active={active === item.id}
            onclick={() => onNavigate(item.id)}
            role="tab"
            aria-selected={active === item.id}
            aria-label={item.label}
        >
            {@render item.icon?.()}

            <span class="flex-1 text-left transition-colors">
                <span class="{active === item.id
                    ? "text-ink"
                    : "text-muted hover:text-ink"
                }">
                    {item.label}
                </span>
            </span>

            {#if active === item.id}
                <span
                    class="absolute left-0 top-1/2 h-2/3 w-1 -translate-y-1/2 rounded-md bg-accent"
                    aria-hidden="true"
                ></span>
            {/if}
        </button>
    {/each}
</div>
