<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLAttributes } from "svelte/elements";

  type Tone = "neutral" | "accent" | "info" | "success" | "warning" | "danger";
  type Size = "xs" | "sm";

  interface Props extends HTMLAttributes<HTMLElement> {
    tone?: Tone;
    size?: Size;
    class?: string;
    children: Snippet;
  }

  let {
    tone = "neutral",
    size = "sm",
    class: className = "",
    children,
    ...rest
  }: Props = $props();

  // Unified chip geometry + token-only colors. Brand/source palettes
  // (--color-badge-*, --color-import-*) stay applied from outside via style/class.
  const toneClasses: Record<Tone, string> = {
    neutral: "border-subtle bg-hover text-secondary",
    accent: "border-accent-bright/30 bg-accent-bright/15 text-accent-soft",
    info: "border-info-line/30 bg-info-line/10 text-info-soft",
    success: "border-success-line/30 bg-success-line/10 text-success-soft",
    warning: "border-warning-line/30 bg-warning-line/10 text-warning-text",
    danger: "border-danger/30 bg-danger-soft text-danger-text",
  };

  const sizeClasses: Record<Size, string> = {
    xs: "gap-1 rounded-md px-1.5 py-0.5 text-[10px]",
    sm: "gap-1 rounded-md px-2 py-0.5 text-xs",
  };

  const baseClasses = "inline-flex items-center whitespace-nowrap border font-medium";
</script>

<span class="{baseClasses} {toneClasses[tone]} {sizeClasses[size]} {className}" {...rest}>
  {@render children()}
</span>
