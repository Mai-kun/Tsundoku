<script lang="ts">
  import Modal from "$shared/ui/Modal.svelte";
  import Button from "$shared/ui/Button.svelte";
  import { AlertTriangle, Check, Trash2 } from "$shared/ui/Icons";
  import {
    confirmDialog,
    type ConfirmRemember,
    type ConfirmRequest,
  } from "$shared/ui/confirmDialog.svelte";
  import { i18n } from "$shared/i18n/index.svelte";

  // The question must stay visible while the exit animation plays out, so the last
  // request is kept as a snapshot after the store has already settled.
  let rendered = $state<ConfirmRequest | null>(null);

  // The two memory checkboxes are mutually exclusive: ticking one unticks the other,
  // and re-ticking the active one clears both.
  let remember = $state<ConfirmRemember>("none");
  // Focus lands on the dialog body, not the Cancel button: a programmatic focus on a
  // button paints the accent ring at open time for mouse users, while Tab still gives
  // Cancel a proper :focus-visible outline.
  let dialogBody = $state<HTMLDivElement | null>(null);

  $effect(() => {
    if (confirmDialog.current) {
      rendered = confirmDialog.current;
      remember = "none";
      // Wait for the dialog to actually mount, then move focus off the page.
      requestAnimationFrame(() => dialogBody?.focus());
    }
  });

  function toggleRemember(which: Exclude<ConfirmRemember, "none">) {
    remember = remember === which ? "none" : which;
  }

  function choose(confirmed: boolean) {
    confirmDialog.settle(confirmed, remember);
  }
</script>

<svelte:window
  onkeydown={(e) => {
    if (!confirmDialog.current) return;
    if (e.key === "Enter") {
      e.preventDefault();
      choose(true);
    }
  }}
/>

<Modal isOpen={confirmDialog.current !== null} onClose={() => confirmDialog.cancel()} size="md">
  {#if rendered}
    <div
      bind:this={dialogBody}
      class="p-6 outline-none"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="confirm-dialog-title"
      aria-describedby="confirm-dialog-description"
      tabindex="-1"
    >
      <div class="flex items-start gap-3.5">
        <div
          class={`grid size-10 shrink-0 place-items-center rounded-xl border ${
            rendered.danger
              ? "border-danger/30 bg-danger-soft text-danger-text"
              : "border-warning-line/30 bg-warning-surface text-warning-text"
          }`}
          aria-hidden="true"
        >
          {#if rendered.danger}
            <Trash2 size={19} />
          {:else}
            <AlertTriangle size={19} />
          {/if}
        </div>
        <div class="min-w-0 pt-0.5">
          <h2 id="confirm-dialog-title" class="text-ink text-base font-bold tracking-tight">
            {rendered.title}
          </h2>
          <p id="confirm-dialog-description" class="text-muted mt-1.5 text-sm leading-relaxed">
            {rendered.description ?? (rendered.danger ? i18n.t.confirmDialog.irreversible : "")}
          </p>
        </div>
      </div>

      <!-- Memory choices: strictly one at a time, none pre-ticked. -->
      <div class="bg-hover/60 mt-4 space-y-1 rounded-lg p-1.5">
        <label
          class="text-secondary hover:bg-active flex cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-xs transition-colors duration-150 hover:text-white"
        >
          <input
            type="checkbox"
            class="peer sr-only"
            checked={remember === "forever"}
            onchange={() => toggleRemember("forever")}
          />
          <span
            aria-hidden="true"
            class="peer-checked:border-accent peer-checked:bg-accent grid size-4 shrink-0 place-items-center rounded border transition-colors duration-150 peer-checked:text-white"
          >
            <Check size={11} class={remember === "forever" ? "opacity-100" : "opacity-0"} />
          </span>
          <span>{i18n.t.confirmDialog.rememberForever}</span>
        </label>
        <label
          class="text-secondary hover:bg-active flex cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 text-xs transition-colors duration-150 hover:text-white"
        >
          <input
            type="checkbox"
            class="peer sr-only"
            checked={remember === "hour"}
            onchange={() => toggleRemember("hour")}
          />
          <span
            aria-hidden="true"
            class="peer-checked:border-accent peer-checked:bg-accent grid size-4 shrink-0 place-items-center rounded border transition-colors duration-150 peer-checked:text-white"
          >
            <Check size={11} class={remember === "hour" ? "opacity-100" : "opacity-0"} />
          </span>
          <span>{i18n.t.confirmDialog.rememberHour}</span>
        </label>
      </div>

      <div class="border-subtle mt-5 flex items-center justify-end gap-2 border-t pt-4">
        <Button
          variant="secondary"
          size="lg"
          data-testid="confirm-dialog-cancel"
          onclick={() => choose(false)}
        >
          {rendered.cancelLabel ?? i18n.t.confirmDialog.cancel}
        </Button>
        <Button
          variant={rendered.danger ? "danger" : "primary"}
          size="lg"
          class="font-semibold disabled:cursor-wait disabled:opacity-70"
          data-testid="confirm-dialog-confirm"
          onclick={() => choose(true)}
        >
          {rendered.confirmLabel ?? i18n.t.confirmDialog.confirm}
        </Button>
      </div>
    </div>
  {/if}
</Modal>
