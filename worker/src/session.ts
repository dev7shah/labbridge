import { DurableObject } from "cloudflare:workers";
import { getOtherSocket, isValidSessionMessage } from "./relay";

interface Env {
  SESSIONS: DurableObjectNamespace;
}

interface SocketAttachment {
  role: "pc" | "phone" | "peer";
}

interface PendingFile {
  filename: string;
  mimeType: string;
  totalChunks: number;
  size: number;
  receivedChunks: number;
  shortcutMode: boolean;
}

async function deriveAndDecrypt(sessionId: string, encryptedBuffer: ArrayBuffer): Promise<ArrayBuffer> {
  const enc = new TextEncoder();
  const baseKey = await crypto.subtle.importKey(
    "raw", enc.encode(sessionId), { name: "HKDF" }, false, ["deriveKey"]
  );
  const key = await crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: enc.encode("cueflex-v2"),
      info: enc.encode("file-transfer")
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["decrypt"]
  );
  const combined = new Uint8Array(encryptedBuffer);
  if (combined.byteLength < 12) {
    throw new Error("Encrypted buffer too short");
  }
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  return await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    ciphertext
  );
}

const SESSION_TTL_MS = 4 * 60 * 1000; // 4 minutes (240 seconds)
const MAX_SESSION_LIFETIME_MS = 60 * 60 * 1000; // 1 hour hard maximum limit
const MAX_FILE_SIZE_BYTES = 500 * 1024 * 1024; // 500MB max limit per transfer

/**
 * A single CueFlex relay session.
 *
 * Uses the WebSocket Hibernation API so the DO can sleep between
 * messages and only wake when data arrives or the alarm fires.
 */
export class Session extends DurableObject {
  private _createdAt: number | null = null;
  private _maxExpiresAt: number | null = null;
  private _bytesTransferred: number = 0;
  private _lastAlarmSet: number = 0;

  private async extendAlarm(durationMs = 4 * 60 * 1000): Promise<void> {
    if (!this._createdAt) {
      this._createdAt = await this.ctx.storage.get<number>("created_at") ?? null;
      if (!this._createdAt) {
        this._createdAt = Date.now();
        await this.ctx.storage.put("created_at", this._createdAt);
      }
    }
    this._maxExpiresAt = this._createdAt + MAX_SESSION_LIFETIME_MS;
    const now = Date.now();
    if (now >= this._maxExpiresAt) {
      return; // session is already past max lifetime, alarm() will clean up
    }
    const nextAlarm = Math.min(now + durationMs, this._maxExpiresAt);
    // Always set on first call after hibernation wake (_lastAlarmSet === 0),
    // otherwise debounce to avoid overwhelming DO storage writes
    if (this._lastAlarmSet === 0 || now - this._lastAlarmSet > 30_000) {
      await this.ctx.storage.setAlarm(nextAlarm);
      this._lastAlarmSet = now;
    }
  }

  /* ------------------------------------------------------------------ */
  /*  HTTP / WebSocket upgrade handler                                   */
  /* ------------------------------------------------------------------ */

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // ── Create a new session ──────────────────────────────────────────
    if (path === "/session/new") {
      // Extract session_id that was set by the edge worker
      const sessionId = url.searchParams.get("id") ?? "unknown";

      const now = Date.now();
      const expiryMs = now + SESSION_TTL_MS;
      const maxExpiryMs = now + MAX_SESSION_LIFETIME_MS;
      await this.ctx.storage.put("session_id", sessionId);
      await this.ctx.storage.put("created_at", now);
      await this.ctx.storage.put("max_expires_at", maxExpiryMs);
      await this.ctx.storage.setAlarm(expiryMs);

      const expiresAt = new Date(expiryMs).toISOString();
      const qrPayload = JSON.stringify({ s: sessionId, e: expiryMs });

      return Response.json({
        session_id: sessionId,
        qr_payload: qrPayload,
        expires_at: expiresAt,
      });
    }

    // ── Nearby / Active Waiting Sessions Discovery handler inside DO ──
    if (path === "/nearby") {
      const current = url.searchParams.get("current") || "";
      const previous = url.searchParams.get("previous") || "";
      const unregister = url.searchParams.get("unregister") || "";
      const ping = url.searchParams.get("ping") || "";
      const excludesStr = url.searchParams.get("excludes") || "";
      const excludes = excludesStr.split(",").map(s => s.trim()).filter(Boolean);
      const clientIp = url.searchParams.get("ip") || "";

      let nearbyMap = (await this.ctx.storage.get<Record<string, { ts: number; ip?: string }>>("nearby_map")) || {};
      const now = Date.now();

      // Clean up old entries older than 60 seconds (active waiting pool)
      for (const [id, val] of Object.entries(nearbyMap)) {
        if (!val || typeof val.ts !== 'number' || (now - val.ts > 60 * 1000)) {
          delete nearbyMap[id];
        }
      }

      // Unregister previous or specified session ID if provided
      if (previous && previous.length === 12) {
        delete nearbyMap[previous];
      }
      if (unregister && unregister.length === 12) {
        delete nearbyMap[unregister];
      }

      // Register pinged session ID
      if (ping && ping.length === 12 && ping !== "null" && ping !== "undefined") {
        nearbyMap[ping] = { ts: now, ip: clientIp };
      }

      await this.ctx.storage.put("nearby_map", nearbyMap);

      const excludeSet = new Set([current, previous, unregister, ...excludes].filter(Boolean));
      const devices = Object.entries(nearbyMap)
        .filter(([id]) => !excludeSet.has(id))
        .map(([id, val]) => ({
          session_id: id,
          age_seconds: Math.floor((now - val.ts) / 1000),
          is_same_ip: Boolean(clientIp && val.ip && val.ip === clientIp)
        }));

      return Response.json({ devices });
    }

    // ── WebSocket upgrade for /pc or /phone ──────────────────────────
    // ── GET /poll  (iPhone Shortcut polls for pending file) ───────────────
    if (path === "/poll") {
      const pending = await this.ctx.storage.get<PendingFile>("pending_file");
      if (!pending) {
        return Response.json({ status: "waiting" });
      }
      if (pending.receivedChunks < pending.totalChunks) {
        return Response.json({
          status: "receiving",
          received_chunks: pending.receivedChunks,
          total_chunks: pending.totalChunks,
        });
      }
      return Response.json({
        status: "file_ready",
        filename: pending.filename,
        size: pending.size,
        chunk_count: pending.totalChunks,
        mime_type: pending.mimeType,
      });
    }

    // ── GET /chunk/:index  (iPhone downloads one encrypted or decrypted chunk) ──
    const chunkPathMatch = path.match(/^\/chunk\/(\d+)$/);
    if (chunkPathMatch) {
      const chunkIndex = parseInt(chunkPathMatch[1], 10);
      const chunkKey = `chunk_${chunkIndex}`;
      const chunkData = await this.ctx.storage.get<ArrayBuffer>(chunkKey);
      if (!chunkData) {
        return new Response("Chunk not found", { status: 404 });
      }
      if (url.searchParams.get("decrypt") === "1" || url.searchParams.get("decrypt") === "true") {
        const sessionId = (await this.ctx.storage.get<string>("session_id")) ?? "unknown";
        try {
          const plaintext = await deriveAndDecrypt(sessionId, chunkData);
          return new Response(plaintext, {
            status: 200,
            headers: { "Content-Type": "application/octet-stream" },
          });
        } catch (err: any) {
          return new Response(`Decryption failed: ${err?.message ?? "unknown error"}`, { status: 500 });
        }
      }
      return new Response(chunkData, {
        status: 200,
        headers: { "Content-Type": "application/octet-stream" },
      });
    }

    // ── POST /phone_ack  (iPhone confirms all chunks received) ────────────
    if (path === "/phone_ack" && request.method === "POST") {
      const pending = await this.ctx.storage.get<PendingFile>("pending_file");
      if (pending) {
        const keysToDelete: string[] = ["pending_file"];
        for (let i = 0; i < pending.totalChunks; i++) {
          keysToDelete.push(`chunk_${i}`);
        }
        await this.ctx.storage.delete(keysToDelete);
      }

      const sockets = this.ctx.getWebSockets();
      for (const ws of sockets) {
        const att = ws.deserializeAttachment() as SocketAttachment | null;
        if (att?.role === "pc") {
          ws.send(JSON.stringify({ type: "shortcut_ack", message: "File received by iPhone" }));
        }
      }

      return Response.json({ status: "ok" });
    }

    // ── POST /phone_connect  (iPhone Shortcut first connect after QR scan) ──
    if (path === "/phone_connect" && request.method === "POST") {
      const sockets = this.ctx.getWebSockets();
      for (const ws of sockets) {
        const att = ws.deserializeAttachment() as SocketAttachment | null;
        if (att?.role === "pc") {
          ws.send(JSON.stringify({ type: "paired", device: "iPhone Shortcut", shortcut_mode: true }));
        }
      }
      const folders = (await this.ctx.storage.get<unknown[]>("folders")) ?? [];
      await this.ctx.storage.put("shortcut_mode", true);
      return Response.json({ status: "ok", folders });
    }

    // ── POST /decrypt  (Option A helper for iOS Shortcut) ────────────────
    if (path === "/decrypt" && request.method === "POST") {
      const sessionId = (await this.ctx.storage.get<string>("session_id")) ?? "unknown";
      const encryptedData = await request.arrayBuffer();
      try {
        const plaintext = await deriveAndDecrypt(sessionId, encryptedData);
        return new Response(plaintext, {
          status: 200,
          headers: { "Content-Type": "application/octet-stream" },
        });
      } catch (err: any) {
        return new Response(`Decryption failed: ${err?.message ?? "unknown error"}`, { status: 500 });
      }
    }

    // ── WebSocket upgrade for /pc, /phone, or /peer ─────────────────
    const roleMatch = path.match(/\/(pc|phone|peer)$/);
    if (!roleMatch) {
      return new Response("Not found", { status: 404 });
    }

    const role = roleMatch[1] as "pc" | "phone" | "peer";

    // Require Upgrade header
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("Expected WebSocket upgrade", { status: 426 });
    }

    // Enforce one-PC, one-phone policy: if reconnecting, replace existing socket
    const existing = this.ctx.getWebSockets();
    for (const ws of existing) {
      const att = ws.deserializeAttachment() as SocketAttachment | null;
      if (att && att.role === role) {
        try { ws.close(1000, "Replaced by new connection"); } catch (_) {}
      }
    }

    // Create the WebSocket pair
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];

    // Tag with role and accept via Hibernation API
    server.serializeAttachment({ role } satisfies SocketAttachment);
    this.ctx.acceptWebSocket(server);

    if (role === "phone" || role === "peer") {
      await this.ctx.storage.put("shortcut_mode", false);
    }

    // Send initial messages based on role
    if (role === "pc") {
      // Check if phone or peer is already connected
      const peerConnected = existing.some((ws) => {
        const att = ws.deserializeAttachment() as SocketAttachment | null;
        return att?.role === "phone" || att?.role === "peer";
      });

      if (peerConnected) {
        const peerAtt = existing.find((ws) => {
          const att = ws.deserializeAttachment() as SocketAttachment | null;
          return att?.role === "phone" || att?.role === "peer";
        });
        const peerRole = peerAtt ? (peerAtt.deserializeAttachment() as SocketAttachment)?.role : "phone";
        server.send(JSON.stringify({ type: "paired", device: peerRole === "peer" ? "PC (Peer)" : "phone" }));
      } else {
        server.send(JSON.stringify({ type: "waiting" }));
      }
    }

    if (role === "phone") {
      // Tell the phone to send its folder structure
      server.send(JSON.stringify({ type: "folder_request" }));

      // Notify the PC that a phone has paired
      for (const ws of existing) {
        const att = ws.deserializeAttachment() as SocketAttachment | null;
        if (att?.role === "pc") {
          ws.send(JSON.stringify({ type: "paired", device: "phone" }));
        }
      }
    }

    if (role === "peer") {
      // Peer is a second PC — notify host PC to show connection request modal
      for (const ws of existing) {
        const att = ws.deserializeAttachment() as SocketAttachment | null;
        if (att?.role === "pc") {
          ws.send(JSON.stringify({ type: "connection_request", device: "PC (Peer)" }));
        }
      }
      // Note: We do not send "paired" to the peer here.
      // The peer will remain waiting until the host PC accepts and sends "connection_accept".
    }

    // If both sides are now paired, reset/extend the session alarm to 240 seconds (4 minutes)
    const hasPc =
      role === "pc" ||
      existing.some((ws) => (ws.deserializeAttachment() as SocketAttachment | null)?.role === "pc");
    const hasPeer =
      role === "phone" || role === "peer" ||
      existing.some((ws) => {
        const att = ws.deserializeAttachment() as SocketAttachment | null;
        return att?.role === "phone" || att?.role === "peer";
      });

    if (hasPc && hasPeer) {
      await this.extendAlarm(4 * 60 * 1000);
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  /* ------------------------------------------------------------------ */
  /*  Hibernation API callbacks                                          */
  /* ------------------------------------------------------------------ */

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const sockets = this.ctx.getWebSockets();

      // Check if sender is PC and peer is not a WebSocket phone (i.e. iOS Shortcut polling mode)
      const senderAtt = ws.deserializeAttachment() as SocketAttachment | null;
      const isFromPc = senderAtt?.role === "pc";

      if (message instanceof ArrayBuffer) {
        const other = getOtherSocket(sockets, ws);
        // For binary frames, check session expiry using cached value
        if (!this._maxExpiresAt) {
          await this.extendAlarm(5 * 60 * 1000);
        }
        if (Date.now() >= (this._maxExpiresAt ?? 0)) {
          ws.close(1000, "Session expired (max lifetime reached)");
          other?.close(1000, "Session expired (max lifetime reached)");
          return;
        }
        this._bytesTransferred += message.byteLength;
        if (this._bytesTransferred > MAX_FILE_SIZE_BYTES) {
          ws.close(1008, "Transfer size exceeds 500MB limit");
          other?.close(1008, "Transfer size exceeds 500MB limit");
          return;
        }

        // Check if we are in shortcut buffering mode (ONLY when PC sends chunks to iOS Shortcut)
        const pending = await this.ctx.storage.get<PendingFile>("pending_file");
        if (isFromPc && pending?.shortcutMode) {
          // Reject chunks beyond the declared total
          if (pending.receivedChunks >= pending.totalChunks) {
            ws.send(JSON.stringify({ type: "error", message: "All chunks already received" }));
            return;
          }
          // Buffer this chunk in storage for the Shortcut to fetch
          const chunkIndex = pending.receivedChunks;
          await this.ctx.storage.put(`chunk_${chunkIndex}`, message);
          pending.receivedChunks++;
          await this.ctx.storage.put("pending_file", pending);

          // ACK each chunk back to PC so it keeps sending
          ws.send(JSON.stringify({ type: "ack", chunk_index: chunkIndex }));

          // Extend alarm every 10 chunks to reduce storage ops
          if (chunkIndex % 10 === 0) {
            await this.extendAlarm(4 * 60 * 1000);
          }
          return;
        }

        if (!other) {
          return;
        }

        // Normal relay mode — forward to other peer
        other.send(message);
        return;
      }

      // Text frames: extend alarm and validate
      await this.extendAlarm(5 * 60 * 1000);

      // Text frames: validate minimally, then forward
      try {
        const parsed: unknown = JSON.parse(message as string);
        if (!isValidSessionMessage(parsed)) {
          ws.send(JSON.stringify({ type: "error", message: "Invalid message format" }));
          return;
        }

        // Re-resolve the peer socket fresh for text messages
        // (after hibernation wake, the socket list may have changed)
        const other = getOtherSocket(this.ctx.getWebSockets(), ws);

        if (parsed.type === "transfer_init") {
          // Reset transfer caps when a new transfer starts
          this._bytesTransferred = 0;
          await this.ctx.storage.delete("pending_file");
          
          // Clear all buffered chunks from any previous transfer
          const keys = await this.ctx.storage.list({ prefix: "chunk_" });
          for (const key of keys.keys()) {
            await this.ctx.storage.delete(key);
          }
          const record = parsed as Record<string, unknown>;
          if (
            typeof record.size !== "number" ||
            typeof record.total_chunks !== "number" ||
            record.size < 0 ||
            record.total_chunks < 0
          ) {
            ws.send(JSON.stringify({ type: "error", message: "Invalid transfer size or chunk count" }));
            return;
          }
          if (record.size > MAX_FILE_SIZE_BYTES || record.total_chunks > Math.ceil(MAX_FILE_SIZE_BYTES / (512 * 1024))) {
            ws.close(1008, "Transfer size exceeds 500MB limit");
            other?.close(1008, "Transfer size exceeds 500MB limit");
            return;
          }

          const isShortcutMode = (await this.ctx.storage.get("shortcut_mode")) === true;

          if (isShortcutMode && isFromPc) {
            // Buffer mode is capped at 100MB to fit within Durable Object storage limits
            if ((record.size as number) > 100 * 1024 * 1024) {
              ws.send(JSON.stringify({ type: "error", message: "Shortcut buffer mode max file size is 100MB" }));
              return;
            }
            // Store transfer metadata — chunks will be stored as they arrive
            const pendingFile: PendingFile = {
              filename: String(record.filename ?? "file"),
              mimeType: String(record.mime_type ?? "application/octet-stream"),
              totalChunks: record.total_chunks as number,
              size: record.size as number,
              receivedChunks: 0,
              shortcutMode: true,
            };
            await this.ctx.storage.put("pending_file", pendingFile);
            await this.ctx.storage.put("bytes_transferred", 0);
            // Tell PC to start sending — shortcut will poll for completion
            ws.send(JSON.stringify({ type: "ready" }));
          } else {
            if (!other) {
              ws.send(JSON.stringify({ type: "error", message: "No peer connected" }));
              return;
            }
            // Normal WebSocket relay path — forward to peer
            await this.ctx.storage.put("bytes_transferred", 0);
            const cumulative = ((await this.ctx.storage.get<number>("cumulative_transferred")) ?? 0) + (record.size as number);
            if (cumulative > MAX_FILE_SIZE_BYTES * 4) {
              ws.close(1008, "Session cumulative transfer limit exceeded");
              other.close(1008, "Session cumulative transfer limit exceeded");
              return;
            }
            await this.ctx.storage.put("cumulative_transferred", cumulative);
            other.send(message);
          }
          return;
      }

      if (parsed.type === "folders") {
        const record = parsed as Record<string, unknown>;
        if (Array.isArray(record.folders)) {
          if (record.folders.length > 5000) {
            ws.close(1008, "Folders array too large");
            other?.close(1008, "Folders array too large");
            return;
          }
          await this.ctx.storage.put("folders", record.folders);
        }
      }

      if (!other) {
        ws.send(JSON.stringify({ type: "error", message: "No peer connected" }));
        return;
      }
      other.send(message);
    } catch {
      ws.send(JSON.stringify({ type: "error", message: "Invalid JSON" }));
    }
  }

  async webSocketClose(
    ws: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean,
  ): Promise<void> {
    // A socket closed due to page reload, sleep, or network drop.
    // Do NOT close the peer socket. Let the peer stay in the session
    // so this side can reconnect natively using the session ID.
    const sockets = this.ctx.getWebSockets();
    const other = getOtherSocket(sockets, ws);
    if (other) {
      try {
        // We can optionally notify the peer that the device temporarily disconnected,
        // but for resilience, we just let it wait.
        // other.send(JSON.stringify({ type: "peer_disconnected" }));
      } catch {
        // ignore
      }
    }
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    // On error, notify the peer socket before closing errored socket
    const sockets = this.ctx.getWebSockets();
    const other = getOtherSocket(sockets, ws);
    if (other && other.readyState === WebSocket.OPEN) {
      try {
        other.send(JSON.stringify({ type: "error", message: "Peer WebSocket encountered an error" }));
      } catch {}
    }
    for (const s of sockets) {
      if (s === ws) {
        try {
          s.close(1011, "WebSocket error");
        } catch {}
      }
    }
  }

  /* ------------------------------------------------------------------ */
  /*  Alarm: session TTL self-destruct                                   */
  /* ------------------------------------------------------------------ */

  async alarm(): Promise<void> {
    // Close all sockets
    const sockets = this.ctx.getWebSockets();
    for (const ws of sockets) {
      try {
        ws.close(1000, "Session expired");
      } catch {
        // Already closed — ignore
      }
    }

    // Wipe storage so the DO can be garbage-collected
    await this.ctx.storage.deleteAll();
  }
}
