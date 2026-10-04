import { translations, type Dictionary, type Locale } from "./translations";

export type { Dictionary, Locale } from "./translations";

export const locales: readonly Locale[] = ["ru", "en"];

const storageKey = "tsundoku_lang";

function readStoredLocale(): Locale {
  if (typeof localStorage === "undefined") {
    return "ru";
  }

  return localStorage.getItem(storageKey) === "en" ? "en" : "ru";
}

function syncDocumentLang(locale: Locale) {
  if (typeof document !== "undefined") {
    document.documentElement.lang = locale;
  }
}

/**
 * Flattens the paired tree down to the one language. Built once per locale and cached, so a
 * language switch is an array lookup rather than a full re-walk of ~400 keys on every keystroke
 * of the reactive graph that reads `t`.
 */
function buildDictionary(locale: Locale): Dictionary {
  const resolve = (node: unknown): unknown =>
    typeof node === "object" && node !== null && !Array.isArray(node)
      ? "ru" in node && "en" in node
        ? (node as Record<Locale, unknown>)[locale]
        : Object.fromEntries(
            Object.entries(node as Record<string, unknown>).map(([key, value]) => [
              key,
              resolve(value),
            ]),
          )
      : node;

  return resolve(translations) as Dictionary;
}

const dictionaries: Record<Locale, Dictionary> = {
  ru: buildDictionary("ru"),
  en: buildDictionary("en"),
};

class I18nService {
  current = $state<Locale>(readStoredLocale());

  get t(): Dictionary {
    return dictionaries[this.current];
  }

  setLocale(locale: Locale) {
    this.current = locale;

    if (typeof localStorage !== "undefined") {
      localStorage.setItem(storageKey, locale);
    }

    syncDocumentLang(locale);
  }
}

export const i18n = new I18nService();

syncDocumentLang(i18n.current);
