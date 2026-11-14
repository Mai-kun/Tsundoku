<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLButtonAttributes } from "svelte/elements";
  import { LoaderCircle } from "$shared/ui/Icons";

  type Variant = "primary" | "secondary" | "ghost" | "outline" | "danger";
  type Size = "xs" | "sm" | "md" | "lg" | "icon";

  interface Props extends HTMLButtonAttributes {
    variant?: Variant;
    size?: Size;
    loading?: boolean;
    /** Collapse to a square (w = h of the chosen size) for icon-only buttons. */
    iconOnly?: boolean;
    /** 0..1 hold-to-confirm fill (see holdToDelete.svelte.ts); null hides the overlay. */
    holdProgress?: number | null;
    disabled?: boolean;
    /** Explicit element binding: `bind:this` does not flow through `{...rest}`. */
    ref?: HTMLButtonElement | null;
    class?: string;
    children: Snippet;
  }

  // `type` is destructured before `...rest` and defaults to "button" so buttons
  // inside forms (Settings / Lists / Import) never act as implicit submit.
  let {
    variant = "secondary",
    size = "md",
    loading = false,
    iconOnly = false,
    holdProgress = null,
    disabled = false,
    type = "button",
    ref = $bindable(null),
    class: className = "",
    children,
    ...rest
  }: Props = $props();

  // All colors come strictly from tokens.css primitives (mapped in app.css @theme).
  const variantClasses: Record<Variant, string> = {
    primary: "bg-accent text-white hover:bg-accent-hover",
    secondary: "border border-subtle bg-elevated text-ink hover:bg-hover",
    ghost: "text-muted hover:bg-hover hover:text-ink",
    outline: "border border-strong text-ink hover:bg-hover",
    danger: "bg-danger text-white hover:bg-danger-hover",
  };

  const sizeClasses: Record<Size, string> = {
    xs: "h-6 gap-1 rounded-md px-2 text-[11px]",
    sm: "h-8 gap-1.5 rounded-md px-3 text-xs",
    md: "h-9 gap-2 rounded-lg px-3.5 text-sm",
    lg: "h-10 gap-2 rounded-lg px-4 text-sm",
    icon: "size-9 rounded-lg p-0",
  };

  const iconSizeClasses: Record<Exclude<Size, "icon">, string> = {
    xs: "size-6 rounded-md p-0",
    sm: "size-8 rounded-md p-0",
    md: "size-9 rounded-lg p-0",
    lg: "size-10 rounded-lg p-0",
  };

  // Bare `transition` (not transition-colors) so active:scale actually animates;
  // the animation audit requires an animating class next to hover: variants.
  // relative + z-0 (stacking context) + overflow-hidden clip the hold-to-confirm
  // fill to the radius while keeping it under the label (fill is -z-10).
  const baseClasses =
    "relative z-0 inline-flex shrink-0 cursor-pointer select-none items-center justify-center overflow-hidden whitespace-nowrap font-medium transition duration-150 active:scale-[0.98] disabled:pointer-events-none disabled:opacity-50";
</script>

<button
  bind:this={ref}
  {type}
  class="{baseClasses} {variantClasses[variant]} {iconOnly && size !== 'icon' ? iconSizeClasses[size] : sizeClasses[size]} {className}"
  disabled={disabled || loading}
  aria-busy={loading || undefined}
  {...rest}
>
  <!-- Hold-to-confirm fill: transform-only so it stays on the compositor at any Hz. -->
  {#if holdProgress !== null}
    <span
      aria-hidden="true"
      class="bg-danger/30 pointer-events-none absolute inset-0 origin-left -z-10"
      style:transform="scaleX({holdProgress})"
    ></span>
  {/if}
  {#if loading}
    <LoaderCircle class="size-4 animate-spin" />
  {/if}
  {@render children()}
</button>
