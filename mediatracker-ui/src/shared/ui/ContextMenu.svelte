<script lang="ts">
  import { tick } from "svelte";
  import { contextMenuStore, closeContextMenu } from "./contextMenu.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import {
    Pencil,
    ListChecks,
    List,
    Copy,
    Trash2,
    Search,
    FileText,
    ExternalLink,
    Settings,
    Power,
    ChevronRight,
  } from "$shared/ui/Icons";

  let menuEl = $state<HTMLElement | null>(null);
  let renderedX = $state(0);
  let renderedY = $state(0);
  let isPositioned = $state(false);
  let expandedSubmenu = $state<string | null>(null);
  let openSubmenuToLeft = $state(false);

  function getIcon(name: string | undefined) {
    if (!name) return null;
    const map: Record<string, typeof Pencil> = {
      edit: Pencil,
      status: ListChecks,
      list: List,
      copy: Copy,
      delete: Trash2,
      search: Search,
      logs: FileText,
      browser: ExternalLink,
      settings: Settings,
      power: Power,
      exit: Power,
    };
    return map[name] as typeof Pencil | null;
  }

  async function updatePosition() {
    await tick();
    if (!menuEl) return;

    const width = menuEl.offsetWidth || 220;
    const height = menuEl.offsetHeight || 200;

    let x = $contextMenuStore.x;
    let y = $contextMenuStore.y;

    if (x + width > window.innerWidth) {
      x = x - width;
    }
    if (y + height > window.innerHeight) {
      y = y - height;
    }

    renderedX = Math.max(8, Math.min(x, Math.max(8, window.innerWidth - width - 8)));
    renderedY = Math.max(8, Math.min(y, Math.max(8, window.innerHeight - height - 8)));
    openSubmenuToLeft = renderedX + width + 190 > window.innerWidth;
    isPositioned = true;
  }

  function handleKeyDown(event: KeyboardEvent) {
    if (event.key === "Escape") {
      closeContextMenu();
    }
  }

  function handlePointerDown(event: PointerEvent) {
    if (menuEl && !menuEl.contains(event.target as Node)) {
      closeContextMenu();
    }
  }

  function handleScroll() {
    closeContextMenu();
  }

  $effect(() => {
    if ($contextMenuStore.isOpen) {
      expandedSubmenu = null;
      isPositioned = false;
      openSubmenuToLeft = false;
      renderedX = $contextMenuStore.x;
      renderedY = $contextMenuStore.y;
      void updatePosition();

      window.addEventListener("keydown", handleKeyDown);
      window.addEventListener("pointerdown", handlePointerDown, { capture: true });
      window.addEventListener("scroll", handleScroll, { capture: true, passive: true });

      return () => {
        window.removeEventListener("keydown", handleKeyDown);
        window.removeEventListener("pointerdown", handlePointerDown, { capture: true });
        window.removeEventListener("scroll", handleScroll, { capture: true });
      };
    } else {
      isPositioned = false;
    }
  });
</script>

{#if $contextMenuStore.isOpen}
  <div
    bind:this={menuEl}
    class="context-menu"
    role="menu"
    tabindex="-1"
    aria-label={i18n.t.contextMenu.title}
    style="left: {renderedX}px; top: {renderedY}px; visibility: {isPositioned ? 'visible' : 'hidden'};"
    oncontextmenu={(e) => e.preventDefault()}
  >
    {#each $contextMenuStore.items as item (item.id)}
      {#if item.kind === "separator"}
        <div class="context-menu-separator" role="separator" aria-hidden="true"></div>
      {:else}
        {@const Icon = item.icon ? getIcon(item.icon) : null}
        {@const isSubmenu = Boolean(item.children && item.children.length > 0)}
        {@const isExpanded = isSubmenu && expandedSubmenu === item.id}

        {#if isSubmenu}
          <div
            class="context-menu-submenu-wrapper"
            role="none"
            onmouseenter={() => {
              expandedSubmenu = item.id;
            }}
            onmouseleave={() => {
              expandedSubmenu = null;
            }}
          >
            <button
              type="button"
              role="menuitem"
              aria-haspopup="true"
              aria-expanded={isExpanded}
              class="context-menu-item"
              class:context-menu-item_active={isExpanded}
              class:context-menu-item_disabled={item.disabled}
              disabled={item.disabled}
              onclick={() => {
                expandedSubmenu = isExpanded ? null : item.id;
              }}
            >
              <div class="context-menu-item-content">
                {#if Icon}
                  <span class="context-menu-icon-wrap">
                    <Icon size={15} aria-hidden="true" />
                  </span>
                {/if}
                <span class="context-menu-label">{item.label}</span>
              </div>

              <span class="context-menu-chevron-wrap">
                <ChevronRight size={14} aria-hidden="true" />
              </span>
            </button>

            {#if isExpanded && item.children}
              <div
                class="context-menu-flyout"
                class:flyout-left={openSubmenuToLeft}
                role="menu"
                aria-label={item.label}
              >
                {#each item.children as sub (sub.id)}
                  <button
                    type="button"
                    role="menuitem"
                    class="context-menu-item context-menu-submenu-item"
                    onclick={() => {
                      sub.action?.();
                      expandedSubmenu = null;
                      closeContextMenu();
                    }}
                  >
                    <span class="context-menu-label">{sub.label}</span>
                  </button>
                {/each}
              </div>
            {/if}
          </div>
        {:else}
          <button
            type="button"
            role="menuitem"
            class="context-menu-item"
            class:context-menu-item_danger={item.kind === "danger"}
            class:context-menu-item_disabled={item.disabled}
            disabled={item.disabled}
            onclick={() => {
              item.action?.();
              closeContextMenu();
            }}
            onmouseenter={() => {
              expandedSubmenu = null;
            }}
          >
            <div class="context-menu-item-content">
              {#if Icon}
                <span
                  class="context-menu-icon-wrap"
                  class:context-menu-icon-wrap_danger={item.kind === "danger"}
                >
                  <Icon size={15} aria-hidden="true" />
                </span>
              {/if}
              <span class="context-menu-label">{item.label}</span>
            </div>
          </button>
        {/if}
      {/if}
    {/each}
  </div>
{/if}

<style>
  .context-menu {
    position: fixed;
    z-index: 99999;
    background: #181b24;
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 12px;
    padding: 6px;
    min-width: 220px;
    max-width: 320px;
    box-shadow: 0 20px 48px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.05);
    font-size: 13px;
    line-height: 1.4;
    color: #e8eaed;
    display: flex;
    flex-direction: column;
    gap: 2px;
    user-select: none;
    outline: none;
  }

  .context-menu-submenu-wrapper {
    position: relative;
    width: 100%;
  }

  .context-menu-flyout {
    position: absolute;
    top: -4px;
    left: 100%;
    margin-left: 4px;
    z-index: 100000;
    background: #181b24;
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 12px;
    padding: 6px;
    min-width: 170px;
    box-shadow: 0 20px 48px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.05);
    display: flex;
    flex-direction: column;
    gap: 2px;
    user-select: none;
    outline: none;
  }

  .context-menu-flyout::before {
    content: "";
    position: absolute;
    top: 0;
    bottom: 0;
    left: -8px;
    width: 8px;
  }

  .context-menu-flyout.flyout-left {
    left: auto;
    right: 100%;
    margin-left: 0;
    margin-right: 4px;
  }

  .context-menu-flyout.flyout-left::before {
    left: auto;
    right: -8px;
  }

  .context-menu-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 7px 10px;
    background: transparent;
    border: none;
    border-radius: 8px;
    color: #e8eaed;
    cursor: pointer;
    text-align: left;
    width: 100%;
    transition: background-color 100ms ease, color 100ms ease;
  }

  .context-menu-item:hover,
  .context-menu-item_active {
    background: rgba(255, 255, 255, 0.08);
  }

  .context-menu-item-content {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    flex: 1;
  }

  .context-menu-item_danger {
    color: #fb7185; /* text-rose-400 */
  }

  .context-menu-item_danger:hover {
    background: rgba(244, 63, 94, 0.1); /* hover:bg-rose-500/10 */
    color: #fda4af;
  }

  .context-menu-item_disabled {
    opacity: 0.4;
    cursor: not-allowed;
    pointer-events: none;
  }

  .context-menu-icon-wrap {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    color: #94a3b8;
  }

  .context-menu-item:hover .context-menu-icon-wrap,
  .context-menu-item_active .context-menu-icon-wrap {
    color: #f1f5f9;
  }

  .context-menu-icon-wrap_danger {
    color: #fb7185;
  }

  .context-menu-chevron-wrap {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    color: #64748b;
  }

  .context-menu-item:hover .context-menu-chevron-wrap,
  .context-menu-item_active .context-menu-chevron-wrap {
    color: #cbd5e1;
  }

  .context-menu-submenu-item {
    padding: 6px 10px;
    font-size: 12.5px;
  }

  .context-menu-separator {
    height: 1px;
    background: rgba(255, 255, 255, 0.08);
    margin: 4px 6px;
  }

  .context-menu-label {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
