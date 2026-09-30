import { DurableObject } from "cloudflare:workers";

interface Env {
  CHANNELS: DurableObjectNamespace<Channel>;
}

interface SocketAttachment {
  role: "host" | "client";
}

interface ChannelMessage {
  t: number;
  body: string;
}

export class Channel extends DurableObject<Env> {
  private hostKeyHash: string | null = null;
  private clientKeyHash: string | null = null;
  private lastSeen: number = 0;
  
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.hostKeyHash = (await this.ctx.storage.get<string>("hostKeyHash")) ?? null;
      this.clientKeyHash = (await this.ctx.storage.get<string>("clientKeyHash")) ?? null;
      this.lastSeen = (await this.ctx.storage.get<number>("lastSeen")) ?? 0;
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    
    if (path === "/notify") {
      if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
      const key = url.searchParams.get("key");
      if (!key) return new Response("Missing key", { status: 400 });
      if (!await this.verifyHost(key)) return new Response("Forbidden", { status: 403 });
      
      const body = await request.text();
      if (body.length > 256 * 1024) return new Response("Payload too large", { status: 413 });
      
      await this.saveInboxMessage(body);
      this.broadcastToClients(body);
      
      return new Response("OK", { status: 200 });
    }
    
    if (path === "/ws") {
      const upgradeHeader = request.headers.get("Upgrade");
      if (!upgradeHeader || upgradeHeader !== "websocket") {
        return new Response("Expected Upgrade: websocket", { status: 426 });
      }

      const role = url.searchParams.get("role");
      const key = url.searchParams.get("key");
      if (!role || !key) return new Response("Missing role or key", { status: 400 });
      
      if (role === "host") {
        const ck = url.searchParams.get("ck");
        if (this.hostKeyHash === null) {
          if (!ck) return new Response("Missing ck for initial registration", { status: 400 });
          this.hostKeyHash = await this.hashKey(key);
          this.clientKeyHash = await this.hashKey(ck);
          await this.ctx.storage.put("hostKeyHash", this.hostKeyHash);
          await this.ctx.storage.put("clientKeyHash", this.clientKeyHash);
        } else {
          if (!await this.verifyHost(key)) return new Response("Forbidden", { status: 403 });
        }
      } else if (role === "client") {
        if (this.clientKeyHash === null) return new Response("Channel not initialized", { status: 400 });
        if (!await this.verifyClient(key)) return new Response("Forbidden", { status: 403 });
      } else {
        return new Response("Invalid role", { status: 400 });
      }

      const pair = new WebSocketPair();
      const [clientWs, serverWs] = [pair[0], pair[1]];
      serverWs.serializeAttachment({ role } satisfies SocketAttachment);
      this.ctx.acceptWebSocket(serverWs, [role]);

      if (role === "host") {
        // Disconnect old hosts
        for (const ws of this.ctx.getWebSockets("host")) {
          if (ws !== serverWs) {
            ws.close(1000, "Replaced by new connection");
          }
        }
        await this.updatePresence(true);
        // Set an alarm for 60 seconds to detect dead sockets
        await this.ctx.storage.setAlarm(Date.now() + 60 * 1000);
      } else {
        // Client connected: send current presence immediately
        serverWs.send(JSON.stringify({ type: "status", host: this.isHostOnline() ? "online" : "offline", lastSeen: this.lastSeen }));
        
        // Replay inbox if since is provided
        const since = url.searchParams.get("since");
        if (since) {
          const ts = parseInt(since, 10);
          if (!isNaN(ts)) {
            const inbox = await this.getInbox();
            for (const msg of inbox) {
              if (msg.t > ts) {
                serverWs.send(msg.body);
              }
            }
          }
        }
      }

      return new Response(null, { status: 101, webSocket: clientWs });
    }
    
    return new Response("Not found", { status: 404 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    if (typeof message !== "string") return;
    
    // Auto-respond to ping
    if (message === "ping") {
      ws.send("pong");
      const att = ws.deserializeAttachment() as SocketAttachment | null;
      if (att?.role === "host") {
        await this.updatePresence(true);
        await this.ctx.storage.setAlarm(Date.now() + 60 * 1000);
      }
      return;
    }
    
    const att = ws.deserializeAttachment() as SocketAttachment | null;
    if (!att) return;
    
    if (att.role === "host") {
      await this.updatePresence(true);
      await this.ctx.storage.setAlarm(Date.now() + 60 * 1000);
      
      // Host sending a message (e.g. reply to prompt)
      await this.saveInboxMessage(message);
      this.broadcastToClients(message);
    } else if (att.role === "client") {
      // Client sending a message (prompt)
      const hostSocket = this.getHostSocket();
      if (hostSocket) {
        hostSocket.send(message);
      } else {
        ws.send(JSON.stringify({ type: "error", msg: "host offline" }));
      }
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean) {
    const att = ws.deserializeAttachment() as SocketAttachment | null;
    if (att?.role === "host") {
      if (!this.getHostSocket()) {
        await this.updatePresence(false);
      }
    }
  }

  async webSocketError(ws: WebSocket, error: unknown) {
    const att = ws.deserializeAttachment() as SocketAttachment | null;
    if (att?.role === "host") {
      if (!this.getHostSocket()) {
        await this.updatePresence(false);
      }
    }
  }

  async alarm() {
    // 60s has passed since last host activity. 
    // This alarm is only set when host is active.
    // If no host socket is active, we mark offline.
    // Wait, the alarm might fire if the socket is alive but haven't sent a message/ping.
    // We expect the host to ping every 25s.
    // So if 60s passed without a ping, the host is offline.
    const now = Date.now();
    if (now - this.lastSeen >= 50 * 1000) {
      // Host is considered offline. Clean up sockets just in case they are ghost sockets.
      for (const ws of this.ctx.getWebSockets("host")) {
        ws.close(1000, "Ping timeout");
      }
      await this.updatePresence(false);
    } else {
      // Still active, but maybe we need to extend alarm if host is still connected
      if (this.getHostSocket()) {
         await this.ctx.storage.setAlarm(Date.now() + 60 * 1000);
      }
    }
  }

  private async hashKey(key: string): Promise<string> {
    const encoder = new TextEncoder();
    const data = encoder.encode(key);
    const hash = await crypto.subtle.digest("SHA-256", data);
    return Array.from(new Uint8Array(hash))
      .map(b => b.toString(16).padStart(2, "0"))
      .join("");
  }

  private async verifyHost(key: string): Promise<boolean> {
    if (!this.hostKeyHash) return false;
    const hash = await this.hashKey(key);
    return this.timingSafeEqual(hash, this.hostKeyHash);
  }

  private async verifyClient(key: string): Promise<boolean> {
    if (!this.clientKeyHash) return false;
    const hash = await this.hashKey(key);
    return this.timingSafeEqual(hash, this.clientKeyHash);
  }

  private timingSafeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    let mismatch = 0;
    for (let i = 0; i < a.length; i++) {
      mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return mismatch === 0;
  }

  private getHostSocket(): WebSocket | null {
    const sockets = this.ctx.getWebSockets("host");
    for (const ws of sockets) {
       if (ws.readyState === WebSocket.OPEN) return ws;
    }
    return null;
  }

  private isHostOnline(): boolean {
    return this.getHostSocket() !== null;
  }

  private async updatePresence(online: boolean) {
    if (online) {
      this.lastSeen = Date.now();
      await this.ctx.storage.put("lastSeen", this.lastSeen);
    }
    const statusMsg = JSON.stringify({ type: "status", host: online ? "online" : "offline", lastSeen: this.lastSeen });
    this.broadcastToClients(statusMsg);
  }

  private broadcastToClients(msg: string) {
    for (const ws of this.ctx.getWebSockets("client")) {
      ws.send(msg);
    }
  }

  private async saveInboxMessage(body: string) {
    const msg: ChannelMessage = { t: Date.now(), body };
    let inbox = await this.getInbox();
    inbox.push(msg);
    if (inbox.length > 50) {
      inbox = inbox.slice(inbox.length - 50);
    }
    await this.ctx.storage.put("inbox", inbox);
  }

  private async getInbox(): Promise<ChannelMessage[]> {
    return (await this.ctx.storage.get<ChannelMessage[]>("inbox")) ?? [];
  }
}
