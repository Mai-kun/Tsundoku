import { en } from "./en";
import { ru, type Dictionary } from "./ru";

export type Locale = "ru" | "en";

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

class I18nService {
  current = $state<Locale>(readStoredLocale());

  get t(): Dictionary {
    return this.current === "en" ? en : ru;
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
