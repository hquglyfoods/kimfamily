// 우리집 도장판 service worker — 푸시 수신 전용, 캐시 없음(항상 최신 앱)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) {}
  e.waitUntil(self.registration.showNotification(d.title || '⭐ 우리집 도장판', {
    body: d.body || '',
    icon: "https://glifusercontent.com/i:r/rxj3rjaoi1hx433rfpcx.jpg",
    badge: "https://glifusercontent.com/i:r/rxj3rjaoi1hx433rfpcx.jpg",
    data: { url: d.url || "https://kimfam.netlify.app/" }
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || "https://kimfam.netlify.app/";
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) { if (c.url.indexOf('kimfam') !== -1 && 'focus' in c) return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
