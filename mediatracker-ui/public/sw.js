const CACHE_NAME = 'tsundoku-pwa-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Для API-запросов и не-GET запросов всегда идем в сеть
  if (event.request.method !== 'GET' || event.request.url.includes('/api/')) {
    return;
  }
  // Network-First стратегия (свежий контент всегда приоритетен)
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
