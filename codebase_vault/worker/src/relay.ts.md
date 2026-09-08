# relay.ts

## Architecture Metrics
- **Path:** `worker/src/relay.ts`
- **Extension:** `.ts`
- **Size:** 1650 bytes
- **Centrality Score:** 0.0002
- **In-Degree (Imported By):** 2
- **Out-Degree (Imports):** 0

## Explanation
*No explanation provided in source code.*

## Structural Outline
- `generateSessionId`
- `getOtherSocket`
- `isValidSessionMessage`

## Imports (Dependencies)
*No internal imports*

## Imported By (Dependents)
- [[worker/src/index.ts.md|worker/src/index.ts]]
- [[worker/src/session.ts.md|worker/src/session.ts]]

## Source Code Snippet
```ts
/**
 * Relay helper utilities for the DocTransit worker.
 * Pure functions — no state, no side effects.
 */

/** Generate a 12-char alphanumeric session ID from a random UUID. */
export function generateSessionId(): string {
  return crypto.randomUUID().replace(/-/g, "").substring(0, 12);
}

/**
 * Given the full set of hibernatable WebSockets on the Durable Object,
 * return the socket that is NOT `currentWs`, i.e. the other peer.
 * Returns null if no other socket exists.
 */
export function getOtherSocket(
  sockets: WebSocket[],
  currentWs: WebSocket,
): WebSocket | null {
  const currentAtt = currentWs.deserializeAttachment() as { role?: string } | null;
...
```