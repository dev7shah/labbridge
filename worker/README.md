# DocTransit Worker

Cloudflare Worker that handles QR session pairing and encrypted file relay.

## Deploy

1. Install wrangler: `npm install -g wrangler`
2. Login: `npx wrangler login`
3. Set your account_id in wrangler.toml
4. Deploy: `npx wrangler deploy`
5. Your worker URL will be: `wss://doctransit.YOUR_SUBDOMAIN.workers.dev`
6. Set this URL in the DocTransit app under Settings → Worker URL

## Local Dev

```bash
npm install
npx wrangler dev
```

Worker runs at `ws://localhost:8787` — use `ws://10.0.2.2:8787` from Android emulator.

## Security Notes

- Sessions expire after 5 minutes
- File chunks are end-to-end encrypted (AES-256-GCM) — worker never decrypts
- No file data is stored or logged
- Sessions are single-use — once paired, no third device can join
