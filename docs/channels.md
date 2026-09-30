# Permanent Channels in DocTransit

Permanent Channels provide a persistent communication mode alongside the ephemeral 240-second file transfer sessions. They are designed for scenarios where you want a reliable, persistent link between a host (e.g., a PC) and a client (e.g., a mobile device) that reconnects automatically across network drops and app restarts.

## Architecture & Security

Permanent Channels operate over a Cloudflare Worker using the Durable Objects WebSocket Hibernation API. 

- **Security via E2E Encryption**: Messages are encrypted end-to-end using AES-256-GCM. The encryption key is derived using HKDF-SHA256 from a 256-bit `clientKey`. The server is entirely blind to the contents of the payload.
- **Zero Knowledge Auth**: The Worker authenticates the host and client using SHA-256 hashes of their respective keys (`hostKey` and `clientKey`). The plaintext keys never touch DO storage.
- **Offline Message Queuing**: If the client is offline, the Worker buffers the last 50 messages from the host. When the client reconnects, it retrieves these messages by supplying a `?since=<timestamp>` parameter.
- **Client Prompts**: If the host is active, clients can push prompt messages to the host in real-time. If the host is offline, the client receives an error, as the DO does not queue client-to-host messages.

## Watcher Script

A powerful feature of Permanent Channels is the ability to run daemon scripts on the host PC that push notifications to the paired client.

We have included a `tools/watcher.py` script that monitors a project directory for changes (`git diff`, `git status`, and an optional `.agent-summary.md` file). If the project is modified and then idle for 45 seconds, the script encrypts the change summary and pushes it to the client via the channel.

### Running the Watcher

1. Create a channel on your PC via the DocTransit web interface.
2. In the browser console (or localStorage), copy your `channelId`, `hostKey`, and `clientKey`.
3. Set them as environment variables:
   ```bash
   export DOCTRANSIT_CHANNEL_ID="your_channel_id"
   export DOCTRANSIT_HOST_KEY="your_host_key"
   export DOCTRANSIT_CLIENT_KEY="your_client_key"
   ```
4. Run the script:
   ```bash
   python3 tools/watcher.py
   ```

## Mobile App (Flutter)

The mobile app includes a dedicated **Channels** tab. When scanning a permanent channel QR code (`https://doctransit.in/c/<id>#<key>`), the app automatically stores the credentials securely and maintains a persistent WebSocket connection. Missing messages are fetched on reconnect, ensuring no updates from the watcher script are lost.
