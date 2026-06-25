# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SwiftStan is a Swift Package providing a macOS command-line tool (`swift-argument-parser`) that wraps Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) toolchain, plus a Swift port of McElreath's R `ulam()` DSL. macOS only; Swift 6.2; single dependency (`swift-argument-parser ≥ 1.2.0`).

The functionality can be used:

1. In Xcode: edit the scheme's "Arguments passed on launch", build-and-run, and watch the console.
2. From a shell (the intended way) via an alias `swiftstan` to `~/Library/Developer/Xcode/DerivedData/SwiftStan_*/Build/Products/Debug/SwiftStan`, or `swift run SwiftStan <subcommand>`.

## Build & test commands

```bash
# Build
swift build

# Run all tests
swift test

# Run a single test by name
swift test --filter "bernoulliMatchesGolden"

# Run a specific suite
swift test --filter "UlamGeneratorTests"
```

Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`). All test targets are in `Tests/SwiftStanTests/`. The `BuildProject` MCP tool builds the Xcode-resolved package directly.

From within Xcode: Product → Scheme → Edit Scheme → set "Arguments passed on launch" (e.g. `compile -V -I --model bernoulli`, `sample --model bernoulli`, `test`), then Build and Run.

From a shell (the primary workflow):

```bash
swiftstan compile --model bernoulli
swiftstan sample -V --model bernoulli num_samples=2000
swiftstan test  # runs the full cycle on Bernoulli
```

Required environment variable: `CMDSTAN` pointing to the cmdstan directory. `STAN_CASES` defaults to `StanCases` (under `~/Documents/`).

## Architecture

### Three-layer call structure

Each subcommand has the same three layers; navigate them in this order when changing behaviour:

1. **`Sources/SwiftStan/SwiftStan.swift`** — `@main struct SwiftStan: ParsableCommand` plus nested `extension SwiftStan { struct <Sub>: ParsableCommand }` types. Three shared `ParsableArguments` groups (`OptionsCompile`, `OptionsSample`, `OptionsLimited`) carry the flags/options. Each subcommand's `run()` reads `CMDSTAN`, resolves the path, and forwards to a top-level Swift function.
2. **`Sources/SwiftStan/Commands/*.swift`** — orchestration: resolve `casePaths(for: model)`, optionally install bootstrap files (`-I`), call the Methods layer (or shell out via `Process`), then post-process via Support.
3. **`Sources/SwiftStan/Methods/*.swift`** — thin wrappers (`stanCompile`, `stanSample`, `stanOptimize`, `stanPathfinder`, `stanSummary`) that build an argv and shell out via `swiftSyncFileExec`. Note: `stanSummary` lives in `Methods/RunStanSummary.swift` (not `StanSummary.swift`) to avoid an APFS case-insensitive `.o` collision with `Commands/Stansummary.swift`.

`SwiftStan.swift` repeats the `CMDSTAN`-resolution block in every `run()` rather than centralising it; if the fallback path needs to change, update all of them.

### `(String, String)` return convention

Almost every helper returns `(String, String)` — `.0` is a human-readable status line, `.1` is an error message (empty on success). This shows up everywhere — `compile`, `sample`, `swiftSyncFileExec`, `csvToDict`, etc. — and call sites consistently branch on `.1 == ""`, then `exit(N)` with distinct codes per failure point. Don't replace it with `throws` piecemeal; either keep it or refactor everything in one pass.

### Process execution

All shelling-out goes through `Support/SwiftSyncFileExec.swift`. It uses `Foundation.Process` synchronously with separate `stdout`/`stderr` pipes, reads both to EOF, and returns `(stdout-summary, stderr-or-empty)`. Exit codes are distinct per failure stage — see `Sample.swift` (exits 5–9) as the canonical pattern.

Callers that pass the optional `logsDir:` + `logsBase:` parameters (every cmdstan-method wrapper does) get a best-effort per-invocation log written to `<dir>/<base>.log` (stdout) and `<dir>/<base>.error.log` (stderr). Both files are always written (zero-byte = "ran but emitted nothing"), overwrite on each call, and any write failure is swallowed — log capture never breaks the return tuple.

### Filesystem layout

All commands read/write under `~/Documents/<STAN_CASES>/<name>/`:
- `Preliminaries/` — input: `<name>.csv`, `<name>.alist.R`, `<Name>.ulam.swift`
- `Results/` — output: `.stan`, `.data.json`, cmdstan binaries, chain CSVs, clean post-processed CSVs, plus `<name>.<method>.log` / `<name>.<method>.error.log` per cmdstan invocation (compile, sample, optimize, laplace, pathfinder, stansummary). Logs overwrite on each run — copy aside if a historical record is wanted.

### Output post-processing (raw vs clean)

cmdstan emits raw CSV (comment headers, one file per chain). The Support layer cleans it up following a uniform **`_raw` / `.clean`** filename convention:

| Method | Raw (from cmdstan) | Clean (post-processed) |
|---|---|---|
| sample | `<name>_output_[1..4].csv` | `<name>.samples.csv` |
| stansummary | `<name>_stansummary.csv` | `<name>.stansummary.csv` |
| optimize | `<name>_optimize.csv` | `<name>.optimize.csv` |
| pathfinder | `<name>_pathfinder.csv` | `<name>.pathfinder.csv` |
| laplace | `<name>_laplace.csv` | `<name>.laplace.csv` |

- `GetSampleResults.swift` collapses the four chain files into a single `<name>.samples.csv`.
- `ExtractStanSummary.swift` reads the raw stansummary CSV and writes a lower-cased-header version to `<name>.stansummary.csv` (also normalises cmdstan `nan` tokens via `replaceNanByNil`).
- `GetOptimizeResult.swift`, `GetPathfinderResult.swift`, `GetLaplaceResult.swift` each read raw and write a comment-stripped clean file alongside, leaving the raw intact.

The raw/clean split is load-bearing for `laplace`: cmdstan needs `<name>_optimize.csv` to carry the `# method = optimize` header as its `mode=` input. Overwriting it in place (as the old code did) destroyed that header.
- `ReplaceNanByNil.swift` handles cmdstan's literal `nan` tokens — Stan emits the literal string `nan` for undefined entries, which doesn't survive a normal CSV → JSON round-trip without intervention.
- `CsvToDict.swift` + `DictToJson.swift` are the building blocks for the `csv2json` subcommand: parse CSV (header-aware, configurable delimiter) into `[String: [Double]]`, then serialize.

### Bootstrap install (`-I` / `--install`)

`Helpers/CreateDotStanModelFile.swift` and `Helpers/CreateDotJsonDataFile.swift` write a bundled bernoulli example into the target `<name>/Results/` so a fresh checkout has something to compile and sample. `compile -I` installs `<name>.stan`; `sample -I` installs `<name>.data.json`. (`Helpers/` is distinct from `Support/` — the latter contains post-processing utilities.) The `test` subcommand drives the full cycle end-to-end on `~/Documents/StanCases/bernoulli/`.

### Subcommands

Defined in `SwiftStan.swift`:

- `compile` — uses `OptionsCompile` (`-V`, `-I`, `--cmdstan`, `--model`, trailing `values` passed through to make).
- `sample` — uses `OptionsSample` (adds `-S/--nosummary`). Defaults `num_chains=4 num_samples=1000` when no trailing args are passed. Always calls `getSampleResult` to produce the clean samples file, and by default also runs `stanSummary` + `extractStanSummary`.
- `optimize`, `pathfinder`, `laplace`, `stansummary`, `csv2json`, `dsl2stan`, `alist2dsl`, `stancode`, `stan2alist`, `runinfo` — all use `OptionsLimited` (no `-I` or `-S`); `stan2alist` adds a `-f/--force` flag.
- `laplace` — runs cmdstan's Laplace approximation. cmdstan requires an explicit `mode=<file>`; the orchestrator runs `stanOptimize` when `<name>_optimize.csv` is missing or doesn't carry the cmdstan `#` header (verified via a one-byte peek in `looksLikeRawOptimizeOutput`), then feeds the raw file via `mode=`. Trailing pass-through args (`stan laplace --model bernoulli draws=2000 mode=my_mode.csv`) work as for any other cmdstan subcommand.
- `csv2json` — reads `Preliminaries/<name>.csv` + `Results/<name>.stan`, writes `Results/<name>.data.json`. Validates every row-data variable declared in the `.stan` schema is present in the CSV; derives `N` and `N_<col>` cardinalities; fails loudly on `NA` (`Csv2JsonError.naValue` with column + row).
- `dsl2stan` — reads `Preliminaries/*.ulam.swift`, shells to `swiftc` to compile and run it, captures stdout into `Results/<name>.stan`. Locates the project source tree via `$SWIFTSTAN_PROJECT_ROOT` (defaults to `/Users/rob/Projects/Swift/SwiftStan`, with a printed notice when the default is used).
- `alist2dsl` — reads `Preliminaries/<name>.alist.R`, runs lexer → parser → lowering → classify → emitter (see **Ulam module** below), writes a runnable `@main` `<Name>.ulam.swift` to `Preliminaries/`. McElreath's "first `~` statement is the likelihood" convention drives role assignment; `dbinom(1, p)` collapses to `.bernoulli(p:)`; `σ` parameters that appear as the scale slot of a normal/cauchy/lognormal/gamma get `truncation: Truncation(lower: 0)` automatically (half-Cauchy / half-normal).
- `stancode` — in-process fast path. Same alist parser chain as `alist2dsl`, but the classified AST flows through `AlistToUlamModel.build(_:)` to a runtime `UlamModel`, then through the public `stancode(_: UlamModel) throws -> String` generator, written directly to `Results/<name>.stan`. No swiftc, no subprocess.
- `stan2alist` — the inverse of `stancode`. Reads `Results/<name>.stan` and writes a McElreath `alist()` to `Preliminaries/<name>.alist.R` via the reverse chain in `Ulam/Stan2Alist/`: `StanBlockParser` (line/block parser for the emitted-Stan subset → `StanProgram`) → `StanToUlamModel` (reverse of `AlistToUlamModel` + `DataInference`; role inference reads block structure — likelihood = `~` over a non-index data vector, varying prior = `~` over a vector param whose size symbol matches an index column's `upper` bound, scalar prior = `~` over a `real` param; inverts `inv_logit`/`exp`/`logit` wrappers to `Link`s) → `AlistTextEmitter` (`[Statement]` → alist text; renders `.bernoulli` as `dbinom(1, p)`). The Stan→`Distribution` reverse catalog (`distribution(fromStanName:args:)`, `mcElreathName(_:)`) lives in `Generator/DistributionCatalog.swift` next to the forward `name(_:)`/`args(_:)` so the tables can't drift. Deliberately lossy per scope: declaration `<lower>`/`<upper>` constraints are dropped (re-derived by `AlistClassify` on the forward pass), `<offset>`/`<multiplier>` affine non-centering is stripped to the centred form, and `generated quantities`/`transformed *` blocks are dropped with a stderr warning. `for`/`while` loops (non-vectorisable indexed RHS, e.g. chimpanzees' `vector * vector` term) and multivariate distributions fail loud. Refuses to overwrite an existing `.alist.R` without `--force`. Round-trip oracle: `alist → stancode → stan2alist → stancode` is byte-identical for vectorising models.
- `runinfo` — pure-Swift, no shell-out. Reads `Results/<name>.config.json` (`StanSample.swift` renames cmdstan's emitted `<name>_output_config.json` to this canonical name after each run) into a typed `RunInfo`, then rewrites the same file in place with `data.file`/`output.file` reduced to basenames, sorted keys, 2-space indent (no separate `.runinfo.json`). Two Swift API entry points: `readRunInfo(dirUrl:modelName:) throws -> RunInfo` (parse only) and `writeCleanRunInfo(dirUrl:modelName:) throws -> URL` (parse + clean-in-place). `MethodConfig` is a tagged-union enum (`.sample`/`.optimize`/`.laplace`/`.pathfinder`) discriminated on `method.value`; the `sample` case is fully typed, the other three currently decode into a `[String: JSONValue]` placeholder. The hand-rolled `RunInfoMarshaller` (mirrors `Ulam/Data/DataMarshaller.swift`) preserves clean Doubles. The Support file is `RunInfoIO.swift` (not `RunInfo.swift`) to avoid an APFS case-insensitive `.o` collision with `Commands/Runinfo.swift` — same pattern as `Methods/RunStanSummary.swift` vs `Commands/Stansummary.swift`.
- `ulam` (V2.1) — file-based pipeline driven by `ulamPipeline(model:cmdstan:verbose:arguments:)`. Picks the .stan-generation path by input presence: if `Preliminaries/<name>.alist.R` exists, use `stancode` (in-process, fast); otherwise fall back to `dsl2stan` against `Preliminaries/<Name>.ulam.swift`. Then `csv2json → compile → sample`, each step skipped when its outputs are newer than its inputs (`isStale(input:output:)`). The CLI lowercases `--model` for case-directory lookup.
- `test` (default subcommand) — drives `compile → sample → optimize → pathfinder` on `~/Documents/StanCases/bernoulli/`.

Trailing positional `<values>` are passed verbatim to cmdstan (`num_chains=4`, `save_iterations=true`, etc.) using cmdstan's `key=value` syntax.

### Ulam module (`Sources/SwiftStan/Ulam/`)

A Swift port of McElreath's R `ulam()` (from the `rethinking` package). Sits **above** the existing pipeline: emits a `<name>.stan` + `<name>.data.json` from a Swift result-builder DSL and hands off to the existing `compile` + `sample` machinery. alist2dsl ✅, stancode ✅, stan2alist ✅ (reverse).

Sub-packages:
- `AST/` — canonical AST types: `Statement` (`likelihood`/`prior` carry `truncation` and `useLpdf`; `varyingPrior` adds `indexedBy` and `countSymbol`; `vectorPrior` adds `length`), `Distribution` (catalog: `normal`, `bernoulli`, `binomial`, `beta`, `exponential`, `poisson`, `gamma`, `cauchy`, `lognormal`, `uniform`, `studentT`, `multivariateNormal`), `LinkFunction`, `Expression` (raw-string wrapper in v1), `Truncation` (optional `lower`/`upper` + `.none`), `UlamModel` (top-level value), `ExpressionNode`.
- `Builder/` — `@resultBuilder StanModelBuilder` and six DSL nodes: `Likelihood`, `Prior`, `VaryingPrior`, `VectorPrior`, `Link`, `Deterministic`. Initialisers carry defaulted `truncation:` and `useLpdf:`; `VaryingPrior` adds defaulted `countSymbol:` for overriding the auto-derived `N_<col>` cardinality variable; `VectorPrior` carries a `length:` cardinality symbol (for `vector[K] mu;`-style declarations under a `multi_normal` prior). All conform to `ModelStatement`.
- `Data/` — `UlamColumn` enum (`.real / .integer / .scalarReal / .scalarInt`) + `UlamData` typealias; `DataMarshaller` (hand-rolled JSON writer with clean Double formatting — emits `0.1` not `0.10000000000000001`; also emits `<countSymbol>: max(values)` for each Phase-5 index column).
- `Generator/` — `StanCodeGenerator` (public `stancode(_:) throws -> String`; `assemble(inferred:statements:)` prepends the traceability header), `BlockEmitter` (writes `data`/`parameters`/`model` blocks; routes through `vectorisationStrategy(...)` — canonical `a[group]` over known vector parameters + index columns vectorises, everything else throws `BlockEmitterError.loopEmissionRequired`), `DataInference` (classifies symbols as data/parameter/derived, computes `N`, infers parameter constraints from prior truncations, records outcome bounds; tracks `vectorParameters` and `indexColumns` from `varyingPrior` cases), `DistributionCatalog` (R→Stan name + arg-order mapping, `isDiscrete` for `_lpmf`/`_lpdf`, `renderTruncation`, `renderConstraint`, `outcomeBounds`; also hosts the reverse Stan→`Distribution` catalog), recursive-descent `ExpressionParser`/`ExpressionLexer`.
- `Alist/` — R `alist()` parser → two downstream targets. `AlistAST.swift` + `AlistLexer.swift` (R tokens incl. `~`, `<-`, `#` comments) + `AlistParser.swift` (outer-wrap stripping for `m12.5 <- map2stan(alist(...), ...)`, comma-split statements, reuses `ExpressionParser`). `AlistLowering.swift` maps R `d*` names to `Distribution` cases, expands `c(a, b, c) ~ ...` group priors, collapses `dbinom(1, p)` → `.bernoulli(p:)`. `AlistClassify.swift` assigns identifier roles using McElreath's "first `~` is the likelihood" convention and infers `lower: 0` truncation for scale-slot scalar parameters. Two emitters: `AlistEmitter.swift` renders a runnable `@main` Swift smoke driver (input for `dsl2stan`); `AlistToUlamModel.swift` builds an in-memory `UlamModel` (input for `stancode`).
- `Stan2Alist/` — the reverse pipeline (`stan2alist`; plan in `Docs/Stan2AlistCommandPlan.md`). `StanProgram.swift` (value types + `StanBlockParseError`) + `StanBlockParser.swift` (brace-depth block splitter, comment stripper, declaration + sampling/assignment parsers; skips model-block local declarations; records `transformed *`/`generated quantities`/`functions` as `droppedBlocks`; fails loud on unrecognised blocks/statements and on `for`/`while` loops). `StanToUlamModel.swift` reconstructs `[Statement]` (role inference off block structure; drops declaration constraints + affine non-centering; surfaces dropped blocks as warnings; orders likelihood → links → priors). `AlistTextEmitter.swift` renders `[Statement]` as McElreath `alist()` text (reuses `DistributionCatalog.args(_:)`).
- `Ulam.swift` — two orchestrators. `ulam(_ model: UlamModel, name:cmdstan:verbose:arguments:)` is the V1 in-process path used by the demo tests. `ulamPipeline(model: String, cmdstan:verbose:arguments:)` is the V2.1 file-based path the CLI uses — chains `stancode`-or-`dsl2stan` → `csv2json` → `compile` → `sample` with make-style staleness checks per step.

Two `stancode` entry points exist on the Swift API: `stancode(_ model: UlamModel) throws -> String` (pure) and `stancode(model: String, verbose: Bool) throws -> URL` (file-based). The `model:` label disambiguates.

DSL example:

```swift
let model = UlamModel(data: ["y": .integer(...), "x": .real(...)]) {
  Likelihood("y", .bernoulli(p: "p"))
  Link(.logit, lhs: "p", rhs: "a + b*x")
  Prior("a", .normal(0, 1.5))
  Prior("b", .normal(0, 0.5))
}
```

### Tests & fixture staging

Tests live in `Tests/SwiftStanTests/`; they use Swift Testing (`@Suite` + `@Test` + `#require`/`#expect`), not XCTest. Run a single one with `swift test --filter "<name>"`.

A whole-suite invocation (`swift test`) writes all artifacts into a sibling **`~/Documents/<STAN_CASES>_Test/`** dir, not the production `<STAN_CASES>/`. The redirect is wired by `Tests/SwiftStanTests/TestCaseRootBootstrap.swift`: every `@Suite` struct's `init()` references `TestCaseRootBootstrap.install`, which sets `caseRootOverride` (declared in `Sources/SwiftStan/Support/CasePaths.swift`) exactly once at first access. From that point on, every `casePaths(for:)` call resolves under `<STAN_CASES>_Test/`. Production binaries never touch `caseRootOverride` — it stays nil through the CLI's entire lifetime.

The contract: `swift test` must succeed against an **empty** `~/Documents/<STAN_CASES>_Test/` directory. Pipeline tests that need a hand-authored fixture (e.g. `howell.csv`, `chimpanzees.csv`, `Chimpanzees.ulam.swift`) **must** stage that fixture themselves before any `#require(fileExists:)`. Don't rely on test ordering — Swift Testing parallelises, and the first run from a fresh checkout is the canonical "does this work?" case. `StanCases_Test/` is left populated across runs so cmdstan binaries survive (make-style staleness checks skip the rebuild); wipe with `rm -rf ~/Documents/StanCases_Test` to exercise the empty-state contract.

When adding a new `@Suite` struct, add `init() { _ = TestCaseRootBootstrap.install }` as the first member — without it the suite runs against the user's production `<STAN_CASES>/` instead.

Fixture-staging pattern:

1. Bundle the fixture under `Tests/SwiftStanTests/TestDataFiles/` and declare it in `Package.swift` (`resources: [.copy("TestDataFiles")]` is already set).
2. Call `stageBundledFixture(named:to:)` from `Tests/SwiftStanTests/TestFixtureStaging.swift` — it copies via `Bundle.module` and overwrites stale destinations.
3. If the test also needs derived artifacts (a compiled binary, a generated `.stan`), bootstrap them after staging: call `stancode(model:)` / `stanCompile(...)` / `createDotStanModelFile(model:)` / `createDotJsonDataFile(model:)` directly. `LaplaceTests.bernoulliLaplaceProducesOutputCsv` is the canonical example.
4. Keep the `#require(fileExists:)` checks downstream of staging — they then act as belt-and-braces for the staging itself.

### Sibling project

[SwiftStats](https://github.com/SwiftProjectOrganization/SwiftStats) consumes the clean `*.samples.csv` / `*.stansummary.csv` files this CLI produces. The `~/Documents/<STAN_CASES>/<name>/Results/` layout is the contract between the two — don't rename output files without updating both.

## Argument quirks

- `--directory <directory>` is **relative to `~/Documents`**, not the working directory. There's no way to point at an absolute path without editing the source.
- Trailing positional `<values>` are passed through verbatim to cmdstan (`num_chains=4`, `save_iterations=true`, etc.), so they follow cmdstan's `key=value` syntax, not Swift-argument-parser's.
- `-V/--verbose` is wired everywhere but its semantics are inconsistent — sometimes it prints the make/cmdstan invocation, sometimes a status `(String, String)` tuple.
- `--version` and `-V` collide in spirit (top-level declares `version: "1.0.0"`, individual subcommands have `-V` as `--verbose`). The top-level `--version` flag works because subcommands don't reach it.

## Key constraints

- macOS only (`Process`, `/usr/bin/make`, `~/Documents`-rooted paths, `FileManager.urls(for: .documentDirectory, in: .userDomainMask)`).
- Swift 6.2+ toolchain (`Package.swift` declares `swift-tools-version: 6.2`).
- Single dependency: `swift-argument-parser` ≥ 1.2.0. Do not pull in additional packages without a clear reason — the CLI's value proposition is "thin wrapper".
- Prefer `async`/`await` over Combine for any new asynchronous code. The current shell-out path is intentionally synchronous (`Process.run()` + read-to-EOF) because the CLI is short-lived; if you make it async, propagate that everywhere rather than mixing styles.

## Code style

- **2-space indentation** throughout (not 4). Match existing files.
- Force-unwraps on `URL.appendingPathComponent` are deliberate — that API returns optional, but inputs are always non-empty, so the unwrap is safe in context.
- `CMDSTAN` resolution is duplicated in every `run()` rather than centralised — update all of them if the fallback path changes.

## Ruleset

Leave this section and these rules in CLAUDE.md and use them as overall guidance.

1. **Think Before Coding**: No silent assumptions. Push back if a simpler approach exists.
2. **Simplicity First**: Minimum code required. No speculative features.
3. **Surgical Changes**: Touch only what you must. Do not "improve" adjacent formatting.
4. **Goal-Driven Execution**: Define success criteria and loop until verified, rather than blindly following rigid steps.
5. **Hard Token Budgets**.
6. **Read Before You Write**.
7. **Checkpoint Multi-Step Operations**.
8. **Fail Loud**.
9. **Commit to the main branch or ask first**.
