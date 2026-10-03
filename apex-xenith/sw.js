const CACHE_NAME = 'max-apex-xenith-v2';
const urlsToCache = [
  './',
  'index.html',
  'css/style.css',
  'js/app.js',
  'js/main.js',
  'icons/icon-192x192.png',
  'icons/icon-512x512.png'
];

// 安装 Service Worker 并缓存资源
self.addEventListener('install', (event) => {
  console.log("正在预缓存静态资源");
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(urlsToCache);
    }).catch(err => console.error("预缓存失败:", err))
  );
});

// 激活时删除旧缓存，保证更新
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          if (cacheName !== CACHE_NAME) {
            console.log('清理旧缓存:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});

// 拦截请求，优先使用缓存，离线可用
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((response) => {
      return response || fetch(event.request);
    }).catch(() => caches.match('index.html'))
  );
});
