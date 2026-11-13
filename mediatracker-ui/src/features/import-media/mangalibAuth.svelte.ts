import { getSourceKeyStatus, saveSourceKey } from "$shared/api/api";
import { i18n } from "$shared/i18n/index.svelte";
import { showToast } from "$shared/ui/toast.svelte";

/**
 * MangaLib (SocialLib) auth state, shared by the import panel and the
 * settings sources tab. The Bearer token is picked up from the user's own
 * browser session (server-side detector, `detect-token` endpoint), persisted
 * through the encrypted source-key storage and never kept in the frontend;
 * only the non-secret User ID lives in localStorage for one-click imports.
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
  await readMangalibStatus();
}

/** Reads the server-side key status. */
async function readMangalibStatus(): Promise<void> {
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

/**
 * Manual token fallback (when browser pickup is unavailable): persists the
 * token the user pasted by hand. Returns true when the token was saved and
 * the shared state now reports connected.
 */
export async function saveMangalibToken(token: string): Promise<boolean> {
  const trimmed = token.trim();
  if (!trimmed) return false;
  try {
    await saveSourceKey("mangalib", trimmed);
    await readMangalibStatus();
    showToast({
      title: i18n.t.importModal.mangalibAuth.connectedToast,
      description: i18n.t.toast.descAuth,
    });
    return true;
  } catch (error) {
    console.error("save mangalib token failed:", error);
    showToast({
      title: i18n.t.importModal.mangalibAuth.saveFailed,
      description: i18n.t.toast.descRetry,
      type: "error",
    });
    return false;
  }
}

/**
 * Applies a session picked up from the user's browser (server already stored
 * the token encrypted): remembers the non-secret User ID for one-click imports
 * and refreshes the shared state so the card flips to connected.
 */
export async function adoptBrowserSession(userId: number | null): Promise<void> {
  if (userId) {
    try {
      localStorage.setItem(USER_ID_KEY, String(userId));
    } catch {
      // Storage unavailable: the user can still type the ID manually.
    }
  }
  // Read the server status directly: the detector already persisted the token.
  await readMangalibStatus();
  showToast({
    title: i18n.t.importModal.mangalibAuth.connectedToast,
    description: i18n.t.toast.descAuth,
  });
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
    showToast({
      title: i18n.t.importModal.mangalibAuth.disconnectedToast,
      description: i18n.t.toast.descAuthOff,
    });
  } catch (error) {
    console.error("clear mangalib token failed:", error);
    showToast({
      title: i18n.t.importModal.mangalibAuth.saveFailed,
      description: i18n.t.toast.descRetry,
      type: "error",
    });
  }
}
