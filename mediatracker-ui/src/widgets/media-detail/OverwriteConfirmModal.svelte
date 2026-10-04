<script lang="ts">
    import Modal from "$shared/ui/Modal.svelte";
    import { i18n } from "$shared/i18n/index.svelte";

    interface Props {
        isOpen: boolean;
        busy: boolean;
        /** Runs the gap fill; the user keeps everything they typed. */
        onFillMissing: () => void;
        /** Runs the full overwrite; the row stops carrying the user's edits afterwards. */
        onOverwrite: () => void;
        onClose: () => void;
    }

    let { isOpen, busy, onFillMissing, onOverwrite, onClose }: Props = $props();
</script>

<Modal {isOpen} onClose={onClose} labelledBy="overwrite-title">
    <div class="p-5">
        <h2
            id="overwrite-title"
            class="text-base font-semibold text-white"
        >
            {i18n.t.detail.overwriteTitle}
        </h2>
        <p class="mt-1.5 text-sm text-muted">
            {i18n.t.detail.overwriteHint}
        </p>
    </div>
    <div class="flex flex-col gap-2 border-t border-white/[0.08] p-5">
        <button
            type="button"
            class="tap w-full rounded-lg bg-[var(--color-accent)] px-4 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--color-accent-hover)] disabled:cursor-wait disabled:opacity-60"
            disabled={busy}
            onclick={onFillMissing}
        >
            {i18n.t.detail.overwriteSafe}
        </button>
        <button
            type="button"
            class="tap w-full rounded-lg border border-white/10 px-4 py-2.5 text-sm font-medium text-muted transition hover:border-rose-400/40 hover:text-rose-200 disabled:cursor-wait disabled:opacity-60"
            disabled={busy}
            onclick={onOverwrite}
        >
            {i18n.t.detail.overwriteFull}
        </button>
        <button
            type="button"
            class="mt-1 w-full rounded-lg px-4 py-2 text-sm text-muted transition hover:text-white disabled:opacity-60"
            disabled={busy}
            onclick={onClose}
        >
            {i18n.t.common.cancel}
        </button>
    </div>
</Modal>