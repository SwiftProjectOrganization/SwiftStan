# Loop Emission Plan

How SwiftStan handles a linear predictor that cannot ride Stan's native
vectorisation, in both the forward (`stancode`: alist/DSL → Stan) and reverse
(`stan2alist`: Stan → alist) directions.

## Background

A McElreath linear model lowers to a single deterministic/link assignment, e.g.

```r
logit(p) <- a + a_actor[actor] + a_block[block_id] + (bp + bpc*condition)*prosoc_left
```

Most such assignments vectorise — Stan overloads `+ - .* ./` element-wise, indexes a
vector by an integer array (`a_actor[actor]` gathers a length-`N` vector), and
vectorises the `~` operator natively. SwiftStan emits those as a single line.

Some shapes do **not** vectorise under SwiftStan's emitter and are written as a
per-row `for (i in 1:N) { ... }` loop instead (`BlockEmitter.classifyVectorisation`):

- `vector * vector` / `vector / vector` — Stan parses `*`/`/` as matrix
  multiply / dot product, not element-wise (`bpc*condition` once both are vectors).
- chained indexing `ab[cafe][k]` — vector-of-vectors element access (varying slopes
  under `multi_normal`).
- nested groupings `a[country, region]` — matrix lookup, per-row scalar.

## Forward emitted-loop grammar (the contract)

For each non-vectorising Link / Deterministic statement the emitter produces exactly
one loop, of exactly this shape (`BlockEmitter.swift`, `modelBlock` + `renderLoopBody`):

```stan
for (i in 1:N) {
  <lhs>[i] = inv_link( <body> );   // Link: wrapped in the inverse-link call
  // or, for a plain Deterministic:
  // <lhs>[i] = <body>;
}
```

Invariants the reverse parser may rely on:

- **One loop variable**, always `i`, always bound `1:N`.
- **Single-statement body** — exactly one assignment, `<lhs>[i] = <rhs>;`.
- `<body>` is the source RHS with every data vector and index column subscripted by
  `[i]`: `a_actor[actor]` → `a_actor[actor[i]]`, `condition` → `condition[i]`.
  Scalar parameters and literals appear verbatim. Operator precedence is preserved
  with parentheses.
- Link wrapping uses the same inverse-link names the vectorised path uses
  (`inv_logit`, `exp`, …), so de-wrapping is identical in both paths.

Anything outside this grammar (multi-statement bodies, `while`, nested loops,
non-`1:N` bounds, recursive/time-series or ragged-array models) is **out of scope**
and fails loud in both directions.

## Forward status

Complete. The emitter loop-emits the full McElreath example suite — chimpanzees
(`vector*vector`), cafe varying-slopes (`ab[cafe][k]`), nested groupings
(`a[country, region]`), monotonic effects, and SUR pairs — verified by the
`UlamGeneratorTests` goldens and the end-to-end artifact tests. The remaining
`BlockEmitterError.loopEmissionRequired` throws are correctness guards for genuinely
ill-typed models (indexing a *scalar* `Prior`, e.g. `a[group]` with no matching
`VaryingPrior`) and are expected to keep failing loud.

## Reverse path (`stan2alist`) — implemented

`StanBlockParser.rewriteContractLoops` (`:267`) inverts the forward grammar:

1. **Brace-aware extraction**: a brace-depth walk recognises the single-assignment
   contract loop (`for (i in 1:N) { lhs[i] = rhs; }`). Off-contract loops still throw
   `StanBlockParseError.unsupportedLoop`.
2. **De-subscript the body** — the inverse of `renderLoopBody`: drops `[i]` subscripts
   (`a_actor[actor[i]]` → `a_actor[actor]`, `condition[i]` → `condition`) and emits a
   normalised `.assignment(lhs, rhs)` — the same form the vectorised path produces. No
   new `StanProgram` case is needed.
3. Downstream is unchanged: `StanToUlamModel.reconstructAssignment` already inverts
   `inv_logit`/`exp`/`logit`, and `AlistTextEmitter` renders the result.

Chimpanzees now round-trips byte-identically through
`alist → stancode → stan2alist → stancode` and is part of the oracle.

### SUR two-statement loop (Family B)

The SUR model emits a two-statement loop (`for (n in 1:N) { row_vector[J] mu = rhs; y[n] ~ multi_normal(mu, Sigma); }`). `appendRewrittenSurLoop` (`:346`) handles this sibling shape: strips the `row_vector[J]` type prefix, keeps the RHS verbatim (BlockEmitter's `detectSurLoops` re-reads it), and strips `[n]` from the outcome. Family B (SUR/WaffleDivorce) round-trips byte-identically via the `Stan → StanProgram → [Statement] → stancode` oracle (see `MultivariateReverseMappingPlan.md`).

## Non-goals

- Lowering `vector * vector` to element-wise `.*` so loops are emitted less often:
  Stan can vectorise such terms, but switching the emitter would rewrite every golden
  and break the byte-identical round-trip contract.
- General loop bodies (recursive/time-series, ragged arrays, conditional per-row
  logic): these genuinely require Stan loops and stay fail-loud in both directions.
