// External-source regression checks.
// Guards three fixes: honest connection tests, no silent cross-source fallback, Kitsu URL escaping.
const base = process.env.TRACKER_URL || "http://127.0.0.1:5000";
const log = (name, value) => console.log(`[${name}] ${value}`);
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const testSource = async (id) => {
  const response = await fetch(`${base}/api/settings/sources/${id}/test`, {
    method: "POST",
  });
  return { status: response.status, body: await response.json() };
};

const knownLive = ["anilist", "mangadex", "shikimori", "steam", "imdb"];
for (const id of knownLive) {
  const { body } = await testSource(id);
  // A live source must pass, and must not merely look like a timeout (~5s ceiling).
  assert(
    body.success === true,
    `${id} should be reachable but reported: ${JSON.stringify(body)}`,
  );
  assert(
    body.latencyMs < 4000,
    `${id} passed but latency ${body.latencyMs}ms looks like a silent timeout`,
  );
  log(`live ${id}`, `ok in ${body.latencyMs}ms`);
}

// An unreachable source must report failure. If it ever claims success again, the
// swallow-the-exception bug is back.
for (const id of ["tmdb", "jikan", "mangaupdates"]) {
  const { body } = await testSource(id);
  assert(
    body.success === false,
    `${id} is unreachable here but reported success: ${JSON.stringify(body)}`,
  );
  assert(
    typeof body.message === "string" && body.message.length > 0,
    `${id} failed without a reason`,
  );
  log(`dead ${id}`, body.message);
}

// An explicit source must never come back as a different provider's entity.
const tmdb = await fetch(
  `${base}/api/external/details?type=movie&source=tmdb&id=550&title=Matrix`,
);
assert(
  tmdb.status === 502,
  `unreachable source should be 502, got ${tmdb.status}`,
);
const body = await tmdb.json();
assert(
  !JSON.stringify(body).includes("kinopoiskapiunofficial.tech"),
  "leaked Kinopoisk entity for a tmdb request",
);
log("no wrong-source fallback", `502 with reason: ${body.detail}`);

// A reachable explicit source still resolves correctly.
const anilist = await fetch(
  `${base}/api/external/details?type=anime&source=anilist&id=1&title=Cowboy%20Bebop`,
);
assert(anilist.status === 200, `anilist details failed: ${anilist.status}`);
const details = await anilist.json();
assert(
  details.externalId === "1" && /cowboy bebop/i.test(details.title),
  "anilist returned wrong entity",
);
log(
  "explicit source",
  `anilist id=${details.externalId} title=${details.title}`,
);

// Kitsu brackets must be percent-encoded; an unescaped [ breaks strict URL parsers.
const kitsu = await fetch(
  `${base}/api/external/details?type=anime&source=kitsu&id=1&title=Cowboy%20Bebop`,
);
assert(kitsu.status === 200, `kitsu details failed: ${kitsu.status}`);
const kitsuBody = await kitsu.json();
assert(
  String(kitsuBody.externalSource || "")
    .toLowerCase()
    .includes("kitsu"),
  `kitsu returned ${kitsuBody.externalSource}`,
);
log("kitsu escaping", `ok id=${kitsuBody.externalId}`);

// Search must still work across types after providers stopped swallowing errors.
for (const type of ["anime", "manga", "book", "movie", "game"]) {
  const response = await fetch(
    `${base}/api/external/search?type=${type}&query=Cowboy`,
  );
  assert(response.status === 200, `search ${type} failed: ${response.status}`);
  const results = await response.json();
  assert(
    Array.isArray(results) && results.length > 0,
    `search ${type} returned no results`,
  );
  log(`search ${type}`, `${results.length} results`);
}

console.log("ALL EXTERNAL SOURCE CHECKS PASSED");
