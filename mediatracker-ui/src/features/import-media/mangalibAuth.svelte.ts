import { invoke } from "@tauri-apps/api/core";
import { getSourceKeyStatus, saveSourceKey } from "$shared/api/api";
import { i18n } from "$shared/i18n/index.svelte";
import { showToast } from "$shared/ui/toast.svelte";
import { isTauri } from "$shared/utils/tauri";

/**
 * Native MangaLib (SocialLib) auth state, shared by the import panel and the
 * settings sources tab. The Bearer token is captured by the Tauri auth window
 * (`save_mangalib_auth` -> `mangalib-authenticated` event), persisted through
 * the encrypted source-key storage and never kept in the frontend; only the
 * non-secret User ID lives in localStorage for one-click imports.
 */

const USER_ID_KEY = "mangalib_user_id";

export const mangalibAuth = $state({
  checking: true,
  connected: false,
  maskedKey: null as string | null,
  userId: "",
});

export function readStoredMangalibUserId(): string {
  try {
    return localStorage.getItem(USER_ID_KEY)?.trim() ?? "";
  } catch {
    return "";
  }
}

export async function refreshMangalibAuth(): Promise<void> {
  if (!isTauri()) {
    mangalibAuth.checking = false;
    return;
  }
  try {
    const status = await getSourceKeyStatus("mangalib");
    mangalibAuth.connected = status.hasKey;
    mangalibAuth.maskedKey = status.maskedKey;
    mangalibAuth.userId = readStoredMangalibUserId();
  } catch {
    // Status is cosmetic; the import itself degrades to manual token entry.
  } finally {
    mangalibAuth.checking = false;
  }
}

/** Opens the native MangaLib login popup (Tauri shell only). */
export function openMangalibAuthWindow(): void {
  if (!isTauri()) return;
  invoke("open_mangalib_auth_window").catch((error) => {
    console.error("open_mangalib_auth_window failed:", error);
    showToast(i18n.t.importModal.mangalibAuth.authFailed, "error");
  });
}

/**
 * Handles the `mangalib-authenticated` event from the Tauri shell: persists
 * the captured token into the encrypted source-key storage, remembers the
 * non-secret User ID for one-click imports and refreshes the shared state.
 */
export async function handleMangalibAuthenticated(token: string, userId: string): Promise<void> {
  try {
    await saveSourceKey("mangalib", token);
    if (userId) {
      try {
        localStorage.setItem(USER_ID_KEY, userId.trim());
      } catch {
        // Storage unavailable: the user can still type the ID manually.
      }
    }
    await refreshMangalibAuth();
    showToast(i18n.t.importModal.mangalibAuth.connectedToast, "success");
  } catch (error) {
    console.error("save mangalib token failed:", error);
    showToast(i18n.t.importModal.mangalibAuth.saveFailed, "error");
  }
}

/** Clears the stored token and the remembered User ID. */
export async function disconnectMangalib(): Promise<void> {
  try {
    await saveSourceKey("mangalib", "");
    try {
      localStorage.removeItem(USER_ID_KEY);
    } catch {
      // Ignore: nothing to clean up locally.
    }
    await refreshMangalibAuth();
    showToast(i18n.t.importModal.mangalibAuth.disconnectedToast, "success");
  } catch (error) {
    console.error("clear mangalib token failed:", error);
    showToast(i18n.t.importModal.mangalibAuth.saveFailed, "error");
  }
}
