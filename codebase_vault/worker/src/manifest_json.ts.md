# manifest_json.ts

## Architecture Metrics
- **Path:** `worker/src/manifest_json.ts`
- **Extension:** `.ts`
- **Size:** 425 bytes
- **Centrality Score:** 0.0001
- **In-Degree (Imported By):** 1
- **Out-Degree (Imports):** 0

## Explanation
*No explanation provided in source code.*

## Structural Outline
*No major classes or functions detected.*

## Imports (Dependencies)
*No internal imports*

## Imported By (Dependents)
- [[worker/src/index.ts.md|worker/src/index.ts]]

## Source Code Snippet
```ts
export const MANIFEST_JSON = "{\n  \"name\": \"DocTransit\",\n  \"short_name\": \"DocTransit\",\n  \"start_url\": \"/phone.html\",\n  \"display\": \"standalone\",\n  \"background_color\": \"#000000\",\n  \"theme_color\": \"#000000\",\n  \"icons\": [\n    { \"src\": \"icon-192.png\", \"sizes\": \"192x192\", \"type\": \"image/png\" },\n    { \"src\": \"icon-512.png\", \"sizes\": \"512x512\", \"type\": \"image/png\" }\n  ]\n}\n";
```