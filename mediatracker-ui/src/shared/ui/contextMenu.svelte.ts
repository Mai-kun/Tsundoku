import { writable } from "svelte/store";

/** Context menu item. For separator `kind: "separator"` label and action are optional. */
export interface MenuItem {
  id: string;
  label?: string;
  icon?: string;
  kind?: "default" | "separator" | "danger";
  disabled?: boolean;
  action?: () => void;
  children?: MenuItem[];
  mediaId?: string;
}

export interface ContextMenuState {
  isOpen: boolean;
  x: number;
  y: number;
  items: MenuItem[];
}

function createContextMenuStore() {
  const { subscribe, set } = writable<ContextMenuState>({
    isOpen: false,
    x: 0,
    y: 0,
    items: [],
  });

  return {
    subscribe,

    open(x: number, y: number, items: MenuItem[]) {
      set({ isOpen: true, x, y, items });
    },

    close() {
      set({ isOpen: false, x: 0, y: 0, items: [] });
    },
  };
}

export const contextMenuStore = createContextMenuStore();

/** Open context menu at (x, y) coordinates. */
export function openContextMenu(x: number, y: number, items: MenuItem[]) {
  contextMenuStore.open(x, y, items);
}

/** Close context menu. */
export function closeContextMenu() {
  contextMenuStore.close();
}

/** Media ID for the ListPicker add-to-list modal. */
export const activeListPickerMediaId = writable<string | null>(null);

export function openListPicker(mediaId: string) {
  activeListPickerMediaId.set(mediaId);
}

export function closeListPicker() {
  activeListPickerMediaId.set(null);
}
