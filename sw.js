// 앱 화면 파일만 캐시 (네트워크 우선). 가계부 데이터(Supabase 요청)는 절대 캐시하지 않음.
const CACHE = "gagyebu-v5";
const SHELL = ["./", "./index.html", "./supabase.js", "./manifest.webmanifest", "./icon-192.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== self.location.origin) return;
  e.respondWith(fetch(e.request).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); } return res; })
    .catch(() => caches.match(e.request).then(r => r || caches.match("./index.html"))));
});
