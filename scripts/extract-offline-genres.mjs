#!/usr/bin/env node
/**
 * Extracts the unique genre/tag vocabulary from an offline SQLite database
 * (data/offline/anime_offline.db) and checks it against the server's genre
 * dictionary (MediaTracker.Server/Resources/genres-dictionary.json).
 *
 * Usage:
 *   node scripts/extract-offline-genres.mjs [dbPath] [dictionaryPath]
 *
 * Defaults: data/offline/anime_offline.db and the bundled dictionary.
 * Prints the recognized genres with their Russian names and the top
 * unrecognized tags so the dictionary can be extended by hand.
 */
import { DatabaseSync } from "node:sqlite";
import { readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dbPath = process.argv[2] ?? join(root, "data/offline/anime_offline.db");
const dictPath =
  process.argv[3] ?? join(root, "MediaTracker.Server/Resources/genres-dictionary.json");

if (!existsSync(dbPath)) {
  console.error(`Database not found: ${dbPath}`);
  process.exit(1);
}
if (!existsSync(dictPath)) {
  console.error(`Dictionary not found: ${dictPath}`);
  process.exit(1);
}

/** Same normalization as GenreNormalizer.BuildLookupKey on the server. */
function lookupKey(value) {
  return value
    .replace(/[\s\-\t\r\n]+/g, " ")
    .trim()
    .toLowerCase();
}

const dictionary = JSON.parse(readFileSync(dictPath, "utf8"));
const aliasToCanonical = new Map();
for (const [key, entry] of Object.entries(dictionary)) {
  for (const alias of [entry.en, key, ...(entry.aliases ?? [])]) {
    aliasToCanonical.set(lookupKey(alias), key);
  }
}

const db = new DatabaseSync(dbPath, { readOnly: true });
const rows = db
  .prepare("SELECT Genres FROM OfflineMedia WHERE Genres IS NOT NULL AND Genres != ''")
  .all();

const frequency = new Map();
for (const row of rows) {
  for (const raw of row.Genres.split(",")) {
    const tag = raw.trim();
    if (tag) frequency.set(tag, (frequency.get(tag) ?? 0) + 1);
  }
}

const recognized = new Map();
const unrecognized = [];
for (const [tag, count] of frequency) {
  const canonical = aliasToCanonical.get(lookupKey(tag));
  if (canonical && dictionary[canonical]?.isGenre !== false) {
    const entry = recognized.get(canonical) ?? { count: 0, ru: dictionary[canonical].ru, tags: [] };
    entry.count += count;
    if (lookupKey(tag) !== canonical) entry.tags.push(tag);
    recognized.set(canonical, entry);
  } else {
    unrecognized.push([tag, count]);
  }
}

console.log(`Rows scanned: ${rows.length}, unique tags: ${frequency.size}\n`);
console.log(`== Recognized genres (${recognized.size}) ==`);
for (const [key, entry] of [...recognized.entries()].sort((a, b) => b[1].count - a[1].count)) {
  const extra = entry.tags.length ? ` (aliases: ${entry.tags.slice(0, 4).join(", ")})` : "";
  console.log(`  ${key} -> ${entry.ru} [${entry.count}]${extra}`);
}

unrecognized.sort((a, b) => b[1] - a[1]);
console.log(`\n== Top unrecognized tags (${unrecognized.length}) ==`);
for (const [tag, count] of unrecognized.slice(0, 60)) {
  console.log(`  ${tag} [${count}]`);
}
console.log(
  `\nRecognition: ${(frequency.size && [...recognized.values()].reduce((s, e) => s + e.count, 0)) ?? 0} of ${rows.length ? [...frequency.values()].reduce((s, c) => s + c, 0) : 0} tag occurrences.`,
);
