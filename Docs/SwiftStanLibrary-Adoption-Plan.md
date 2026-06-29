# Plan: SwiftStan CLI depends on SwiftStanLibrary, DSL route stays alive

## Context

A parallel effort split SwiftStan's engine into a distributable SPM package,
**`SwiftStanLibrary`** (`~/Projects/Swift/SwiftStanLibrary/`, module name still
`SwiftStan`), consumed by `SwiftStanServer` over OpenAPI. That library is a copy
of the original `Sources/SwiftStan/` **minus `dsl2stan`** — the DSL route was
dropped because `dsl2stan` recompiles the package's own `Ulam/` source tree via
a `swiftc` subprocess (a hardcoded `SWIFTSTAN_PROJECT_ROOT`), which is not viable
in a distributed binary. The library is currently kept in sync with the original
by a brittle `rsync -a --delete` recipe (drift risk).

**Goal:** make the original `SwiftStan` package consume `SwiftStanLibrary` as a
dependency — a single source of truth that ends the rsync drift — **while
keeping the DSL route (`dsl2stan`) alive in the CLI only**. Per the design
decisions: the DSL route lives only in the CLI, and `dsl2stan` is rewritten so
the `.ulam.swift` driver does `import SwiftStan` and links the *resolved
SwiftStanLibrary build product* (dropping the hardcoded source-tree glob).

## Two hard problems (both verified against the code)

1. **Module-name collision.** Both packages vend a product+module named
   `SwiftStan`. The original package **cannot** keep a local target named
   `SwiftStan` and also depend on the external `SwiftStan` product → the local
   `SwiftStan` library target must be removed; `swiftstan-cli` imports the
   external one.
2. **`dsl2stan` moves outside the module.** Today it globs
   `Ulam/{AST,Builder,Data,Generator}/*.swift` from `SWIFTSTAN_PROJECT_ROOT` and
   compiles them alongside the driver so `internal` symbols resolve. The new
   approach links the *built library* instead. But the generated driver calls
   `stanScalars`/`stanInits` (currently `internal` in SwiftStanLibrary) and has
   no `import SwiftStan`; `AlistEmitter` (which generates drivers, in the
   library) emits no import either. And SPM emits **no standalone
   `libSwiftStan.a`** — it static-links the library's `.o` files into the
   executable — so there is no `-lSwiftStan` artifact to link against; only
   `.build/<cfg>/Modules/SwiftStan.swiftmodule` + `.build/<cfg>/SwiftStan.build/*.o`.

## Approach (recommended choices)

### A. Restructure `Package.swift` — local path dependency
`/Users/rob/Projects/Swift/SwiftStan/Package.swift`: drop the local `SwiftStan`
target and its `.library` product; vend only the `swiftstan` executable; add
`.package(path: "../SwiftStanLibrary")`. Use a **local path dependency** (not a
pinned remote URL) because this refactor must make symbols public in
SwiftStanLibrary — a remote pin would force re-tag/push/`swift package update`
on every visibility tweak. Keep the remote-URL line commented for the eventual
release switch.

After:
```swift
let package = Package(
  name: "SwiftStan",
  platforms: [ .macOS(.v14) ],
  products: [ .executable(name: "swiftstan", targets: ["swiftstan-cli"]) ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    .package(path: "../SwiftStanLibrary"),
    // Release: .package(url: ".../SwiftStanLibrary.git", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(name: "swiftstan-cli", dependencies: [
      .product(name: "SwiftStan", package: "SwiftStanLibrary"),
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ]),
    .testTarget(name: "SwiftStanCLITests", dependencies: [
      "swiftstan-cli", .product(name: "SwiftStan", package: "SwiftStanLibrary"),
    ], path: "Tests", resources: [.copy("TestDataFiles")]),
  ]
)
```

### B. Move `dsl2stan` into the executable target
Move `Sources/SwiftStan/Commands/Dsl2Stan.swift` →
`Sources/swiftstan-cli/Dsl2Stan.swift`; add `import SwiftStan`. It uses
`casePaths`/`ensureCaseDirectories` (already **public** ✅). `splitDriverOutput`
moves verbatim. The two sentinel strings it splits on are `internal` today —
make them public (see D) and reference `AlistEmitter.initsSentinel` /
`.scalarsSentinel` rather than hardcoding (avoids a drift bug with the emitter).

### C. New `swiftc` invocation — link the built module, derived from the binary's own path
Delete `resolveUlamSourceDir` / `dsl2stanGlob` / `SWIFTSTAN_PROJECT_ROOT`.
Replace with:
1. **Products dir** = `SWIFTSTAN_LIB_DIR` env override, else
   `URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
   .deletingLastPathComponent()`. (The running `swiftstan` binary sits in the
   build-products dir where `SwiftStan.swiftmodule` and the objects are
   siblings — covers both `.build/debug/` and Xcode DerivedData layouts.)
2. **Module dir** = probe `<dir>/Modules/SwiftStan.swiftmodule` (SPM) then
   `<dir>/SwiftStan.swiftmodule` (Xcode).
3. **Linkables** = probe `<dir>/libSwiftStan.{a,dylib}`; else glob
   `<dir>/SwiftStan.build/*.o`. If neither module nor linkables found, throw a
   new `Dsl2StanError.libraryArtifactNotFound(searchedDir:)` telling the user to
   `swift build` first or set `SWIFTSTAN_LIB_DIR` (fail loud, not an opaque
   swiftc error).
4. **swiftc args**: `-parse-as-library -O -module-name dsl2stan_driver -I <moduleDir>
   -L <productsDir> [<*.o> | -lSwiftStan] <driverPath> -o <tempBinary>`.

> Fragility note: the `*.o` glob depends on SPM's internal `SwiftStan.build/`
> layout. **Hardening recommendation:** have SwiftStanLibrary vend a
> statically-linkable product so a stable `libSwiftStan.a` exists, turning the
> link into a clean `-lSwiftStan`. Until then the `.o` glob + clear-error
> fallback is the pragmatic path. (A heavier but layout-independent alternative
> — generating a throwaway SwiftPM package that depends on SwiftStanLibrary and
> letting SPM build/link it — is the fallback if the `.o` layout proves
> unstable.)

### D. Make the driver self-contained against the public surface
Minimal coordinated edit in `SwiftStanLibrary` (justified DSL public surface):
- `Ulam/Data/ScalarMarshaller.swift` — `stanScalars(_:)` → `public`
- `Ulam/Data/InitMarshaller.swift` — `stanInits(_:)` → `public`
- `Ulam/Alist/AlistEmitter.swift` — `struct AlistEmitter` + `initsSentinel` +
  `scalarsSentinel` → `public`; and make `appendHeader` emit `import SwiftStan`
  so newly generated drivers are self-describing.

`UlamModel`, `UlamData`, `stancode(_:)`, and all DSL nodes are already public ✅.

For the **existing** committed `Examples/*_dsl/*.ulam.swift` (cafe, chimpanzees,
radon, radon_np) which lack the import: `dsl2stan` prepends `import SwiftStan\n`
in-memory before compiling **if absent** (`!source.contains("import SwiftStan")`)
— no mass file rewrite; a no-op once `alist2dsl` regenerates them.

### E. Test strategy
The 18 unit/integration tests using `@testable import SwiftStan` are **already
re-homed** in `SwiftStanLibraryTests` (and `@testable` cannot reach an external
binary dependency anyway). The CLI repo keeps only the DSL-route tests that the
library cannot cover — new `SwiftStanCLITests` target, **plain `import SwiftStan`**:
1. Port `Dsl2StanTests`: `smokeDriver → golden .stan` round-trip and
   missing-driver-throws. (If the golden derives from `SwiftStan.Ulam.bernoulliDemo()`,
   reach it via the `swiftstan-cli` test dependency, or inline the golden text.)
2. A link-path test exercising a cafe-shaped driver that calls
   `stanScalars`/`stanInits`, proving D's public promotion + the `.scalars.json`/
   `.init.json` side-files still emit.
3. Reuse existing `TestFixtureStaging.swift` + `TestCaseRootBootstrap.swift` and
   `resources: [.copy("TestDataFiles")]` (`Chimpanzees.ulam.swift` is already a
   staged fixture).

### F. Rsync recipe obsolete
The `rsync --delete` + delete-Dsl2Stan + re-apply-visibility recipe is
eliminated. After verification, the orphaned `Sources/SwiftStan/` tree in the
original repo should be deleted (only `Commands/Dsl2Stan.swift` is salvaged,
moving to `Sources/swiftstan-cli/`).

> Watch-out: the executable's `@main struct SwiftStan` shares its name with the
> imported module `SwiftStan`. Unqualified library calls (`dsl2stan(...)`,
> `stancode(...)`) are fine, but any `SwiftStan.`-qualified reference becomes
> ambiguous — check the CLI for these during the move.

## Critical files
- `/Users/rob/Projects/Swift/SwiftStan/Package.swift` (rewrite — A)
- `Sources/SwiftStan/Commands/Dsl2Stan.swift` → `Sources/swiftstan-cli/Dsl2Stan.swift` (move + rewrite — B, C, D)
- `Sources/swiftstan-cli/SwiftStan.swift` (check module-name shadowing — F)
- `~/Projects/Swift/SwiftStanLibrary/Sources/SwiftStan/Ulam/Data/ScalarMarshaller.swift`, `.../InitMarshaller.swift`, `.../Ulam/Alist/AlistEmitter.swift` (public surface — D)
- `Tests/` — replace `SwiftStanTests` with `SwiftStanCLITests` (E)

## Sequenced steps
1. **SwiftStanLibrary first** (CLI build depends on it): make `stanScalars`,
   `stanInits`, `AlistEmitter` + sentinels public; emit `import SwiftStan` in the
   driver header. `swift build` + `swift test` in `~/Projects/Swift/SwiftStanLibrary`.
2. Move + rewrite `Dsl2Stan.swift` into `swiftstan-cli` (C/D), add the
   `libraryArtifactNotFound` error and the import-prepend guard.
3. Rewrite the CLI `Package.swift` (A).
4. Replace the test target with `SwiftStanCLITests` (E).
5. After verification, delete the orphaned `Sources/SwiftStan/` tree (F).

## Verification
- `swift build` in `~/Projects/Swift/SwiftStanLibrary` (public symbols compile;
  existing `@testable` tests pass).
- `swift build` in `~/Projects/Swift/SwiftStan` (path dependency resolves, no
  module-name collision, `import SwiftStan` works).
- `swift test --filter Dsl2Stan` in the CLI repo.
- Real run: `swift run swiftstan dsl2stan --model cafe_dsl --verbose` (and
  `chimpanzees_dsl`) against `Examples/` — confirms it locates
  `.build/debug/Modules/SwiftStan.swiftmodule` + `SwiftStan.build/*.o`, compiles
  the driver, writes `Results/cafe_dsl.stan` (+ `.scalars.json`/`.init.json` for
  cafe). Run once with `SWIFTSTAN_LIB_DIR` unset, once set, to exercise both
  discovery paths.
- Negative: run `dsl2stan` against a clean (unbuilt) checkout → confirm
  `Dsl2StanError.libraryArtifactNotFound` fires with an actionable message.
