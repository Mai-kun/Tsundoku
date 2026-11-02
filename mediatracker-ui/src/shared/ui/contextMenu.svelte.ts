import { writable } from "svelte/store";

/** Пункт контекстного меню. Для разделителя `kind: "separator"` поля label и action необязательны. */
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

/** Открыть контекстное меню в координатах (x, y). */
export function openContextMenu(x: number, y: number, items: MenuItem[]) {
  contextMenuStore.open(x, y, items);
}

/** Закрыть контекстное меню. */
export function closeContextMenu() {
  contextMenuStore.close();
}

/** ID тайтла для модалки добавления в список ListPicker. */
export const activeListPickerMediaId = writable<string | null>(null);

export function openListPicker(mediaId: string) {
  activeListPickerMediaId.set(mediaId);
}

export function closeListPicker() {
  activeListPickerMediaId.set(null);
}
