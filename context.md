# DocTransit: Comprehensive AI Context & Codebase Documentation

This document is designed specifically to provide context for AI agents reading or modifying this codebase. It contains a deep dive into the architecture, dependencies, state management, edge cases, and cryptographic implementation details of the DocTransit project.

## 1. Project Overview & Philosophy
DocTransit is an ultra-fast, browser-based peer-to-peer file transfer and messaging bridge between a desktop/laptop (PC) and a mobile device. 
- **Core Philosophy:** Zero app installations, zero user accounts, zero cloud storage.
- **Tech Stack:** Vanilla HTML/JS/CSS (Frontend) + Cloudflare Workers / Durable Objects (Backend).
- **Security:** Strict End-to-End Encryption (E2EE). The server (Relay) is completely blind to payloads.

## 2. Directory Structure & File Roles
```text
project-root/
├── webapp/
│   ├── index.html        # PC Terminal UI & Frontend Logic
│   └── phone.html        # Mobile Client UI & Frontend Logic
├── worker/
│   ├── package.json      # Dependencies (wrangler, typescript, workers-types)
│   ├── wrangler.toml     # Cloudflare deployment config (KV, Durable Object bindings)
│   └── src/
│       ├── index.ts      # Cloudflare Worker entry point (HTTP routing, static serving)
│       ├── relay.ts      # HTTP routing specific to the Durable Object
│       ├── session.ts    # Durable Object class (WebSocket Relay, State, Buffering)
│       ├── index_html.ts # Generated at deploy-time, contains inlined index.html
│       ├── phone_html.ts # Generated at deploy-time, contains inlined phone.html
│       └── sw_js.ts      # Generated at deploy-time, contains inlined Service Worker
```
*Note: The `webapp` HTML files are injected directly into the worker deployment script to avoid Cloudflare KV latency during initial page loads.*

## 3. Frontend Architecture (Vanilla JS)
Both `index.html` and `phone.html` use no external frontend frameworks (No React/Vue, no Tailwind). 

**Dependencies:**
- `phone.html` imports `html5-qrcode` from unpkg to handle mobile camera QR scanning.

**State Management:**
- Global `state` object (or `phoneState`) holds active WebSocket references, cryptographic keys, active transfer data, file arrays, and UI navigation indices.

**Styling / Aesthetics:**
- Pure vanilla CSS utilizing CSS Variables (`--surface`, `--surface-2`, `--border`, `--text`, `--mono`).
- Design language: Monospaced, dark-themed, "hacker/terminal" aesthetic. High contrast, sharp edges (border-radius: 0).

**Connection Resilience:**
- Session IDs are stored in `localStorage` (`doctransit_session_id`, `doctransit_session_expiry`).
- If the browser is refreshed or the phone goes to sleep, the frontend script (`createSession(false)`) attempts to resume the stored session before requesting a new one.

## 4. Backend Architecture (Cloudflare Workers + Durable Objects)
The backend acts strictly as a low-latency relay between the PC and the Phone. 

**Durable Objects (DO) & WebSocket Hibernation:**
- A single 12-character Session ID maps to a unique Durable Object instance.
- Both PC (`/pc`) and Phone (`/phone`) send HTTP Upgrade requests to establish WebSockets.
- The DO uses the **WebSocket Hibernation API** (`ctx.acceptWebSocket(server)` and `webSocketMessage(...)`). This allows the DO compute instance to sleep between messages, significantly reducing costs while keeping the TCP/WebSocket connection alive.

**Disconnect Logic (`webSocketClose`):**
- If one socket drops (e.g., page reload, network drop), the DO intentionally **does not** close the peer socket. This allows the disconnected client to natively reconnect to the same session ID. The session is only torn down if a peer explicitly sends a `{"type":"cancelled"}` message or the TTL expires.

**Security Constraints in DO:**
- Hard limit of 500MB per file transfer.
- Hard TTL limit of 5 minutes per session.

## 5. End-to-End Encryption (E2EE) Implementation
All data (files and chat messages) is encrypted client-side using the Web Crypto API.

1. **Key Derivation (HKDF):** 
   - The 12-character Session ID acts as the base secret.
   - Using `SHA-256`, salt `doctransit-v2`, and info `file-transfer`, it derives a 256-bit `AES-GCM` CryptoKey.
2. **Chunking & Encryption:**
   - Files are sliced into 512KB chunks.
   - A random 12-byte Initialization Vector (IV) is generated via `crypto.getRandomValues`.
   - The chunk is encrypted via `AES-GCM`.
   - The binary blob sent over WebSocket is structured as: `[12-byte IV] + [Ciphertext]`.
3. **Decryption:**
   - The receiving peer slices the first 12 bytes to extract the IV, then decrypts the remainder using the derived key.

## 6. Messaging Protocol & Data Flow

### A. Handshake Phase
1. **PC** requests a new session via HTTP `POST /init`. Worker returns a Session ID.
2. PC connects via WebSocket to `wss://.../pc?id=<SessionID>`.
3. **Phone** scans QR, connects via WebSocket to `wss://.../phone?id=<SessionID>`.
4. DO notifies PC: `{"type": "paired", "device": "phone"}`.

### B. File Transfer Flow (Chunked & Acknowledged)
1. Sender dispatches metadata: `{"type": "transfer_init", "filename": "...", "size": 1234, "total_chunks": 3}`.
2. Receiver allocates a buffer array and replies: `{"type": "ready"}`.
3. Sender encrypts Chunk 0 and transmits as a raw binary WebSocket frame.
4. DO relays the binary frame instantly to Receiver.
5. Receiver decrypts, pushes to array, and replies: `{"type": "ack", "chunk_index": 0}`.
6. Sender receives `ack`, updates UI progress bar, encrypts and transmits Chunk 1.
7. Upon completing the final chunk, Receiver creates a `Blob` URL and renders the file. Sender dispatches `{"type": "transfer_complete"}`.

### C. Text Messaging (Chat)
Text messages are handled identically to files to reuse the E2EE pipeline.
- When a user sends a text message, it is converted to a text `Blob`.
- It is transmitted as a standard file transfer with a hardcoded filename `message.txt` (and a size limit of < 50KB).
- The receiving client intercepts `message.txt`, reads it as text, and appends it to the Chat Modal UI (`appendChatMessage`) rather than treating it as a downloadable file.

## 7. iOS Shortcut Support (Headless Buffer Mode)
Because iOS Shortcuts cannot maintain long-lived WebSockets, the Worker has a specialized fallback.
- If the PC initiates a transfer and the DO detects no active Phone WebSocket, it enters **Shortcut Mode**.
- As the PC sends binary chunks, the DO buffers them in its persistent `ctx.storage` (capped at 100MB).
- The DO automatically replies with mock `ack` packets to the PC so the PC continues streaming.
- The iOS Shortcut makes sequential HTTP `GET /download_chunk?index=0` requests to the Worker. The Worker retrieves the chunks from DO storage, decrypts them server-side (only in this specific Shortcut mode), and returns the raw file data to iOS.

## 8. Development & Deployment Workflow
- The project uses `npm run deploy` inside the `worker/` directory.
- This script reads the raw HTML files from `webapp/`, injects them as exported string constants into `worker/src/index_html.ts`, etc., and executes `wrangler deploy`.
- Therefore, to apply frontend changes, you **must** run the worker deployment script. Local HTML file changes do not auto-sync unless deployed.
