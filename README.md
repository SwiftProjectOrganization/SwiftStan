# SwiftStan CLI
## Purpose

1. A macOS / Xcode / Swift CLI (Command Line Interface) wrapping Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/).

2. An experimental port of [McElreath](https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919)'s R implementation ulam() in [rethinking](https://github.com/rmcelreath/rethinking) to Swift.

3. As an "experiment within an experiment", and for me to further my understanding of the mapping back-and-forth between alternate ways of expressing Stan Language Programs, I asked Claude to plan and implement a reverse mapping from a .stan file to an .alist.r file. See sections 2.2 and 5.2 in Docs/UlamManual.md.

## Other SwiftStan CLI related repositories in the '*SwiftStan suite*'

Other components is the SwiftStan suite are: 
1. [SwiftStanApp](https://github.com/SwiftProjectOrganization/SwiftStanApp): A thin HTTP client of:
2. [SwiftStanServer](https://github.com/SwiftProjectOrganization/SwiftStanServer), an OpenAPI server that uses the
3. [SwiftStanLibrary](https://github.com/SwiftProjectOrganization/SwiftStanLibrary) to execute cmdstan commands.

The SwiftStanLibrary is derived from the [SwiftStan](https://github.com/SwiftProjectOrganization/SwiftStan) CLI.

SwiftStan CLI provides a second ulam pipeline implementation using an intermediate DSL that requires `swiftc`. As swiftc is not available on iOS platforms that functionality was dropped from the SwiftStanLibrary package and consequently from SwiftStanServer and SwiftStanApp.

The SwiftStanLibrary is available as a SPM package on Github.

## Documentation[](Docs/)

- [`Docs/UserGuide.md`](Docs/UserGuide.md) — Overview, supported functionality, setup and usage.
- [`Docs/UlamManual.md`](Docs/UlamManual.md) — Ulam pipeline manual (`stancode` → `csv2json` → `CMDSTAN`).
- [`Docs/DSLManual.md`](Docs/DSLManual.md) — Swiftc+DSL pipeline (`alist2dsl` → `dsl2stan` → `csv2json` → `CMDSTAN`).
- [`Docs/TODO.md`](Docs/TODO.md) — Future work items.
- [`CLAUDE.md`](CLAUDE.md) — Guidance for Claude.

As the last item indicates, the ulam port is being worked on using Claude.

---

# Example cases

The repository contains ready-to-run input files for several of the models used in the ulam and DSL manuals and also models from "Statistical Rethinking", typically ending  with `<name>_m[n]_[n]`, e.g. "milk_m5_7". Those can be found in the top-level `Examples/` directory. Each example is a self-contained case directory named after the model:

```
Examples/<name>/
├── Preliminaries/     the inputs (<name>.csv, <name>.alist.R, and for the DSL cases <Name>.ulam.swift)
└── Results/           empty — the pipeline writes its output here
```

Once SwiftStan has been installed (**see UserGuide.md**), to run the examples, copy the contents of the Examples directory into your `~/Documents/<STAN_CASES>/` root and run the pipeline against it. For example:

```bash
cd ~/Project/Swift/SwiftStan # Your path to SwiftStan
cp -Rf Examples/* ~/Documents/StanCases/ # Your <Stan_Cases> environment variable
swiftstan ulam --model howell_m4_4

```
---
