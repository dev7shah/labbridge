/**
 * CueFlex — Cloudflare Worker entry point.
 *
 * Pure relay: routes requests to Session Durable Objects,
 * stores nothing, knows nothing about users or files.
 */

import { generateSessionId } from "./relay";
import { INDEX_HTML } from "./index_html";
import { PHONE_HTML } from "./phone_html";
import { INSTALL_HTML } from "./install_html";
import { MANIFEST_JSON } from "./manifest_json";
import { SW_JS } from "./sw_js";
import { ICON_192_BASE64, ICON_512_BASE64 } from "./icon_png";
import { QR_MIN_JS } from "./qr_min_js";
import { JS_QR } from "./js_qr";
import { HTML5_QRCODE } from "./html5_qrcode";
import { FFLATE_MIN_JS } from "./fflate_min_js";
// Re-export the Durable Object class so wrangler can discover it
export { Session } from "./session";

interface Env {
  SESSIONS: DurableObjectNamespace;
  MAX_SESSION_MINUTES?: string;
  MAX_FILE_SIZE_MB?: string;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

const ipRequests = new Map<string, { count: number; resetAt: number }>();
let lastGcTime = 0;

function checkRateLimit(ip: string, limit: number, windowMs: number): boolean {
  const now = Date.now();

  // Periodic eviction of expired entries (throttled to max once per 10s)
  if (ipRequests.size > 1000 && now - lastGcTime > 10000) {
    lastGcTime = now;
    for (const [key, val] of ipRequests.entries()) {
      if (now > val.resetAt) ipRequests.delete(key);
    }
  }
  // Hard cap safeguard - delete oldest elements efficiently
  if (ipRequests.size > 10000) {
    let dropped = 0;
    for (const key of ipRequests.keys()) {
      ipRequests.delete(key);
      if (++dropped >= 2000) break;
    }
  }

  const record = ipRequests.get(ip);
  if (!record || now > record.resetAt) {
    ipRequests.set(ip, { count: 1, resetAt: now + windowMs });
    return true;
  }
  if (record.count >= limit) {
    return false;
  }
  record.count++;
  return true;
}

function corsResponse(body: string | null, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) {
    headers.set(k, v);
  }
  return new Response(body, { ...init, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return corsResponse(null, { status: 204 });
    }

    const url = new URL(request.url);
    const path = url.pathname;
    const ip = request.headers.get("CF-Connecting-IP") ?? "local/unknown";

    // ── Static Web & PWA Routes ───────────────────────────────────────
    if (request.method === "GET" || request.method === "HEAD") {
      const noCache = { "Cache-Control": "no-cache, no-store, must-revalidate" };
      if (path === "/" || path === "/index.html") {
        return corsResponse(INDEX_HTML, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", ...noCache } });
      }
      if (path === "/phone.html" || path === "/pwa") {
        return corsResponse(PHONE_HTML, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", ...noCache } });
      }
      if (path === "/install.html" || path === "/install") {
        return corsResponse(INSTALL_HTML, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", ...noCache } });
      }
      if (path === "/manifest.json") {
        return corsResponse(MANIFEST_JSON, { status: 200, headers: { "Content-Type": "application/json; charset=utf-8", ...noCache } });
      }
      if (path === "/sw.js") {
        return corsResponse(SW_JS, { status: 200, headers: { "Content-Type": "application/javascript; charset=utf-8", ...noCache } });
      }
      if (path === "/qr.min.js" || path === "/qrcode.min.js") {
        return corsResponse(QR_MIN_JS, { status: 200, headers: { "Content-Type": "application/javascript; charset=utf-8" } });
      }
      if (path === "/jsQR.min.js") {
        return corsResponse(JS_QR, { status: 200, headers: { "Content-Type": "application/javascript; charset=utf-8" } });
      }
      if (path === "/html5-qrcode.min.js") {
        return corsResponse(HTML5_QRCODE, { status: 200, headers: { "Content-Type": "application/javascript; charset=utf-8" } });
      }
      if (path === "/fflate.min.js") {
        return corsResponse(FFLATE_MIN_JS, { status: 200, headers: { "Content-Type": "application/javascript; charset=utf-8" } });
      }
      if (path === "/icon.png" || path === "/icon-192.png") {
        const bin = Uint8Array.from(atob(ICON_192_BASE64), c => c.charCodeAt(0));
        return new Response(bin, { status: 200, headers: { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" } });
      }
      if (path === "/icon-512.png" || path === "/logo.png") {
        const bin = Uint8Array.from(atob(ICON_512_BASE64), c => c.charCodeAt(0));
        return new Response(bin, { status: 200, headers: { "Content-Type": "image/png", "Access-Control-Allow-Origin": "*" } });
      }
      if (path === "/join" || path === "/join.html") {
        const noCache = { "Cache-Control": "no-cache, no-store, must-revalidate" };
        return corsResponse(INDEX_HTML, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", ...noCache } });
      }
    }

    // ── GET /session/new ──────────────────────────────────────────────
    if (path === "/session/new" && request.method === "GET") {
      if (!checkRateLimit(`new:${ip}`, 20, 60 * 1000)) {
        return corsResponse(JSON.stringify({ error: "Rate limit exceeded. Please try again later." }), {
          status: 429,
          headers: { "Content-Type": "application/json", "Retry-After": "60" },
        });
      }

      const previous = url.searchParams.get("previous") || "";
      const sessionId = generateSessionId();
      
      // Register session in global waiting DO and purge previous if any
      try {
        const globalDoId = env.SESSIONS.idFromName("global_waiting_sessions");
        const globalStub = env.SESSIONS.get(globalDoId);
        await globalStub.fetch(`https://fake/nearby?ping=${sessionId}&previous=${previous}&ip=${ip}`);
      } catch (e) {}

      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);

      // Forward to the DO, passing the session ID as a query param
      const doUrl = new URL(request.url);
      doUrl.searchParams.set("id", sessionId);
      const res = await stub.fetch(doUrl.toString());
      const body = await res.text();

      return corsResponse(body, {
        status: res.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── GET /nearby ───────────────────────────────────────────────────
    if (path === "/nearby" && request.method === "GET") {
      const globalDoId = env.SESSIONS.idFromName("global_waiting_sessions");
      const globalStub = env.SESSIONS.get(globalDoId);
      const reqUrl = new URL(request.url);
      reqUrl.searchParams.set("ip", ip);
      const res = await globalStub.fetch(reqUrl.toString());
      const body = await res.text();
      return corsResponse(body, {
        status: res.status,
        headers: { "Content-Type": "application/json", "Cache-Control": "no-cache" },
      });
    }

    // ── GET /session/:id/pc  or  /session/:id/phone  or  /session/:id/peer ──
    const wsMatch = path.match(/^\/session\/([a-zA-Z0-9]{12})\/(pc|phone|peer)$/);
    if (wsMatch && request.method === "GET") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        const [, , role] = wsMatch;
        if (role === "phone") {
          return corsResponse(PHONE_HTML, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } });
        }
        return corsResponse("Expected WebSocket upgrade", { status: 426 });
      }

      if (!checkRateLimit(`ws:${ip}`, 60, 60 * 1000)) {
        return corsResponse("Rate limit exceeded", { status: 429 });
      }

      const [, sessionId, role] = wsMatch;
      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);

      // Forward the upgrade request directly to the Durable Object
      const doUrl = new URL(request.url);
      doUrl.pathname = `/${role}`;
      const res = await stub.fetch(doUrl.toString(), request);

      if (res.status === 101) {
        return res;
      }
      const errBody = await res.text();
      return corsResponse(errBody, { status: res.status, headers: res.headers });
    }

    // ── GET /session/:id/poll  (iPhone Shortcut polls this) ──────────────
    const pollMatch = path.match(/^\/session\/([a-zA-Z0-9]{12})\/poll$/);
    if (pollMatch && request.method === "GET") {
      if (!checkRateLimit(`poll:${ip}`, 60, 60 * 1000)) {
        return corsResponse(JSON.stringify({ error: "Rate limit exceeded" }), {
          status: 429,
          headers: { "Content-Type": "application/json" },
        });
      }
      const [, sessionId] = pollMatch;
      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);
      const doUrl = new URL(request.url);
      doUrl.pathname = "/poll";
      doUrl.searchParams.set("id", sessionId);
      const res = await stub.fetch(doUrl.toString());
      const body = await res.text();
      return corsResponse(body, {
        status: res.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── GET /session/:id/chunk/:index  (iPhone downloads one chunk) ──────
    const chunkMatch = path.match(/^\/session\/([a-zA-Z0-9]{12})\/chunk\/(\d+)$/);
    if (chunkMatch && request.method === "GET") {
      if (!checkRateLimit(`chunk:${ip}`, 200, 60 * 1000)) {
        return corsResponse("Rate limit exceeded", { status: 429 });
      }
      const [, sessionId, chunkIndexStr] = chunkMatch;
      const chunkIndex = parseInt(chunkIndexStr, 10);
      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);
      const doUrl = new URL(request.url);
      doUrl.pathname = `/chunk/${chunkIndex}`;
      doUrl.searchParams.set("id", sessionId);
      const res = await stub.fetch(doUrl.toString());
      if (!res.ok) {
        return corsResponse(await res.text(), { status: res.status });
      }
      const buffer = await res.arrayBuffer();
      const headers = new Headers(CORS_HEADERS);
      headers.set("Content-Type", "application/octet-stream");
      headers.set("Content-Length", buffer.byteLength.toString());
      return new Response(buffer, { status: 200, headers });
    }

    // ── POST /session/:id/phone_ack  (iPhone confirms file received) ──────
    const ackMatch = path.match(/^\/session\/([a-zA-Z0-9]{12})\/phone_ack$/);
    if (ackMatch && request.method === "POST") {
      const [, sessionId] = ackMatch;
      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);
      const doUrl = new URL(request.url);
      doUrl.pathname = "/phone_ack";
      doUrl.searchParams.set("id", sessionId);
      const res = await stub.fetch(doUrl.toString(), {
        method: "POST",
        body: request.body,
        headers: request.headers,
      });
      return corsResponse(await res.text(), {
        status: res.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── POST /session/:id/phone_connect  (iPhone Shortcut first connect) ──
    const connectMatch = path.match(/^\/session\/([a-zA-Z0-9]{12})\/phone_connect$/);
    if (connectMatch && request.method === "POST") {
      const [, sessionId] = connectMatch;
      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);
      const doUrl = new URL(request.url);
      doUrl.pathname = "/phone_connect";
      doUrl.searchParams.set("id", sessionId);
      const res = await stub.fetch(doUrl.toString(), { method: "POST" });
      return corsResponse(await res.text(), {
        status: res.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── POST /session/:id/decrypt  (Option A helper for iOS Shortcut) ────
    const decryptMatch = path.match(/^\/session\/([a-zA-Z0-9]{12})\/decrypt$/);
    if (decryptMatch && request.method === "POST") {
      if (!checkRateLimit(`decrypt:${ip}`, 200, 60 * 1000)) {
        return corsResponse("Rate limit exceeded", { status: 429 });
      }
      const [, sessionId] = decryptMatch;
      const doId = env.SESSIONS.idFromName(sessionId);
      const stub = env.SESSIONS.get(doId);
      const doUrl = new URL(request.url);
      doUrl.pathname = "/decrypt";
      doUrl.searchParams.set("id", sessionId);
      const res = await stub.fetch(doUrl.toString(), {
        method: "POST",
        body: request.body,
        headers: request.headers,
      });
      if (!res.ok) {
        return corsResponse(await res.text(), { status: res.status });
      }
      const buffer = await res.arrayBuffer();
      const headers = new Headers(CORS_HEADERS);
      headers.set("Content-Type", "application/octet-stream");
      headers.set("Content-Length", buffer.byteLength.toString());
      return new Response(buffer, { status: 200, headers });
    }

    // ── Fallback ──────────────────────────────────────────────────────
    return corsResponse("Not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
