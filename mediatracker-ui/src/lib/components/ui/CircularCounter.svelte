<script lang="ts">
    import Minus from "lucide-svelte/icons/minus";
    import Plus from "lucide-svelte/icons/plus";
    import { untrack } from "svelte";

    interface Props {
        value: number;
        min?: number;
        max?: number;
        step?: number;
        label?: string;
        disabled?: boolean;
        onChange: (value: number) => void;
    }

    let {
        value,
        min = 0,
        max = 99999,
        step = 1,
        label = "Часы",
        disabled = false,
        onChange,
    }: Props = $props();

    let dialRef: HTMLDivElement | null = $state(null);
    let isDragging = $state(false);
    let lastAngle: number | null = null;
    let accumulatedAngleDelta = 0;
    let rotationDeg = $state(0);
    let inputValue = $state(untrack(() => value));

    $effect(() => {
        inputValue = value;
    });

    function calculateAngle(clientX: number, clientY: number): number {
        if (!dialRef) return 0;
        const rect = dialRef.getBoundingClientRect();
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        const radians = Math.atan2(clientY - centerY, clientX - centerX);
        let degrees = radians * (180 / Math.PI);
        if (degrees < 0) degrees += 360;
        return degrees;
    }

    function handlePointerDown(e: PointerEvent) {
        if (disabled || (e.target as HTMLElement).tagName === "INPUT") return;
        isDragging = true;
        lastAngle = calculateAngle(e.clientX, e.clientY);
        accumulatedAngleDelta = 0;
        (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    }

    function handlePointerMove(e: PointerEvent) {
        if (!isDragging || lastAngle === null) return;
        const currentAngle = calculateAngle(e.clientX, e.clientY);
        let delta = currentAngle - lastAngle;

        if (delta > 180) delta -= 360;
        else if (delta < -180) delta += 360;

        lastAngle = currentAngle;
        accumulatedAngleDelta += delta;
        rotationDeg += delta;

        const angleThreshold = 18;
        if (Math.abs(accumulatedAngleDelta) >= angleThreshold) {
            const steps = Math.trunc(accumulatedAngleDelta / angleThreshold);
            accumulatedAngleDelta -= steps * angleThreshold;
            const next = Math.min(Math.max(value + steps * step, min), max);
            if (next !== value) {
                onChange(next);
            }
        }
    }

    function handlePointerUp(e: PointerEvent) {
        if (isDragging) {
            isDragging = false;
            lastAngle = null;
            accumulatedAngleDelta = 0;
            try {
                (e.currentTarget as HTMLElement).releasePointerCapture(
                    e.pointerId,
                );
            } catch {}
        }
    }

    function handleWheel(e: WheelEvent) {
        if (disabled) return;
        e.preventDefault();
        const dir = e.deltaY < 0 ? 1 : -1;
        rotationDeg += dir * 15;
        const next = Math.min(Math.max(value + dir * step, min), max);
        if (next !== value) {
            onChange(next);
        }
    }

    function handleInputCommit(e: Event) {
        const target = e.target as HTMLInputElement;
        const parsed = parseInt(target.value, 10);
        if (Number.isNaN(parsed)) {
            inputValue = value;
            return;
        }
        const clamped = Math.min(Math.max(parsed, min), max);
        inputValue = clamped;
        if (clamped !== value) {
            onChange(clamped);
        }
    }

    function handleKeyDown(e: KeyboardEvent) {
        if (disabled) return;
        if (e.key === "ArrowRight" || e.key === "ArrowUp") {
            e.preventDefault();
            const next = Math.min(value + step, max);
            onChange(next);
            rotationDeg += 15;
        } else if (e.key === "ArrowLeft" || e.key === "ArrowDown") {
            e.preventDefault();
            const next = Math.max(value - step, min);
            onChange(next);
            rotationDeg -= 15;
        }
    }

    function stepDelta(delta: number) {
        if (disabled) return;
        const next = Math.min(Math.max(value + delta * step, min), max);
        if (next !== value) {
            onChange(next);
            rotationDeg += delta * 15;
        }
    }
</script>

<div class="flex flex-col items-center gap-3">
    {#if label}
        <div class="text-xs font-bold uppercase tracking-wider text-slate-300">
            {label}
        </div>
    {/if}

    <div class="relative flex items-center justify-center gap-4">
        <button
            type="button"
            class="grid h-8 w-8 place-items-center rounded-lg border border-white/[0.08] bg-[var(--color-field)] text-muted transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:opacity-40 cursor-pointer"
            disabled={disabled || value <= min}
            onclick={() => stepDelta(-1)}
            aria-label="Decrease"
        >
            <Minus size={14} />
        </button>

        <!-- Rotary Knob / Dial -->
        <div
            bind:this={dialRef}
            role="slider"
            tabindex="0"
            aria-valuenow={value}
            aria-valuemin={min}
            aria-valuemax={max}
            aria-label={label}
            class={`relative h-28 w-28 select-none rounded-full border-2 border-white/[0.08] bg-gradient-to-b from-[var(--color-overlay-strong)] to-[var(--color-field)] shadow-xl touch-none flex items-center justify-center cursor-grab active:cursor-grabbing transition-colors ${
                isDragging
                    ? "ring-2 ring-[color-mix(in_oklab,var(--color-accent)_60%,transparent)] border-[var(--color-accent)]"
                    : "hover:border-white/[0.14]"
            }`}
            onpointerdown={handlePointerDown}
            onpointermove={handlePointerMove}
            onpointerup={handlePointerUp}
            onpointercancel={handlePointerUp}
            onwheel={handleWheel}
            onkeydown={handleKeyDown}
        >
            <!-- Outer Tick Ring (SVG) -->
            <svg
                class="absolute inset-0 h-full w-full pointer-events-none"
                viewBox="0 0 112 112"
            >
                <circle
                    cx="56"
                    cy="56"
                    r="50"
                    fill="none"
                    stroke="rgba(255, 255, 255, 0.05)"
                    stroke-width="3"
                />
                <!-- 12 radial ticks around ring -->
                {#each Array(16) as _, i}
                    {@const tickAngle = (i * 360) / 16}
                    <line
                        x1="56"
                        y1="8"
                        x2="56"
                        y2="13"
                        stroke="rgba(255, 255, 255, 0.18)"
                        stroke-width="1.5"
                        stroke-linecap="round"
                        transform={`rotate(${tickAngle} 56 56)`}
                    />
                {/each}
            </svg>

            <!-- Rotating Dial Surface with Indicator Notch -->
            <div
                class="absolute inset-3 rounded-full bg-[var(--color-track-soft)] shadow-inner flex items-center justify-center pointer-events-none transition-transform duration-75 ease-out"
                style={`transform: rotate(${rotationDeg}deg);`}
            >
                <!-- Indicator notch at top of knob -->
                <div
                    class="absolute top-1.5 h-2.5 w-1 rounded-full bg-[var(--color-accent)] shadow-[0_0_8px_#5844e0]"
                ></div>
            </div>

            <!-- Center Direct Input Container -->
            <div
                class="relative z-10 flex items-center justify-center pointer-events-auto"
            >
                <!-- Chromium reserves a gutter for the number spinners, which pushes the
                     digits off-centre even with text-align:center; appearance:none removes it. -->
                <input
                    type="number"
                    {min}
                    {max}
                    {step}
                    {disabled}
                    value={inputValue}
                    onchange={handleInputCommit}
                    onblur={handleInputCommit}
                    class="w-16 appearance-none bg-transparent text-center text-lg font-bold tabular-nums text-white focus:outline-none focus:ring-1 focus:ring-[var(--color-accent)] rounded py-0.5 [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                    title="Нажмите, чтобы ввести число вручную"
                />
            </div>
        </div>

        <button
            type="button"
            class="grid h-8 w-8 place-items-center rounded-lg border border-white/[0.08] bg-[var(--color-field)] text-muted transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:opacity-40 cursor-pointer"
            disabled={disabled || value >= max}
            onclick={() => stepDelta(1)}
            aria-label="Increase"
        >
            <Plus size={14} />
        </button>
    </div>

    <div class="text-[11px] text-muted">
        Крутите диск или введите число вручную
    </div>
</div>
