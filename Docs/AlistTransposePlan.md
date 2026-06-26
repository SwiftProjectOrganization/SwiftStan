# Alist Transpose `'` Support Plan

Completes the deferred alist-text round-trip for Family A multivariate
models (noted in `Docs/MultivariateReverseMappingPlan.md` §3). The
hard oracle (`Stan → [Statement] → stancode`) already passed. This plan
targets the softer oracle:

```
cafeAlist  ──stancode──▶  .stan  ──stan2alist──▶  .alist.R
           ──AlistParser──▶  [Statement]  ──stancode──▶  .stan'
```

where `.stan'` must equal the original `.stan` byte-for-byte.

## 1. Exact failure chain (now fixed ✅)

`AlistTextEmitter.renderStatement(.varyingVectorPrior(...,
.multivariateNormalCholesky(...), ...))` previously called
`renderDistribution`, which routed through `DistributionCatalog.mcElreathName`
and `args`. This emitted:

```
ab[cafe] ~ dmvnorm([a_bar, b_bar]', diag_pre_multiply(sigma_ab, L_Omega))
```

Three sequential problems blocked re-parsing via `AlistParser.parse`:

| # | Problem | Where it failed | Fix |
|---|---|---|---|
| A | `'` (apostrophe) not in `AlistLexer` | `AlistLexer.tokenize` → `unexpectedCharacter` | T1: add `case prime` |
| B | `dmvnorm` (2-arg) lowered to `.multivariateNormal` → `stancode` emitted `multi_normal`, not `multi_normal_cholesky` | `AlistLowering.lowerDistribution("dmvnorm", ...)` | T4: emit `dmvnorm2(c(...), sigma, L)` instead |
| C | `.indexed("ab", "cafe")` LHS with a multivariate distribution never reached `lowerGroupIndexed` | `AlistLowering.lower`, `.indexed` case | T3: extend `.indexed` case for `dmvnorm2`/`dmvnormchol` |

## 2. Implementation status — all slices shipped ✅

| Slice | File | What changed |
|---|---|---|
| **T1** — AlistLexer `'` token | `Ulam/Alist/AlistLexer.swift` | Added `case prime` to `AlistToken.Kind`; `'` recognized as `.prime` instead of throwing `unexpectedCharacter`. |
| **T2** — `parseBracketVectorArg` | `Ulam/Alist/AlistParser.swift` | New helper alongside `parseCRowVectorArg`: `[id1, id2, …]'` in a distribution-arg position → `"[id1, id2, …]'"` string. Called first in `parseDistribution`. |
| **T3** — packed indexed LHS lowering | `Ulam/Alist/AlistLowering.swift` | `.indexed` LHS case now detects `dmvnorm2`/`dmvnormchol` and routes through new `lowerPackedIndexed` helper. Length derived from `c(…)` mean-arg count. `componentNames: []` (recoverable only from `c(…)` LHS, not from the packed name). |
| **T4** — emitter `dmvnorm2(c(...))` | `Ulam/Stan2Alist/AlistTextEmitter.swift` | `renderStatement` for `.varyingVectorPrior` with `.multivariateNormalCholesky` now calls `renderVaryingVectorCholDist` to decompose stored `[a, b]'` mean and `diag_pre_multiply(sigma, L)` chol args into `dmvnorm2(c(names), sigma, L)`. No `'` in output. |
| **T5** — oracle tests | `Tests/SwiftStanTests/Stan2AlistTests.swift` | Added `primeLexerNoCrash` (T1), `bracketVectorArgEquivalentToCVector` (T2), `indexedLhsDmvnorm2LowersToVaryingVector` (T3), `varyingVectorPriorEmitsDmvnorm2` (T4), `cafeAlistFullRoundTrip` (T5). 27/27 pass. |

## 3. Target emitter output (achieved)

The emitter now produces:

```
ab[cafe] ~ dmvnorm2(c(a_bar, b_bar), sigma_ab, L_Omega)
```

- No `'` in the output → A is defensive only (user-written `[a, b]'` alist no longer crashes).
- `dmvnorm2` + `c(a_bar, b_bar)` → `parseCRowVectorArg` returns `"[a_bar, b_bar]'"` → correct `.multivariateNormalCholesky` → `multi_normal_cholesky` in Stan → B solved.
- `.indexed("ab", "cafe")` LHS + `dmvnorm2` → `lowerPackedIndexed` → C solved.

## 4. Scope limits (unchanged)

- `ExpressionParser` and `ExpressionLexer` are **not changed**. The `'` character only appears in distribution-arg position, intercepted by `parseBracketVectorArg` before `parseExpression` is called.
- `Statement.varyingVectorPrior` gains **no new fields**. Component names are not stored.
- Only `dmvnorm2` and `dmvnormchol` get the T3 `.indexed` treatment.

## 5. Known residual loss

- `componentNames` are not recovered — the emitted alist uses `ab[cafe]` (packed name), not `c(a_cafe, b_cafe)[cafe]`. The `componentNames` field in `varyingVectorSample` is `[]` on the reverse path. `AlistEmitter.swift` (DSL-text forward emitter) uses the packed name verbatim — missing per-component labels. Affects only the `dsl2stan` path, not `stancode`. The oracle is `stancode` byte-identical, so this loss does not break the acceptance gate.
- `dmvnorm([…]', …)` written by hand (non-standard McElreath) is now tokenised (T1) and the `[…]'` arg parsed (T2), but `lowerDistribution("dmvnorm", 2args)` yields `.multivariateNormal` → `multi_normal` in Stan (not `multi_normal_cholesky`). Documented; this was always a lossy path. The emitter never produces this form.
