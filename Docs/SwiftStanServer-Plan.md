# Plan: SwiftStanServer (OpenAPI server) + SwiftStanApp (OpenAPI-client AppIntents)

## Context

`SwiftStanApp` (a macOS app at `~/Projects/Swift/SwiftStanApp/`) was meant to expose SwiftStan commands as App Intents by linking the `SwiftStan` library directly. In practice, **linking the local `SwiftStan` SwiftPM package into the Xcode app never worked** (the "Add Local Package" UI route is unreliable). So the real goal is twofold: (1) stand up a `SwiftStanServer` that owns all cmdstan execution and exposes SwiftStan commands over an HTTP API, and (2) make `SwiftStanApp` a thin OpenAPI **client** that no longer links any library directly — which removes the local-linking pain entirely.

The dependency problem was solved by creating **`SwiftStanLibrary`** (`~/Projects/Swift/SwiftStanLibrary/`), a proper distributable SPM library (see below) that the server depends on via a remote GitHub URL — reliable, no Xcode local-package UI involved.

## Final architecture

```
SwiftStanApp (client)              SwiftStanServer (Xcode app)           SwiftStanLibrary (SPM package)
 13 AppIntents                      Hummingbird HTTP server                published on GitHub
   └─ generated OpenAPI Client ──►  └─ generated APIProtocol impl ──►     13 public command functions
      URLSessionTransport (remote)     import SwiftStan ──────────────►   + Swift DSL (UlamModel, etc.)
   serverURL (http://127…:8080)        CMDSTAN / STAN_CASES on server      dependency-free, MIT licensed
```

**Three independently deployable projects, zero build coupling between them:**
- `SwiftStanLibrary` — the library; published to GitHub; no dependencies; module name `SwiftStan`.
- `SwiftStanServer` — links `SwiftStanLibrary` (remote URL); exposes 13 ops + health via Hummingbird/OpenAPI; non-sandboxed macOS Xcode app.
- `SwiftStanApp` — pure OpenAPI client; depends only on remote-URL OpenAPI packages; no link to `SwiftStanLibrary` or `SwiftStanServer`; the only runtime coupling is HTTP to the server.
- `SwiftStan` (original) — unchanged; keeps its CLI. Not a dependency of either app.

The **openapi.yaml** is the contract between server and client. The canonical copy lives in `SwiftStanServer/SwiftStanServer/OpenAPI/openapi.yaml`; a byte-identical copy lives in the SwiftStanApp target's source folder. Both generate their typed code (server-side `APIProtocol`, client-side `Client`) from this same spec.

## Why 13 ops (not 14)

`dsl2stan` is absent. It recompiles the package's own `Ulam/` source tree via `swiftc` — not viable in a distributed binary. `SwiftStanLibrary` dropped it; the in-process `stancode` covers alist→Stan without `swiftc`. Scope: `compile, sample, optimize, pathfinder, laplace, generated_quantities, stansummary, ulam, csv2json, alist2dsl, stancode, stan2alist, runinfo` (13) + `GET /v1/health`.

## SwiftStanLibrary (completed ✅)

Location: `~/Projects/Swift/SwiftStanLibrary/`  
GitHub: `https://github.com/SwiftProjectOrganization/SwiftStanLibrary`  
Add to Xcode via: File → Add Package Dependencies → the URL above; add product `SwiftStan`.

Key properties vs. original `SwiftStan`:
- Library-only (no CLI, no `swift-argument-parser`). Module name kept as `SwiftStan`.
- `dsl2stan` dropped; `caseRootOverride` demoted to `internal`; `Methods/`/`Helpers/`/support plumbing demoted to `internal`. Public surface: 75 declarations (was ~319).
- Idiomatic test layout: `Tests/SwiftStanLibraryTests/{Unit,Integration,Resources}`. Unit tests pass without cmdstan; integration tests env-gated on `$CMDSTAN`.
- MIT licensed; `.gitignore`; `CHANGELOG.md`.

Sync recipe (when upstream `SwiftStan` library changes):
```bash
rsync -a --delete ../SwiftStan/Sources/SwiftStan/ Sources/SwiftStan/
rm Sources/SwiftStan/Commands/Dsl2Stan.swift
# re-apply: caseRootOverride internal, Methods/Helpers/Support plumbing internal,
#           StanCodeGenerator internal, dsl2stan fallback removal in Ulam/Ulam.swift
swift build
```

## SwiftStanServer (to implement)

Location: `~/Projects/Swift/SwiftStanServer/` (Xcode app, source files already scaffolded).

Implementation steps:
1. **Create the Xcode project** (macOS App, SwiftUI, macOS 14, Swift 6) inside the existing dir.
2. **Add `SwiftStanLibrary`**: File → Add Package Dependencies → `https://github.com/SwiftProjectOrganization/SwiftStanLibrary`; add the `SwiftStan` product to the target.
3. **Add OpenAPI + Hummingbird packages** via remote URL: `swift-openapi-generator` (plugin), `swift-openapi-runtime`, `swift-openapi-hummingbird`, `hummingbird`.
4. **Wire the OpenAPI build plugin** (Build Phases → Run Build Tool Plug-ins → OpenAPIGenerator). The plugin reads `OpenAPI/openapi.yaml` + `openapi-generator-config.yaml` (server variant) and emits `APIProtocol`/`Types`.
5. **`StanAPIHandler.swift`** implements `APIProtocol` — 13 methods forwarding to `SwiftStan` library functions; synchronous blocking calls wrapped in `Task.detached` via `offload(_:)`.
6. **`ServerController.swift`** — Hummingbird `Application` lifecycle, binds to `127.0.0.1:<port>`, generous timeouts.
7. **Entitlements**: non-sandboxed + `network.server`; Hardened Runtime.

All scaffolded source files are already in place:
- `SwiftStanServer/StanAPIHandler.swift` — 13 ops + health (dsl2stan already removed)
- `SwiftStanServer/ServerController.swift`, `ServerSettings.swift`, `SwiftStanServerApp.swift`, `ContentView.swift`
- `SwiftStanServer/SwiftStanServer.entitlements`
- `SwiftStanServer/OpenAPI/openapi.yaml` — canonical 13-op spec (dsl2stan already removed)
- `SwiftStanServer/OpenAPI/openapi-generator-config.yaml`

## SwiftStanApp refactor (to implement)

Location: `~/Projects/Swift/SwiftStanApp/` (existing Xcode project).

The app currently links `SwiftStan` directly (broken — never worked) and has 5 intents. After the refactor it links nothing from the SwiftStan family and has 13 intents.

Steps:
1. **Remove** the `XCLocalSwiftPackageReference "../SwiftStan"` + `SwiftStan` product dependency from the project (done in Xcode UI); remove `import SwiftStan` from intent files.
2. **Add client OpenAPI packages** via remote URL: `swift-openapi-generator` (plugin), `swift-openapi-runtime`, `swift-openapi-urlsession`. Wire the plugin. Copy `openapi.yaml` into the app target source dir with a client `openapi-generator-config.yaml` (`generate: [types, client]`).
3. **Add** `StanClient.swift` (generated `Client` over `URLSessionTransport`, ~900 s timeout) and `ServerSettings.swift` (reads `@AppStorage("serverURL")`, default `http://127.0.0.1:8080`).
4. **Rewrite 5 intents + add 8 new ones** = 13 total. Each `perform()` calls `try await client.<op>(...)`, branches on `result.error`, surfaces failures via `StanIntentError`. New intents: `OptimizeModelIntent`, `PathfinderIntent`, `LaplaceIntent`, `GeneratedQuantitiesIntent`, `StansummaryIntent`, `Csv2JsonIntent`, `Alist2DslIntent`, `RuninfoIntent`.
5. **Update** `SwiftStanShortcuts` (8 new entries) and `ContentView` (replace cmdstan path field with `serverURL` field).
6. **Entitlements**: add `com.apple.security.network.client`; keep non-sandboxed initially.

## Verification

**Server:**
1. Build in Xcode; confirm plugin emitted `APIProtocol`/`Types` and handler compiles.
2. Run; `curl http://127.0.0.1:8080/v1/health` → JSON with cmdstan + StanCases.
3. `POST /v1/stancode {"model":"bernoulli"}` → `Wrote bernoulli.stan`; `POST /v1/compile` then `/v1/sample` → `error:""` and clean `bernoulli.samples.csv` on disk.

**Client:**
4. Build SwiftStanApp; confirm generated `Client` compiles and 13 intents reference it.
5. With server running, invoke "Compile Stan Model" and "Generate Stan Code" from Shortcuts; dialog shows server's `status`; failures surface via `StanIntentError`.
6. Run a `sample` with large `num_samples`; confirm 900 s client timeout holds.

## Open items
- Implement SwiftStanServer Xcode project (steps above).
- Implement SwiftStanApp refactor (steps above).
- Decide sandbox posture for SwiftStanApp once it stops shelling out.
- Hummingbird per-route timeout configuration for multi-minute calls (verify 2.x API).
