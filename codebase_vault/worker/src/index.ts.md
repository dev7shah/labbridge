# index.ts

## Architecture Metrics
- **Path:** `worker/src/index.ts`
- **Extension:** `.ts`
- **Size:** 12383 bytes
- **Centrality Score:** 0.0002
- **In-Degree (Imported By):** 1
- **Out-Degree (Imports):** 12

## Explanation
*No explanation provided in source code.*

## Structural Outline
- `checkRateLimit`
- `corsResponse`

## Imports (Dependencies)
- [[worker/src/fflate_min_js.ts.md|worker/src/fflate_min_js.ts]]
- [[worker/src/html5_qrcode.ts.md|worker/src/html5_qrcode.ts]]
- [[worker/src/icon_png.ts.md|worker/src/icon_png.ts]]
- [[worker/src/index_html.ts.md|worker/src/index_html.ts]]
- [[worker/src/install_html.ts.md|worker/src/install_html.ts]]
- [[worker/src/js_qr.ts.md|worker/src/js_qr.ts]]
- [[worker/src/manifest_json.ts.md|worker/src/manifest_json.ts]]
- [[worker/src/phone_html.ts.md|worker/src/phone_html.ts]]
- [[worker/src/qr_min_js.ts.md|worker/src/qr_min_js.ts]]
- [[worker/src/relay.ts.md|worker/src/relay.ts]]
- [[worker/src/session.ts.md|worker/src/session.ts]]
- [[worker/src/sw_js.ts.md|worker/src/sw_js.ts]]

## Imported By (Dependents)
- [[worker/worker-configuration.d.ts.md|worker/worker-configuration.d.ts]]

## Source Code Snippet
```ts
/**
 * DocTransit — Cloudflare Worker entry point.
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
...
```