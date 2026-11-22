import http from "node:http";
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import path from "node:path";
import fs from "node:fs";

const BASE_URL = process.env.TS_BASE || "http://127.0.0.1:5099";
const DB_PATH = process.env.TS_DB || "/tmp/tsundoku-pixel-audit/tracker.db";

async function postJson(endpoint, body) {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`POST ${endpoint} failed (${res.status}): ${txt}`);
  }
  const txt = await res.text();
  return txt ? JSON.parse(txt) : {};
}

async function putJson(endpoint, body) {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`PUT ${endpoint} failed (${res.status}): ${txt}`);
  }
  const txt = await res.text();
  return txt ? JSON.parse(txt) : {};
}

export async function seedAuditData() {
  console.log(`🌱 Seeding audit data into ${BASE_URL}...`);

  // 1. Anime: Sousou no Frieren
  const frierenEpisodes = [];
  for (let i = 1; i <= 28; i++) {
    frierenEpisodes.push({
      number: i,
      title: `Эпизод ${i}: ${i === 1 ? "Конец приключения" : i === 2 ? "Магия не для убийства" : "Путь на север"}`,
      airDate: `2023-${(9 + Math.floor(i / 4)).toString().padStart(2, "0")}-${(1 + (i % 28)).toString().padStart(2, "0")}`,
      overview: `Описание серии ${i} путешествия Фрирен и её учеников.`
    });
  }

  const frieren = await postJson("/api/media", {
    type: "tvshow",
    isAnime: true,
    title: "Провожающая в последний путь Фрирен",
    romajiTitle: "Sousou no Frieren",
    altTitles: ["Frieren: Beyond Journey's End", "葬送のフリーレン"],
    status: 1, // InProgress
    score: 10,
    studio: "Madhouse",
    director: "Кэйитиро Сайто",
    releaseYear: 2023,
    releaseDate: "2023-09-29T00:00:00Z",
    genres: "Аниме, Приключения, Драма, Фэнтези, Сёнэн",
    tags: "Магия, Эльфы, Путешествия, Меланхолия, Дружба",
    description: "История начинается там, где обычные фэнтезийные саги заканчиваются: отряд героев побеждает владыку демонов и возвращается с триумфом. Но эльфийка Фрирен живет тысячелетиями, в то время как её смертные спутники стареют и умирают. Похоронив старых друзей, она отправляется в новое странствие, чтобы лучше понять природу человеческих чувств.",
    seasons: [
      {
        seasonNumber: 1,
        title: "Сезон 1",
        totalEpisodes: 28,
        currentEpisode: 16,
        status: 1,
        episodesData: JSON.stringify(frierenEpisodes)
      }
    ],
    coverUrl: "/placeholder-404.jpg"
  });

  console.log(`  ✓ Created Anime: Frieren (${frieren.id})`);

  // Link external sources to Frieren
  try {
    await postJson(`/api/media/${frieren.id}/linked-sources`, {
      source: "AniList",
      externalId: "154587",
      url: "https://anilist.co/anime/154587",
      isPrimary: true
    });
    await postJson(`/api/media/${frieren.id}/linked-sources`, {
      source: "Kitsu",
      externalId: "46853",
      url: "https://kitsu.app/anime/sousou-no-frieren",
      isPrimary: false
    });
    await postJson(`/api/media/${frieren.id}/linked-sources`, {
      source: "MyAnimeList",
      externalId: "52991",
      url: "https://myanimelist.net/anime/52991",
      isPrimary: false
    });
  } catch (e) {
    console.warn("  Could not link sources to Frieren:", e.message);
  }

  // 2. Book: Crime and Punishment
  const crime = await postJson("/api/media", {
    type: "book",
    title: "Преступление и наказание",
    author: "Фёдор Михайлович Достоевский",
    status: 2, // Completed
    score: 9,
    totalPages: 672,
    currentPage: 672,
    isbn: "978-5-17-090624-6",
    format: "Бумажная книга",
    releaseYear: 1866,
    releaseDate: "1866-01-01T00:00:00Z",
    genres: "Классика, Психологический роман, Детектив",
    tags: "Петербург, Философия, Раскольников, Совесть, Мораль",
    description: "Бедный студент Родион Раскольников решается на страшный шаг — убийство старухи-процентщицы. Он убеждён, что сильные личности имеют право переступать через закон ради великих целей. Однако содеянное оборачивается для него душевным адом.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created Book: Crime and Punishment (${crime.id})`);

  // 3. Manga: Berserk
  const berserk = await postJson("/api/media", {
    type: "manga",
    title: "Берсерк",
    author: "Кэнтаро Миура",
    status: 1, // InProgress
    score: 10,
    totalChapters: 364,
    currentChapter: 120,
    totalVolumes: 41,
    currentVolume: 14,
    releaseYear: 1989,
    releaseDate: "1989-08-25T00:00:00Z",
    genres: "Манга, Тёмное фэнтези, Сэйнэн, Экшен, Ужасы",
    tags: "Гатс, Мечи, Средневековье, Предательство, Демоны",
    description: "Эпическая сага о Гатсе, беспощадном наёмнике по прозвищу Чёрный Мечник, ведомом жаждой мести против своего бывшего командира и лучшего друга Гриффита.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created Manga: Berserk (${berserk.id})`);

  // 4. Movie: Interstellar
  const interstellar = await postJson("/api/media", {
    type: "movie",
    title: "Интерстеллар",
    director: "Кристофер Нолан",
    studio: "Syncopy, Lynda Obst Productions",
    status: 2, // Completed
    score: 10,
    durationMinutes: 169,
    releaseYear: 2014,
    releaseDate: "2014-11-07T00:00:00Z",
    genres: "Фильм, Научная фантастика, Драма, Приключения",
    tags: "Космос, Черная дыра, Гравитация, Время, Отец и дочь",
    description: "В будущем, когда ресурсы Земли истощены, группа исследователей отправляется сквозь червоточину в неизведанные глубины космоса на поиски нового дома для человечества.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created Movie: Interstellar (${interstellar.id})`);

  // 5. Game: Baldur's Gate 3
  const bg3 = await postJson("/api/media", {
    type: "game",
    title: "Baldur's Gate 3",
    status: 1, // InProgress
    platform: "PC",
    hoursPlayed: 125,
    score: 10,
    releaseYear: 2023,
    releaseDate: "2023-08-03T00:00:00Z",
    genres: "Игра, RPG, Тактика, Пошаговая, Кооператив",
    tags: "D&D, Магия, Иллитиды, Свобода выбора, Диалоги",
    description: "Возвращение легендарной партийной ролевой игры от Larian Studios во вселенной Dungeons & Dragons. Паразит пожирателя разума внутри вас дарует невиданную силу, но требует высокой цены.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created Game: Baldur's Gate 3 (${bg3.id})`);

  // 6. Game: Cyberpunk 2077
  const cp2077 = await postJson("/api/media", {
    type: "game",
    title: "Cyberpunk 2077",
    status: 2, // Completed
    platform: "PC",
    hoursPlayed: 85,
    score: 9,
    releaseYear: 2020,
    releaseDate: "2020-12-10T00:00:00Z",
    genres: "Игра, Action-RPG, Открытый мир, Киберпанк",
    tags: "Найт-Сити, Джонни Сильверхенд, Импланты, Будущее",
    description: "Приключенческая ролевая игра с открытым миром, действие которой происходит в мегаполисе Найт-Сити, где власть, роскошь и модификации тела ценятся превыше всего.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created Game: Cyberpunk 2077 (${cp2077.id})`);

  // 7. TV Show: Breaking Bad
  const breakingBad = await postJson("/api/media", {
    type: "tvshow",
    isAnime: false,
    title: "Во все тяжкие",
    director: "Винс Гиллиган",
    status: 2, // Completed
    score: 10,
    releaseYear: 2008,
    releaseDate: "2008-01-20T00:00:00Z",
    genres: "Сериал, Криминал, Драма, Триллер",
    tags: "Уолтер Уайт, Хайзенберг, Химия, Альбукерке, Метамфетамин",
    description: "Школьный учитель химии Уолтер Уайт узнаёт о неизлечимой болезни и решает заняться изготовлением наркотиков, чтобы обеспечить будущее своей семьи.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created TV Show: Breaking Bad (${breakingBad.id})`);

  // 8. Book: Dune
  const dune = await postJson("/api/media", {
    type: "book",
    title: "Дюна",
    author: "Фрэнк Герберт",
    status: 0, // Planned
    totalPages: 704,
    isbn: "978-5-17-083654-3",
    releaseYear: 1965,
    releaseDate: "1965-08-01T00:00:00Z",
    genres: "Книга, Научная фантастика, Космоопера, Философия",
    tags: "Арракис, Пряность, Песчаные черви, Пол Атрейдес, Империя",
    description: "Пустынная планета Арракис — единственный во Вселенной источник спайса, самого ценного вещества в галактике. Тот, кто контролирует Дюну, контролирует судьбу человечества.",
    coverUrl: "/placeholder-404.jpg"
  });
  console.log(`  ✓ Created Book: Dune (${dune.id})`);

  // 9. Lists
  const list1 = await postJson("/api/lists", {
    name: "Избранные шедевры",
    description: "Золотой фонд мировой культуры и личные фавориты",
    icon: "sparkles",
    color: "#f59e0b"
  });
  await postJson(`/api/lists/${list1.id}/items`, { mediaId: frieren.id });
  await postJson(`/api/lists/${list1.id}/items`, { mediaId: interstellar.id });
  await postJson(`/api/lists/${list1.id}/items`, { mediaId: bg3.id });
  console.log(`  ✓ Created List: ${list1.name} (${list1.id})`);

  const list2 = await postJson("/api/lists", {
    name: "Пройти на каникулах",
    description: "Игры и аниме для праздничного марафона",
    icon: "gamepad-2",
    color: "#10b981"
  });
  await postJson(`/api/lists/${list2.id}/items`, { mediaId: cp2077.id });
  await postJson(`/api/lists/${list2.id}/items`, { mediaId: berserk.id });
  console.log(`  ✓ Created List: ${list2.name} (${list2.id})`);

  // 10. Goals
  const goal1 = await postJson("/api/goals", {
    title: "Прочитать 20 книг в 2026",
    description: "Регулярное чтение литературы классики и фантастики",
    year: 2026,
    targetCount: 20,
    category: "book",
    icon: "book"
  });
  console.log(`  ✓ Created Goal: ${goal1.title}`);

  const goal2 = await postJson("/api/goals", {
    title: "Пройти 10 игр в 2026",
    description: "Закрыть отложенный игровой бэклог",
    year: 2026,
    targetCount: 10,
    category: "game",
    icon: "gamepad2"
  });
  console.log(`  ✓ Created Goal: ${goal2.title}`);

  // Now, update CastJson and Calendar events directly in SQLite to give 100% rich detail
  if (fs.existsSync(DB_PATH)) {
    const frierenCast = JSON.stringify([
      { Name: "Ацуми Танэдзаки", Character: "Фрирен (Frieren)", PhotoUrl: null },
      { Name: "Кана Итиносэ", Character: "Ферн (Fern)", PhotoUrl: null },
      { Name: "Тиаки Кобаяси", Character: "Штарк (Stark)", PhotoUrl: null },
      { Name: "Нобухико Окамото", Character: "Химмель (Himmel)", PhotoUrl: null },
      { Name: "Хироки Тоти", Character: "Гайтер (Heiter)", PhotoUrl: null },
      { Name: "Ёдзи Уэда", Character: "Айзен (Eisen)", PhotoUrl: null }
    ]);

    const now = new Date().toISOString();
    const yesterday = new Date(Date.now() - 86400000).toISOString();
    const twoDaysAgo = new Date(Date.now() - 172800000).toISOString();

    const todayDate = new Date();
    const curYear = todayDate.getFullYear();
    const curMonth = (todayDate.getMonth() + 1).toString().padStart(2, "0");
    const calDate1 = `${curYear}-${curMonth}-15T00:00:00Z`;
    const calDate2 = `${curYear}-${curMonth}-22T00:00:00Z`;
    const calDate3 = `${curYear}-${curMonth}-28T00:00:00Z`;

    const e1 = crypto.randomUUID();
    const e2 = crypto.randomUUID();
    const e3 = crypto.randomUUID();
    const e4 = crypto.randomUUID();

    const sqlCommands = `
UPDATE MediaItems SET CastJson = '${frierenCast.replace(/'/g, "''")}' WHERE Id = '${frieren.id}';
INSERT OR REPLACE INTO Events (Id, MediaId, Type, OldValue, NewValue, CreatedAt) VALUES ('${e1}', '${frieren.id}', 3, '15', '16', '${now}');
INSERT OR REPLACE INTO Events (Id, MediaId, Type, OldValue, NewValue, CreatedAt) VALUES ('${e2}', '${bg3.id}', 3, '110', '125', '${yesterday}');
INSERT OR REPLACE INTO Events (Id, MediaId, Type, OldValue, NewValue, CreatedAt) VALUES ('${e3}', '${crime.id}', 1, '1', '2', '${twoDaysAgo}');
INSERT OR REPLACE INTO Events (Id, MediaId, Type, OldValue, NewValue, CreatedAt) VALUES ('${e4}', '${interstellar.id}', 2, '0', '10', '${twoDaysAgo}');
UPDATE MediaItems SET ReleaseDate = '${calDate1}' WHERE Id = '${dune.id}';
UPDATE MediaItems SET NextAutoRefreshAt = '${calDate2}' WHERE Id = '${frieren.id}';
UPDATE TvSeasons SET AirDate = '${calDate3}' WHERE TvShowId = '${frieren.id}';
`;

    execFileSync("sqlite3", [DB_PATH, sqlCommands]);
    console.log(`  ✓ Updated CastJson, History Events and Calendar Air Dates in SQLite.`);
  }

  return {
    frierenId: frieren.id,
    crimeId: crime.id,
    berserkId: berserk.id,
    interstellarId: interstellar.id,
    bg3Id: bg3.id,
    cp2077Id: cp2077.id,
    breakingBadId: breakingBad.id,
    duneId: dune.id,
    list1Id: list1.id,
    list2Id: list2.id,
    goal1Id: goal1.id,
    goal2Id: goal2.id
  };
}

if (process.argv[1] && process.argv[1].endsWith("seed-pixel-audit.mjs")) {
  seedAuditData()
    .then((res) => {
      console.log("Seeding complete:", res);
      process.exit(0);
    })
    .catch((err) => {
      console.error("Seeding failed:", err);
      process.exit(1);
    });
}
