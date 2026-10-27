import { spawn, execSync, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export interface SeededIds {
  gameId: string;
  movieId: string;
  tvshowId: string;
  mangaId: string;
  bookId: string;
  droppedGameId: string;
  listId: string;
  allIds: string[];
}

export interface ServerHarness {
  baseUrl: string;
  port: number;
  dataDir: string;
  isManaged: boolean;
  seededIds: SeededIds;
  stop: () => Promise<void>;
}

async function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, "127.0.0.1", () => {
      const address = srv.address();
      if (!address || typeof address === "string") {
        srv.close(() => reject(new Error("Unable to determine port")));
        return;
      }
      const port = address.port;
      srv.close((err) => {
        if (err) reject(err);
        else resolve(port);
      });
    });
    srv.on("error", reject);
  });
}

async function waitForServer(url: string, timeoutMs = 180000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${url}/api/media`, { signal: AbortSignal.timeout(1500) });
      if (res.ok) return;
    } catch {
      // Waiting for server to become responsive
    }
    await new Promise((r) => setTimeout(r, 350));
  }
  throw new Error(`Server at ${url} failed to respond within ${timeoutMs}ms`);
}

async function seedData(baseUrl: string): Promise<SeededIds> {
  // Check if DB already has records
  try {
    const existingRes = await fetch(`${baseUrl}/api/media`);
    if (existingRes.ok) {
      const existing = (await existingRes.json()) as Array<{ id: string; type: string }>;
      if (Array.isArray(existing) && existing.length >= 15) {
        const game = existing.find((x) => x.type === "game");
        const movie = existing.find((x) => x.type === "movie");
        const tv = existing.find((x) => x.type === "tvshow");
        const manga = existing.find((x) => x.type === "manga");
        const book = existing.find((x) => x.type === "book");

        let listId = "";
        try {
          const listsRes = await fetch(`${baseUrl}/api/lists`);
          if (listsRes.ok) {
            const lists = (await listsRes.json()) as Array<{ id: string }>;
            if (lists.length > 0) listId = lists[0].id;
          }
        } catch {
          // Ignore
        }

        return {
          gameId: game?.id || existing[0]?.id || "",
          movieId: movie?.id || existing[0]?.id || "",
          tvshowId: tv?.id || existing[0]?.id || "",
          mangaId: manga?.id || existing[0]?.id || "",
          bookId: book?.id || existing[0]?.id || "",
          droppedGameId: existing[0]?.id || "",
          listId,
          allIds: existing.map((x) => x.id),
        };
      }
    }
  } catch {
    // Continue with seeding
  }

  const itemsToCreate: Array<Record<string, unknown>> = [
    // 1) Game (InProgress)
    {
      type: "game",
      title: "Elden Ring",
      status: 1, // InProgress
      score: 10,
      platform: "PC",
      hoursPlayed: 85,
      releaseYear: 2022,
      releaseDate: "2022-02-25T00:00:00Z",
      genres: "Action, RPG, Open World, Souls-like",
      description: "Rise, Tarnished, and be guided by grace to brandish the power of the Elden Ring.",
      director: "Hidetaka Miyazaki",
    },
    // 2) Movie (Completed)
    {
      type: "movie",
      title: "Spirited Away",
      status: 2, // Completed
      score: 10,
      durationMinutes: 125,
      releaseYear: 2001,
      releaseDate: "2001-07-20T00:00:00Z",
      genres: "Animation, Adventure, Fantasy",
      description: "A ten-year-old girl wanders into a world ruled by gods, witches, and spirits.",
      director: "Hayao Miyazaki",
      studio: "Studio Ghibli",
    },
    // 3) TV Show / Anime (InProgress) with seasons
    {
      type: "tvshow",
      title: "Frieren: Beyond Journey's End",
      status: 1, // InProgress
      score: 10,
      isAnime: true,
      releaseYear: 2023,
      releaseDate: "2023-09-29T00:00:00Z",
      genres: "Adventure, Drama, Fantasy",
      description: "An elf mage honors her fallen companions while learning what it means to live.",
      director: "Keiichiro Saito",
      studio: "Madhouse",
      seasons: [
        {
          seasonNumber: 1,
          title: "Season 1",
          totalEpisodes: 28,
          currentEpisode: 16,
          status: 1,
        },
      ],
    },
    // 4) Manga (Planned)
    {
      type: "manga",
      title: "Berserk",
      status: 0, // Planned
      score: 10,
      author: "Kentaro Miura",
      totalChapters: 364,
      totalVolumes: 41,
      releaseYear: 1989,
      releaseDate: "1989-08-25T00:00:00Z",
      genres: "Dark Fantasy, Action, Horror",
      description: "Guts, a former mercenary known as the Black Swordsman, seeks vengeance.",
    },
    // 5) Book (Dropped)
    {
      type: "book",
      title: "Finnegans Wake",
      status: 4, // Dropped
      score: 4,
      author: "James Joyce",
      totalPages: 628,
      releaseYear: 1939,
      releaseDate: "1939-05-04T00:00:00Z",
      genres: "Classic, Avant-Garde, Modernism",
      description: "A complex comic fiction known for its experimental language and style.",
    },
    // 6) Dropped Game with reason
    {
      type: "game",
      title: "The Lord of the Rings: Gollum",
      status: 4, // Dropped
      score: 2,
      platform: "PC",
      releaseYear: 2023,
      genres: "Action, Adventure, Stealth",
      description: "Athletic and agile, sneaky and cunning.",
    },
  ];

  // Add 20 extra games and manga to guarantee virtual grid triggers (>= 15 items in category)
  const genresPool = ["Action", "RPG", "Sci-Fi", "Cyberpunk", "Strategy", "Mystery", "Indie"];
  for (let i = 1; i <= 15; i++) {
    itemsToCreate.push({
      type: "game",
      title: `Virtual Game Title ${i}`,
      status: i % 3 === 0 ? 2 : i % 2 === 0 ? 1 : 0,
      score: 6 + (i % 5),
      platform: i % 2 === 0 ? "PC" : "PlayStation 5",
      hoursPlayed: 10 + i * 4,
      releaseYear: 2018 + (i % 6),
      genres: `${genresPool[i % genresPool.length]}, ${genresPool[(i + 1) % genresPool.length]}`,
      description: `Comprehensive description for benchmark virtual grid card item ${i} checking text truncation and math.`,
    });
  }

  for (let i = 1; i <= 8; i++) {
    itemsToCreate.push({
      type: "manga",
      title: `Virtual Manga Series ${i}`,
      status: i % 2 === 0 ? 1 : 0,
      score: 7 + (i % 4),
      author: `Author Mangaka ${i}`,
      totalChapters: 50 + i * 15,
      releaseYear: 2015 + (i % 8),
      genres: "Fantasy, Adventure, Shounen",
      description: `Description for manga series number ${i} testing responsive layouts.`,
    });
  }

  const allIds: string[] = [];
  let gameId = "";
  let movieId = "";
  let tvshowId = "";
  let mangaId = "";
  let bookId = "";
  let droppedGameId = "";

  for (const item of itemsToCreate) {
    const res = await fetch(`${baseUrl}/api/media`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(item),
    });
    if (!res.ok) {
      const errText = await res.text();
      console.warn(`[testServerHarness] Warning: failed to seed item "${item.title}": ${errText}`);
      continue;
    }
    const data = (await res.json()) as { id: string };
    const id = data.id;
    allIds.push(id);

    if (item.title === "Elden Ring") gameId = id;
    else if (item.title === "Spirited Away") movieId = id;
    else if (item.title === "Frieren: Beyond Journey's End") tvshowId = id;
    else if (item.title === "Berserk") mangaId = id;
    else if (item.title === "Finnegans Wake") {
      bookId = id;
      // Set drop reason
      await fetch(`${baseUrl}/api/media/${id}/status`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          status: 4,
          dropReason: "boring",
          dropNotes: "Lost interest in stream of consciousness",
        }),
      });
    } else if (item.title === "The Lord of the Rings: Gollum") {
      droppedGameId = id;
      // Set drop reason
      await fetch(`${baseUrl}/api/media/${id}/status`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          status: 4,
          dropReason: "bad_perf",
          dropNotes: "Severe optimization bugs and broken stealth",
        }),
      });
    }
  }

  // Seed custom list
  let listId = "";
  try {
    const listRes = await fetch(`${baseUrl}/api/lists`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "Audit Masterpieces",
        description: "Curated collection created by testServerHarness",
        icon: "sparkles",
        color: "#f59e0b",
      }),
    });
    if (listRes.ok) {
      const listData = (await listRes.json()) as { id: string };
      listId = listData.id;
      if (gameId) {
        await fetch(`${baseUrl}/api/lists/${listId}/items`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ mediaId: gameId }),
        });
      }
      if (movieId) {
        await fetch(`${baseUrl}/api/lists/${listId}/items`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ mediaId: movieId }),
        });
      }
    }
  } catch (err) {
    console.warn("[testServerHarness] Warning: could not seed list:", err);
  }

  return {
    gameId: gameId || allIds[0] || "",
    movieId: movieId || allIds[0] || "",
    tvshowId: tvshowId || allIds[0] || "",
    mangaId: mangaId || allIds[0] || "",
    bookId: bookId || allIds[0] || "",
    droppedGameId: droppedGameId || allIds[0] || "",
    listId,
    allIds,
  };
}

export async function ensureTestServer(): Promise<ServerHarness> {
  const existingUrl = process.env.TS_BASE_EXISTING || process.env.TS_BASE;
  if (existingUrl) {
    console.log(`[testServerHarness] Using existing server at ${existingUrl}`);
    await waitForServer(existingUrl, 5000);
    const seededIds = await seedData(existingUrl);
    return {
      baseUrl: existingUrl,
      port: new URL(existingUrl).port ? parseInt(new URL(existingUrl).port, 10) : 80,
      dataDir: "",
      isManaged: false,
      seededIds,
      stop: async () => {},
    };
  }

  const port = await findFreePort();
  const tempDir = path.join(
    os.tmpdir(),
    `tsundoku-audit-db-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
  );
  fs.mkdirSync(tempDir, { recursive: true });

  // Fast boot optimization: copy pre-migrated empty template SQLite DB if available
  const fixtureDb = path.resolve(__dirname, "__fixtures__/tracker.db");
  if (fs.existsSync(fixtureDb)) {
    fs.copyFileSync(fixtureDb, path.join(tempDir, "tracker.db"));
    fs.copyFileSync(fixtureDb, path.join(tempDir, "tracker.dev.db"));
  }

  const serverProject = path.resolve(__dirname, "../../../MediaTracker.Server");
  const dllPath = path.join(serverProject, "bin/Debug/net10.0/Tsundoku.dll");

  const spawnArgs = fs.existsSync(dllPath)
    ? [dllPath, "--headless", "--port", port.toString(), "--data-dir", tempDir]
    : [
        "run",
        "--no-build",
        "--no-launch-profile",
        "--project",
        serverProject,
        "--",
        "--headless",
        "--port",
        port.toString(),
        "--data-dir",
        tempDir,
      ];

  console.log(`[testServerHarness] Launching server on port ${port} (dataDir: ${tempDir})...`);

  const proc: ChildProcess = spawn("dotnet", spawnArgs, {
    cwd: serverProject,
    stdio: "inherit",
    env: {
      ...process.env,
      ASPNETCORE_ENVIRONMENT: "Production",
    },
  });

  if (proc.pid && process.platform === "linux") {
    try {
      execSync(`renice -n 0 -p ${proc.pid}`, { stdio: "ignore" });
    } catch {
      // Ignore renice errors
    }
  }

  let procExited = false;
  let exitCode: number | null = null;
  proc.on("exit", (code) => {
    procExited = true;
    exitCode = code;
  });

  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    await waitForServer(baseUrl, 180000);
  } catch (err) {
    if (procExited) {
      throw new Error(`Server process exited prematurely with code ${exitCode}`);
    }
    proc.kill("SIGTERM");
    throw err;
  }

  console.log(`[testServerHarness] Server is ready on ${baseUrl}. Seeding test database...`);
  const seededIds = await seedData(baseUrl);
  console.log(
    `[testServerHarness] Seeded ${seededIds.allIds.length} items and list ${seededIds.listId || "none"}.`,
  );

  const stop = async () => {
    console.log(`[testServerHarness] Shutting down isolated server (PID ${proc.pid})...`);
    if (proc.pid && !procExited) {
      try {
        proc.kill("SIGTERM");
        // Give it 2 seconds to shut down gracefully
        await new Promise((r) => setTimeout(r, 2000));
        if (!procExited) {
          proc.kill("SIGKILL");
        }
      } catch {
        // Process might already be dead
      }
    }
    try {
      if (fs.existsSync(tempDir)) {
        fs.rmSync(tempDir, { recursive: true, force: true });
      }
    } catch (err) {
      console.warn(`[testServerHarness] Warning: could not clean up ${tempDir}:`, err);
    }
  };

  return {
    baseUrl,
    port,
    dataDir: tempDir,
    isManaged: true,
    seededIds,
    stop,
  };
}
