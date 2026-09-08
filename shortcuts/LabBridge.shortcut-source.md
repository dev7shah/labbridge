# DocTransit iOS Shortcut

This document provides the exact sequence of actions to build the **DocTransit** shortcut in the iOS Shortcuts app.

## Actions in order:

1. **Text** — Set variable `WorkerURL`
   Value: `https://doctransit-worker.YOUR_SUBDOMAIN.workers.dev`
   *(User updates this once after adding the shortcut)*

2. **Scan QR Code** — Scan QR from PC screen
   Save result to variable `QRRaw`

3. **Get Dictionary from Input** — Parse `QRRaw` as JSON
   Save to variable `QRData`

4. **Get Dictionary Value** — Key: `s` from `QRData`
   Save to variable `SessionID`

5. **Get Dictionary Value** — Key: `e` from `QRData`
   Save to variable `ExpiryMs`

6. **Get Current Date** — Save to variable `Now`

7. **If** — `Now` (as Unix timestamp × 1000) > `ExpiryMs`
   - **Show Alert**: "QR code has expired. Please refresh the PC page."
   - **Stop and output**
   **Otherwise continue**

8. **URL** — `[WorkerURL]/session/[SessionID]/phone_connect`

9. **Get Contents of URL** — Method: POST
   Save result to variable `ConnectResult`

10. **Repeat** — 60 times *(covers ~2 minutes of polling)*

    a. **URL** — `[WorkerURL]/session/[SessionID]/poll`

    b. **Get Contents of URL** — Method: GET
       Save to variable `PollResult`

    c. **Get Dictionary from Input** — Parse `PollResult`
       Save to variable `PollData`

    d. **Get Dictionary Value** — Key: `status` from `PollData`
       Save to variable `Status`

    e. **If** `Status` = `file_ready`
       - Get Dictionary Value: `chunk_count` → `ChunkCount`
       - Get Dictionary Value: `filename` → `Filename`
       - Set variable `AllChunks` to empty list
       - **Repeat** `ChunkCount` times:
         - Get variable `Repeat Index` → `ChunkIndex` *(subtract 1 for 0-based index)*
         - **URL**: `[WorkerURL]/session/[SessionID]/chunk/[ChunkIndex]?decrypt=1`
           *(Note: `?decrypt=1` uses server-side HKDF/AES-GCM decryption — Option A helper)*
         - **Get Contents of URL** → `ChunkData`
         - **Add to Variable** `ChunkData` to `AllChunks`
       - **Combine Text/Files** `AllChunks` → `FileData`
       - **Set Name** of `FileData` to `Filename`
       - **Save File** `FileData` to Files app
         - Default location: `iCloud Drive / DocTransit`
         - Ask where to save: `YES`
       - **URL**: `[WorkerURL]/session/[SessionID]/phone_ack`
       - **Get Contents of URL** (Method: POST) — confirm receipt with PC
       - **Show Notification**: "✅ [Filename] saved to Files"
       - **Stop and output** (Exit Shortcut)

    f. **Wait** — 2 seconds

11. **Show Alert** — "No file received. Session may have expired."

---

## Notes on Encryption (Option A vs Option B)

- **Option A (`?decrypt=1` parameter or `/decrypt` endpoint — Recommended & Enabled)**:
  Because iOS Shortcuts does not support AES-256-GCM natively without external apps, appending `?decrypt=1` to the chunk download URL instructs the Cloudflare Worker DO to derive the session key via HKDF and decrypt the chunk right before sending it over HTTPS. The Worker is already trusted with routing the session.
- **Option B (Fully E2E Native)**:
  If a native Share Extension or local Swift helper app is installed on the iPhone, the Shortcut can omit `?decrypt=1`, download raw ciphertext chunks, and pass them locally to the helper for on-device decryption.
