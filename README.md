# DocTransit

<p align="center">
  <img src="preview.jpg" alt="DocTransit Preview" width="100%">
</p>

Secure file transfer for students. Scan a QR on any lab PC to send files directly to your phone.

No accounts. No cloud storage. Files go straight to your phone.

## Architecture

- `worker/` — Cloudflare Worker (session relay, free tier)
- `webapp/` — PC browser app (single HTML file, no framework)
- `mobile/` — Flutter app (Android + iOS)

## Setup

### 1. Deploy the Worker

```bash
cd worker
npm install
npx wrangler login
npx wrangler deploy
```

Note your worker URL: `wss://doctransit.YOUR_SUBDOMAIN.workers.dev`

### 2. Set Worker URL in webapp

Edit `webapp/index.html` line 1:
```javascript
const WORKER_URL = 'wss://doctransit.YOUR_SUBDOMAIN.workers.dev';
```

### 3. Build Android APK

```bash
cd mobile

# First time only — generate release keystore
cd android && bash create_keystore.sh && cd ..

# Set env vars
export KEYSTORE_FILE=android/doctransit.keystore
export KEYSTORE_PASSWORD=your_password
export KEY_ALIAS=doctransit
export KEY_PASSWORD=your_password

# Build
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### 4. Build iOS IPA (requires Mac + Xcode)

```bash
cd mobile
flutter build ios --release
# Then archive in Xcode → Product → Archive
```

### 5. Run in Development

```bash
# Terminal 1 — Worker
cd worker && npx wrangler dev

# Terminal 2 — Mobile app
cd mobile && flutter run
```

Open `webapp/index.html` in Chrome for the PC side.

## Releasing

- Android: Upload `app-release.apk` to Google Play Console
- iOS: Archive in Xcode → distribute via App Store Connect
- Worker: Already live on Cloudflare (free forever)
- Webapp: Deploy `webapp/` to Cloudflare Pages (free forever)
