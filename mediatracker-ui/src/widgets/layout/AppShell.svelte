<script lang="ts">
    import type { Snippet } from "svelte";
    import ToastContainer from "./ToastContainer.svelte";

    interface Props {
        sidebar: Snippet;
        header: Snippet;
        children: Snippet;
        mainRef?: (el: HTMLElement | null) => void;
    }

    let { sidebar, header, children, mainRef }: Props = $props();

    let mainElement = $state<HTMLElement | null>(null);

    $effect(() => {
        if (mainRef) mainRef(mainElement);
    });
</script>

<div class="flex h-dvh w-full overflow-hidden bg-canvas text-ink lg:pl-60">
    <aside
        class="z-20 fixed inset-x-0 bottom-0 border-t border-white/[0.07] bg-surface px-2 py-2 lg:inset-y-0 lg:left-0 lg:right-auto lg:w-60 lg:border-r lg:border-t-0 lg:px-3 lg:py-5"
    >
        {@render sidebar()}
    </aside>

    <div class="flex min-w-0 flex-1 flex-col lg:pl-0">
        <header
            class="z-20 flex h-14 shrink-0 items-center border-b border-white/[0.07] bg-surface"
        >
            {@render header()}
        </header>

        <main
            id="main-scroll"
            bind:this={mainElement}
            class="min-h-0 flex-1 overflow-y-auto overflow-x-hidden px-4 pb-24 pt-6 sm:px-6 lg:px-8 lg:pb-8"
        >
            {@render children()}
        </main>
    </div>

    <ToastContainer />
</div>
