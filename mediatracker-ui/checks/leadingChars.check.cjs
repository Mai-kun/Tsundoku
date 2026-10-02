// Source-encoding guards.
//
// 1. A .svelte file must not start with a stray character before its first tag:
//    Svelte renders such characters as a literal text node (a visible "?").
// 2. No file may contain mojibake — text that was decoded as Windows-1251 and
//    re-encoded as UTF-8, e.g. "Кинопоиск" -> "РљРёРЅРѕРїРѕРёСЃРє".
//    It renders as garbage in the UI and is easy to reintroduce by saving a
//    file with the wrong encoding, so it gets an explicit guard.
const { readdirSync, readFileSync, statSync } = require('node:fs')
const { join } = require('node:path')

const ROOT = join(__dirname, '..', 'src')
const BOM = 0xfeff
const offenders = []

// Node ships full ICU, so the real cp1251 codec is available. Using it avoids
// hand-rolling a mapping table and missing the U+0400/U+0450 Cyrillic blocks
// that real mojibake is full of.
const cp1251 = new TextDecoder('windows-1251', { fatal: false })

const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    if (statSync(full).isDirectory()) walk(full)
    else if (/\.(svelte|ts|css|html)$/.test(name)) check(full)
  }
}

// Mojibake is text that was ENCODED as cp1251 bytes and then decoded as UTF-8:
// "Кинопоиск" -> utf8 bytes -> read as cp1251 -> "РљРёРЅРѕРїРѕРёСЃРє".
// To detect it, encode the suspect run AS cp1251 and see whether the result is
// valid UTF-8 spelling different text. Correct Russian fails that round-trip
// (cp1251 cannot represent it), so it is never flagged.
const cp1251Encode = (text) => {
  const bytes = []
  for (const ch of text) {
    const cp = ch.codePointAt(0)
    if (cp < 0x80) {
      bytes.push(cp)
      continue
    }
    // Build the cp1251 high half by decoding each byte back to a character.
    let mapped = -1
    for (let b = 0x80; b < 0x100; b++) {
      const back = cp1251.decode(Uint8Array.of(b))
      if (back && back.codePointAt(0) === cp) {
        mapped = b
        break
      }
    }
    if (mapped === -1) return null
    bytes.push(mapped)
  }
  return Buffer.from(bytes)
}

// Returns the repaired string, or null when the run is legitimate text.
const isMojibake = (run) => {
  const bytes = cp1251Encode(run)
  if (!bytes) return null
  let decoded
  try {
    // strict: any invalid UTF-8 sequence throws, so real text cannot pass.
    decoded = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    return null
  }
  if (decoded === run) return null
  // Sanity: the repair must stay in the Cyrillic/Latin range, not turn into
  // punctuation soup. Require that it still looks like words.
  if (!/[^\x00-\x7F]/.test(decoded)) return null
  if (decoded.length < 2) return null
  return decoded
}

const check = (file) => {
  const text = readFileSync(file, 'utf8')
  const body = text.charCodeAt(0) === BOM ? text.slice(1) : text

  // Only .svelte can render leading junk as a text node; in .ts/.css a leading
  // "@"/"import"/"export" is the file's actual first token.
  if (file.endsWith('.svelte')) {
    const stray = body.match(/^\s*([^\s<])/)
    if (stray) offenders.push(`${file}: stray leading ${JSON.stringify(stray[1])}`)
  }

  for (const run of body.match(/[^\x00-\x7F]+/g) ?? []) {
    const repaired = isMojibake(run)
    if (repaired) {
      offenders.push(`${file}: ${JSON.stringify(run)} should be ${JSON.stringify(repaired)}`)
    }
  }
}

walk(ROOT)

if (offenders.length) {
  console.error(
    `source encoding problems (${offenders.length}):\n` + offenders.slice(0, 20).join('\n'),
  )
  process.exit(1)
}
console.log('OK: no stray leading characters or mojibake in source files')
