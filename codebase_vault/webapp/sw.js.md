# sw.js

## Architecture Metrics
- **Path:** `webapp/sw.js`
- **Extension:** `.js`
- **Size:** 1532 bytes
- **Centrality Score:** 0.0001
- **In-Degree (Imported By):** 0
- **Out-Degree (Imports):** 0

## Explanation
*No explanation provided in source code.*

## Structural Outline
*No major classes or functions detected.*

## Imports (Dependencies)
*No internal imports*

## Imported By (Dependents)
*Not imported by any file*

## Source Code Snippet
```js
const CACHE_NAME = 'doctransit-pwa-v22';
const ASSETS = [
  '/',
  '/index.html',
  '/phone.html',
  '/install.html',
  '/fflate.min.js',
  '/manifest.json',
  '/icon.png',
  '/icon-192.png',
  '/icon-512.png',
  '/logo.png',
  '/qr.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/jsqr/1.4.0/jsQR.min.js',
  'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
...
```