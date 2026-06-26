# Multivariate Reverse-Mapping Plan

Extends `stan2alist` (the reverse pipeline, see `Docs/Stan2AlistCommandPlan.md`)
to handle the two multivariate model families the **forward** pipeline already
emits but the reverse currently rejects:

| Family | Canonical model | Forward AST | Stan shape |
|---|---|---|---|
| **A — correlated varying effects** | McElreath `cafe` (varying slopes) | `varyingVectorPrior` + `lkjCorrCholeskyPrior` + `vectorPrior` | `array[N_g] vector[K]`, `cholesky_factor_corr[K]`, `multi_normal_cholesky`, `lkj_corr_cholesky` |
| **B — SUR / multi-outcome** | `WaffleDivorce` (2-outcome) | SUR `deterministic` + `multivariateNormal` likelihood + `matrixPrior` + `covMatrixPrior` (and `wishartPrior`) | `matrix[r,c]`, `cov_matrix[K]`, per-row `multi_normal` loop, `wishart` |

Both are in scope; they reverse through **two distinct recognizers** but share
the catalog + declaration-parsing extensions.

## 1. Success oracle (the hard gate)

**stancode round-trip, byte-identical.** For every multivariate fixture:

```
.stan  ──StanBlockParser──▶  StanProgram
       ──StanToUlamModel──▶  [Statement]
       ──stancode────────▶   .stan'           (must equal the original .stan)
```

The reverse reconstructs the *same `[Statement]` list the forward built*, so the
existing forward goldens are the truth. This sidesteps the lossy alist-text
ambiguity: the combined `ab` parameter cannot recover McElreath's component
names `a_cafe`/`b_cafe`, and `diag_pre_multiply(sigma, L)` cannot recover whether
the source was `dmvnorm2` or `dmvnormchol`. Those losses are invisible at the
Stan level because the forward emitter renders multivariate distribution
**args verbatim** from `.expression` `DistributionArg`s.

**alist text is best-effort/secondary** — emitted so `stan2alist` still writes a
readable `.alist.R`, but its byte-form is not a gate (consistent with
`Stan2AlistCommandPlan.md` §1, the existing two-tier criterion).

### Why the verbatim-args property makes Family A trivial at the Stan level

Forward `DistributionCatalog.args(_:)` renders
`.multivariateNormalCholesky(mean, chol)` as `"\(arg(mean)), \(arg(chol))"`, and
`arg(.expression(s))` is `s` verbatim. So the original line

```stan
ab ~ multi_normal_cholesky([a_bar, b_bar]', diag_pre_multiply(sigma_ab, L_Omega));
```

round-trips if the reverse simply captures the two arg source-slices as
`.expression(...)` and rebuilds `.multivariateNormalCholesky`. No decomposition
of `diag_pre_multiply` / `[a,b]'` is needed for the oracle — only for the
best-effort alist text (§6).

## 2. Reference forward output (the round-trip targets)

These are existing forward goldens — the reverse must reproduce them exactly.

**Family A** — `UlamGeneratorTests.varyingVectorChainedIndexMatchesGolden`
(`Tests/SwiftStanTests/UlamGeneratorTests.swift:1176`):

```stan
parameters {
  real a_bar;
  real b_bar;
  real<lower=0> sigma;
  vector<lower=0>[J] sigma_ab;
  cholesky_factor_corr[J] L_Omega;
  array[N_cafe] vector[J] ab;
}
model {
  vector[N] mu;
  for (i in 1:N) {
    mu[i] = ab[cafe[i]][1] + ab[cafe[i]][2]*afternoon[i];
  }
  ...
  sigma_ab ~ exponential(1) T[0, ];
  L_Omega ~ lkj_corr_cholesky(2);
  ab ~ multi_normal_cholesky([a_bar, b_bar]', diag_pre_multiply(sigma_ab, L_Omega));
  wait ~ normal(mu, sigma);
}
```

**Family B** — `UlamGeneratorTests.surWaffleDivorceShapeMatchesGolden`
(`Tests/SwiftStanTests/UlamGeneratorTests.swift:1234`; read the full `expected`
string before implementing). Shape:

```stan
data { matrix[N, 2] x; matrix[N, 2] y; int J; int K; }
parameters { matrix[K, J] beta; cov_matrix[J] Sigma; }
model {
  to_vector(beta) ~ normal(0, 1);
  for (n in 1:N) {
    row_vector[J] mu = x[n]*beta;
    y[n] ~ multi_normal(mu, Sigma);
  }
}
```

Also reverse `lkjCorrCholeskyPriorMatchesGolden` (`:1045`) and
`wishartPriorMatchesGolden` (`:1069`) as smaller unit fixtures.

## 3. Implementation status — all slices shipped ✅

| Stage | File | Status |
|---|---|---|
| Declaration types (M1) | `Stan2Alist/StanProgram.swift` | `StanType` gains `matrix`, `covMatrix`, `cholFactorCorr`, `arrayVector`. |
| Declaration parsing (M1) | `Stan2Alist/StanBlockParser.swift` (`classifyType`) | All four new shapes parsed. |
| Reverse catalog (M2) | `Generator/DistributionCatalog.swift` | `multi_normal`, `multi_normal_cholesky`, `lkj_corr_cholesky`, `wishart` added. |
| Role inference (M3) | `Stan2Alist/StanToUlamModel.swift` | All parameter kinds classified; priors rebuilt in declaration order. `to_vector(<m>)` LHS handled. Plain vector priors (size not an index `upper`) emit `.vectorPrior`. |
| SUR loop recognition (M4) | `Stan2Alist/StanBlockParser.swift` (`appendRewrittenSurLoop`) | Two-statement body lowered to `.assignment` + `.sampling`. |
| alist text (M5) | `Stan2Alist/AlistTextEmitter.swift` | `vectorPrior`, `lkjCorrCholeskyPrior`, `wishartPrior`, `varyingVectorPrior`, `matrixPrior`, `covMatrixPrior` all render. |
| Tests + oracle (M6) | `Tests/SwiftStanTests/Stan2AlistTests.swift` | Catalog symmetry extended to multivariate; `cafeMultivariateRoundTrip` and `surMultivariateRoundTrip` oracle tests pass byte-identically via `Stan → [Statement] → stancode`. All 22 tests pass. |
| `generated quantities` bonus | `StanBlockParser` + `StanToUlamModel` + `AlistTextEmitter` | `generated quantities` block is now **parsed** (into `StanProgram.gqStatements`) instead of dropped; `reconstructGQ` maps `<dist>_rng(<args>)` assignments back to `Statement.generatedQuantity`; emitter renders them as `<name> <- sim(d*(<args>))`. |

**Deferred (not blocking the oracle):** the full alist-text round-trip (`alist → stancode → stan2alist → stancode`) for Family A multivariate models is blocked by `AlistLexer` not recognising the `'` transpose operator in `[a_bar, b_bar]'`. The hard gate (§1) uses `Stan → [Statement] → stancode` directly and is unaffected. Deferred: AlistLexer `'` support; `c(...)` prior regrouping in Family A alist text.

## 4. Slices (independently testable)

### Slice M1 — declaration types + parser

`StanProgram.StanType` gains:

```swift
case matrix(rows: String, cols: String)      // matrix[r, c]
case covMatrix(dim: String)                  // cov_matrix[K]
case cholFactorCorr(dim: String)             // cholesky_factor_corr[K]
case arrayVector(outer: String, length: String)  // array[outer] vector[length]
```

`StanBlockParser.classifyType` learns these shapes (constraint `<...>` is already
stripped upstream at `parseDeclaration:160`, so `vector<lower=0>[J]` still lands
as `.vector(size:"J")` unchanged):

- `array[<outer>] vector[<length>] x` → `.arrayVector`. Extend the existing
  `array[` branch (`:175`) — after pulling the outer size, peek for an inner
  `vector[...]` before falling back to int/real.
- `cholesky_factor_corr[<K>]` → `.cholFactorCorr`.
- `cov_matrix[<K>]` → `.covMatrix`.
- `matrix[<r>, <c>]` → `.matrix` (split the bracket on the top-level comma).

Unit-test against each declaration line in the §2 goldens.

### Slice M2 — reverse distribution catalog

Add to `DistributionCatalog.distribution(fromStanName:args:)` (`:378`):

```swift
case "multi_normal":          try require(2); return .multivariateNormal(mu: a[0], sigma: a[1])
case "multi_normal_cholesky": try require(2); return .multivariateNormalCholesky(mean: a[0], chol: a[1])
case "lkj_corr_cholesky":     try require(1); return .lkjCorrCholesky(a[0])
case "wishart":               try require(2); return .wishart(nu: a[0], V: a[1])
```

The existing `distributionArg(from:)` (`:350`) already turns `[a_bar, b_bar]'`
and `diag_pre_multiply(sigma_ab, L_Omega)` into `.expression(...)` (verbatim
round-trip). `args` were split at `splitTopLevelCommas`, which already protects
the inner comma of `[a_bar, b_bar]` (depth tracks `[`). Verify `'` (transpose)
survives the slice — it does, it's just trailing text on the expression.

Replace `Stan2AlistTests.unsupportedDistributionThrows` with a *symmetry* test:
each multivariate `Distribution` survives `args(_:) → distribution(fromStanName:)`.

### Slice M3 — role inference (`StanToUlamModel`)

Extend the parameter-classification walk (`:91`). New per-decl buckets:

```swift
var cholFactorDim:   [String: String] = [:]   // name → K
var arrayVectorShape:[String: (outer: String, length: String)] = [:]
var covMatrixDim:    [String: String] = [:]
var matrixShape:     [String: (rows: String, cols: String)] = [:]
```

Sampling-statement routing — dispatch on the **LHS declaration kind**, not the
distribution name:

| LHS is… | dist reconstructed | emit Statement |
|---|---|---|
| `cholFactorDim[lhs]` | `.lkjCorrCholesky(eta)` | `.lkjCorrCholeskyPrior(name: lhs, dim: K, eta:)` |
| `cholFactorDim[lhs]` | `.wishart(nu, V)` (if `cov_matrix`) | `.wishartPrior(name, dim, nu, V)` — wishart targets `covMatrixDim` |
| `covMatrixDim[lhs]` | `.wishart(nu, V)` | `.wishartPrior(name: lhs, dim:, nu:, V:)` |
| `arrayVectorShape[lhs]` | `.multivariateNormalCholesky` / `.multivariateNormal` | `.varyingVectorPrior(name: lhs, indexedBy:, length:, countSymbol: nil, distribution:, …)` |
| `vectorParamSize[lhs]`, size **is** an index `upper` | any | `.varyingPrior` (existing) |
| `vectorParamSize[lhs]`, size **is not** an index `upper` | any | **NEW:** `.vectorPrior(name: lhs, length: size, distribution:, truncation:)` — fixes the `:133` throw for `sigma_ab` |
| `to_vector(<m>)` LHS, `matrixShape[m]` | any | `.matrixPrior(name: m, rows:, cols:, distribution:, …)` |

`varyingVectorPrior` pairing: `arrayVectorShape[ab].outer == "N_cafe"`; find the
index column whose `<upper>` is `N_cafe` (reuse `columnByCardinality`, already
built at `:69`) → `indexedBy: "cafe"`. Setting `countSymbol: nil` makes the
forward re-derive `outer = "N_\(indexedBy)" = "N_cafe"` — byte-identical.

`covMatrix` declared but **never sampled** (the SUR `Sigma`): emit
`.covMatrixPrior(name, dim)` (forward emits *no* sampling line for it — see
`BlockEmitter:410` — so this is declaration-only and round-trips).

The Family-A linear model needs **no new logic**: the contract-loop rewriter
(`StanBlockParser:331` `desubscript`) already turns
`mu[i] = ab[cafe[i]][1] + ab[cafe[i]][2]*afternoon[i]` into
`mu = ab[cafe][1] + ab[cafe][2]*afternoon`, which becomes `.deterministic(mu, …)`;
forward `canLoopEmit` re-recognises `ab` as a varying-vector param (because we
emit the `.varyingVectorPrior`) and re-wraps the loop identically.

### Slice M4 — SUR loop recognizer (`StanBlockParser`)

The SUR loop is off the single-assignment contract, so `rewriteContractLoops`
needs a sibling that recognises exactly:

```stan
for (n in 1:N) {
  row_vector[<dim>] <mean> = <rhs>;
  <outcome>[n] ~ multi_normal(<mean>, <cov>);
}
```

and lowers it to two `StanModelStatement`s:

- `.assignment(lhs: mean, rhs: <rhs>)` — strip the `row_vector[<dim>]` type
  prefix; **keep `<rhs>` verbatim** (`x[n]*beta`, `[n]` intact — forward's
  `detectSurLoops` reads `detRhs.source` verbatim, `BlockEmitter:544`).
- `.sampling(lhs: outcome, distName: "multi_normal", args: [mean, cov], trunc: nil)`
  — strip `[n]` from the outcome (`y[n]` → `y`). The `row_vector[J]` dim `J` is
  **not** captured; forward re-derives it from `covMatrixParameters[cov]`
  (`BlockEmitter:539`).

In `StanToUlamModel`, the `multi_normal` sampling whose LHS is a **matrix data
column** becomes `.likelihood(y, .multivariateNormal(mu, Sigma))`; the paired
`.assignment(mu, "x[n]*beta")` becomes `.deterministic`. Forward `detectSurLoops`
(`BlockEmitter:526`) re-pairs and re-emits the loop byte-identically.

Implementation note: keep this recognizer *additive* and *fail-loud* — match the
exact two-statement / `n in 1:N` / `multi_normal` shape; anything else still
throws `unsupportedLoop`. Reuse `matchingDelimiterIndex` / `splitStatements`.

### Slice M5 — alist text (best-effort, `AlistTextEmitter`)

Add `renderStatement` cases (not gated by the oracle, so heuristic is fine):

- `.vectorPrior(name, _, dist, …)` → `name ~ <dist>(args)`.
- `.lkjCorrCholeskyPrior(name, _, eta)` → `name ~ dlkjcorr(<eta>)`.
- `.wishartPrior(name, _, nu, V)` → `name ~ dwishart(<nu>, <V>)`.
- `.varyingVectorPrior(name, indexedBy, …, .multivariateNormalCholesky(mean, chol))`
  → decompose for readability: `<mean>` `[a, b]'` → `c(a, b)`; `<chol>`
  `diag_pre_multiply(sig, corr)` → emit `dmvnorm2(c(a,b), <sig>, <corr>)`.
  Render LHS as `<name>[<indexedBy>] ~ …` (single synthesized name — component
  names are unrecoverable; documented loss).
- `.matrixPrior` / `.covMatrixPrior` — declaration-only in McElreath; render a
  comment line or skip with a recorded warning (no native alist idiom).

`mcElreathName` already maps the multivariate `Distribution`s
(`DistributionCatalog:335`); add `dmvnorm2` handling in the emitter since the
catalog can't know the `dmvnorm2` vs `dmvnormchol` arg split.

### Slice M6 — tests + oracle

`Stan2AlistTests.swift`:

- **Replace** `unsupportedDistributionThrows` with the M2 catalog-symmetry test.
- `parsesCafeMultivariateStan` — `StanBlockParser` accepts the §2 Family-A
  golden (new decl types, chained-index contract loop).
- `parsesSurMultivariateStan` — accepts the §2 Family-B golden (SUR loop,
  `to_vector` prior, `cov_matrix` declaration-only).
- **Round-trip oracle** (`cafe`, `WaffleDivorce`, `lkjCorrCholesky`, `wishart`):
  build the `UlamModel` → `stancode` → `StanBlockParser` → `StanToUlamModel` →
  `stancode` → assert byte-identical to the first `stancode`. This is the gate.
- Keep an off-contract loop (e.g. SUR body with a third statement) asserting
  `unsupportedLoop` — the fail-loud guard must survive.

## 5. Implementation order — completed

All six slices shipped in a single pass. M1–M3 unlocked Family A (cafe); M4 additionally unlocked Family B (SUR). Family A is byte-identical via the `Stan → [Statement] → stancode` oracle. Family B likewise. The alist-text round-trip is blocked only by the `AlistLexer '` gap (see §3).

## 6. Locked decisions & known losses

1. **Oracle = stancode round-trip byte-identical.** alist text is best-effort.
2. **Component names are lost.** `c(a_cafe, b_cafe)[cafe]` → combined `ab`; the
   reverse emits a single synthesized name. Invisible to the oracle (the linear
   model uses `ab[cafe][k]`, which is what the Stan carries).
3. **`dmvnorm2` vs `dmvnormchol` is lost.** Both lower to
   `diag_pre_multiply(sigma, corr)`; the reverse picks one spelling for alist
   text. Semantically identical; oracle unaffected (args round-trip verbatim).
4. **`cov_matrix` priors are declaration-only.** No alist idiom; rendered as a
   warning/comment, re-derived on the forward pass from the declaration.
5. **Multivariate truncation stays rejected** — Stan has no `T[...]` for
   multivariates (`BlockEmitter:1055` already guards the forward direction).
6. **Fail-loud preserved.** Any multivariate shape outside these two families
   (general `multi_normal` topologies, `lkj_corr` non-Cholesky, mixed nesting)
   still throws rather than guessing.

## 7. Risks

- **SUR loop-var collision.** Family A loops use `i`, Family B uses `n`. The SUR
  recognizer must key on the *body shape* (`row_vector` local + `multi_normal`
  sampling), not the loop var, to avoid mis-routing a contract `i`-loop.
- **`to_vector(...)` arg-splitting.** The LHS `to_vector(beta)` must be peeled
  before the `~` split; ensure the sampling parser (`StanBlockParser:388`)
  doesn't choke on a function-call LHS (it currently assumes a bare identifier
  downstream in `StanToUlamModel`).
- **Index-column re-pairing for `array[N_g] vector[K]`.** If a model has two
  group indices sharing a cardinality, `columnByCardinality` is ambiguous —
  confirm via the `ab[<col>]` reference in the linear model (the forward already
  relies on this). Out-of-v1 ambiguity → fail loud.
- **`matrix` data vs `matrix` parameter.** `matrix[N, c]` (data, row dim `N`) vs
  `matrix[r, c]` (parameter) — disambiguate by block, as the existing
  data/parameter split already does.
