# sw_js.ts

## Architecture Metrics
- **Path:** `worker/src/sw_js.ts`
- **Extension:** `.ts`
- **Size:** 1615 bytes
- **Centrality Score:** 0.0001
- **In-Degree (Imported By):** 1
- **Out-Degree (Imports):** 0

## Explanation
*No explanation provided in source code.*

## Structural Outline
*No major classes or functions detected.*

## Imports (Dependencies)
*No internal imports*

## Imported By (Dependents)
- [[worker/src/index.ts.md|worker/src/index.ts]]

## Source Code Snippet
```ts
export const SW_JS = "const CACHE_NAME = 'doctransit-pwa-v22';\nconst ASSETS = [\n  '/',\n  '/index.html',\n  '/phone.html',\n  '/install.html',\n  '/fflate.min.js',\n  '/manifest.json',\n  '/icon.png',\n  '/icon-192.png',\n  '/icon-512.png',\n  '/logo.png',\n  '/qr.min.js',\n  'https://cdnjs.cloudflare.com/ajax/libs/jsqr/1.4.0/jsQR.min.js',\n  'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js'\n];\n\nself.addEventListener('install', (event) => {\n  self.skipWaiting();\n  event.waitUntil(\n    caches.open(CACHE_NAME).then((cache) => {\n      return Promise.allSettled(\n        ASSETS.map((asset) => cache.add(asset).catch(() => {}))\n      );\n    })\n  );\n});\n\nself.addEventListener('activate', (event) => {\n  event.waitUntil(\n    caches.keys().then((cacheNames) => {\n      return Promise.all(\n        cacheNames.map((cacheName) => {\n          if (cacheName !== CACHE_NAME) {\n            return caches.delete(cacheName);\n          }\n        })\n      );\n    }).then(() => self.clients.claim())\n  );\n});\n\nself.addEventListener('fetch', (event) => {\n  // Only intercept GET requests\n  if (event.request.method !== 'GET') return;\n\n  event.respondWith(\n    fetch(event.request)\n      .then((networkResponse) => {\n        if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic') {\n          const responseClone = networkResponse.clone();\n          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));\n        }\n        return networkResponse;\n      })\n      .catch(() => caches.match(event.request))\n  );\n});\n";
```