<script lang="ts">
    import { Bookmark, Flame, Heart, List, Sparkles, Star } from "$shared/ui/Icons.svelte";
    import { createList, errorMessage, updateList } from "$shared/api/api";
    import type { CustomListSummary, CreateListPayload } from "$shared/types";
    import { i18n } from "$shared/i18n/index.svelte";
    import Modal from "$shared/ui/Modal.svelte";

    interface Props {
        isOpen: boolean;
        list?: CustomListSummary | null;
        onClose: () => void;
        onSaved: () => void;
    }
    let { isOpen, list = null, onClose, onSaved }: Props = $props();
    let name = $state("");
    let description = $state("");
    let color = $state("#5844e0");
    let icon = $state("list");
    let busy = $state(false);
    let error = $state("");
    let nameInput = $state<HTMLInputElement | null>(null);
    let lastOpen = false;
    const colors = ["#5844e0", "#3b82f6", "#10b981", "#f59e0b", "#ec4899", "#06b6d4"];
    const icons = [
        { key: "list", component: List }, { key: "bookmark", component: Bookmark },
        { key: "heart", component: Heart }, { key: "star", component: Star },
        { key: "sparkles", component: Sparkles }, { key: "flame", component: Flame },
    ];

    $effect(() => {
        if (isOpen) nameInput?.focus();
        if (isOpen && !lastOpen) {
            name = list?.name ?? "";
            description = list?.description ?? "";
            color = list?.color ?? colors[0];
            icon = list?.icon ?? "list";
            error = "";
        }
        lastOpen = isOpen;
    });

    async function save(event: SubmitEvent) {
        event.preventDefault();
        if (!name.trim() || busy) return;
        busy = true;
        error = "";
        const payload: CreateListPayload = { name: name.trim(), description: description.trim() || null, icon, color };
        try {
            if (list) await updateList(list.id, payload);
            else await createList(payload);
            onSaved();
            onClose();
        } catch (caught) {
            error = errorMessage(caught);
        } finally {
            busy = false;
        }
    }
</script>

<Modal {isOpen} {onClose} labelledBy="custom-list-modal-title">
    <form class="space-y-5 p-5 sm:p-6" onsubmit={save}>
        <div>
            <h2 id="custom-list-modal-title" class="text-lg font-bold text-ink">
                {list ? i18n.t.views.listEdit : i18n.t.views.listCreate}
            </h2>
            <p class="mt-1 text-sm text-muted">{i18n.t.views.listModalHint}</p>
        </div>
        <label class="block space-y-1.5 text-sm font-medium text-ink">
            {i18n.t.views.listName}
            <input bind:this={nameInput} bind:value={name} maxlength="100" required class="w-full rounded-lg border border-white/10 bg-canvas px-3 py-2.5 text-sm outline-none focus:border-accent" />
        </label>
        <label class="block space-y-1.5 text-sm font-medium text-ink">
            {i18n.t.views.listDescription}
            <textarea bind:value={description} maxlength="500" rows="3" class="w-full resize-y rounded-lg border border-white/10 bg-canvas px-3 py-2.5 text-sm outline-none focus:border-accent"></textarea>
        </label>
        <fieldset class="space-y-2">
            <legend class="text-sm font-medium text-ink">{i18n.t.views.listColor}</legend>
            <div class="flex flex-wrap gap-3">
                {#each colors as value (value)}
                    <button type="button" aria-label={value} aria-pressed={color === value} class="h-8 w-8 rounded-full ring-offset-2 ring-offset-[#151a26] transition" style={`background:${value}`} class:ring-2={color === value} class:ring-white={color === value} onclick={() => (color = value)}></button>
                {/each}
            </div>
        </fieldset>
        <fieldset class="space-y-2">
            <legend class="text-sm font-medium text-ink">{i18n.t.views.listIcon}</legend>
            <div class="flex flex-wrap gap-2">
                {#each icons as choice (choice.key)}
                    {@const Icon = choice.component}
                    <button type="button" aria-label={choice.key} aria-pressed={icon === choice.key} class={`grid h-10 w-10 place-items-center rounded-lg border transition ${icon === choice.key ? "border-accent bg-accent/15" : "border-white/10 text-muted"}`} onclick={() => (icon = choice.key)}><Icon size={18} /></button>
                {/each}
            </div>
        </fieldset>
        {#if error}<p class="text-sm text-rose-300" role="alert">{error}</p>{/if}
        <div class="flex justify-end gap-2 border-t border-white/[0.07] pt-4">
            <button type="button" class="rounded-lg px-4 py-2 text-sm text-muted hover:bg-white/5" onclick={onClose}>{i18n.t.common.cancel}</button>
            <button type="submit" disabled={!name.trim() || busy} class="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white hover:bg-accent-hover disabled:opacity-50">{busy ? i18n.t.common.saving : i18n.t.common.save}</button>
        </div>
    </form>
</Modal>
