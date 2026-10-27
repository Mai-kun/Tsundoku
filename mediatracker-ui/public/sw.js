const CACHE_NAME = 'tsundoku-pwa-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Пропускаем не-GET запросы и API
  if (event.request.method !== 'GET' || event.request.url.includes('/api/')) {
    return;
  }
  
  // КРИТИЧНО: Не перехватываем внешние CDN обложек (MangaLib, TMDb, AniList и т.д.),
  // чтобы браузер запрашивал их напрямую с нативным referrerpolicy="no-referrer"
  if (!event.request.url.startsWith(self.location.origin)) {
    return;
  }

  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
