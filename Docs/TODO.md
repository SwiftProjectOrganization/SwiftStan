# TODO

Outstanding issues and deferred work — items not yet implemented.

## General

- Change the `<Stan_Cases>` being set by an environment variable approach to a settable path.

## Alist parser gaps

- **Alist-side `start = list(...)` / `constraints = list(...)` syntax.** No parser/lowering support yet — McElreath `.alist.R` files can't express per-prior start or constraint overrides; users must author in Swift DSL or hand-edit `<name>.init.json`.
- **Alist-side crossed effects.** `AlistClassify.swift varyingVectorLengthSymbol = "J"` is hard-coded; two `c(...)[subject]` + `c(...)[item]` lines in the same `.alist.R` would collide on the shared `"J"` bucket. Fix: replace the constant with a per-grouping `J_<indexedBy>` helper and thread through the four use sites (lines 100, 101, 134/147, 173), including pairing the `lkjCorrCholeskyPrior` arm with its companion `dmvnormchol` line to pick up the right group's `J`.
- **Alist parser support for nested groupings** (`a[country, region] ~ dnorm(...)` in `.alist.R` files). Today only the Swift DSL exposes the surface.
- **`mo()` alist alias** for monotonic effects.
- **`dordlogit` / `dordprobit` alist aliases** for ordered logit/probit.
- **Indexed bare LHS** (`mu[i] <- …`). The identity-link path accepts plain-identifier LHS only. Per-row deterministic assignment with an indexed target would need an `AlistSampleLhs.indexedTarget`-style addition + a loop-body emitter.

## Multi-grouping / higher-dimensional

- **3+ grouping dimensions** for nested groupings (`a[country, region, year]` → `array[N1, N2, N3]`; would need a more general n-arg subscript AST node and array-shape declarations rather than `matrix`).
- **Varying nested groupings** — a nested group paired with a vector prior (`array[N_c, N_r] vector[J]` for cell-wise vectors of coefficients).
- **3+ crossed groupings** (path scales naturally but no golden test today).
- **Crossed-with-nested combinations** (e.g. nested `subject` inside `class`, crossed with `item`).
- **brms `(1 + x | group)` shorthand** — would need new alist syntax that expands to existing primitives.

## GP priors

- **`dgpl2` alist alias** for Gaussian process priors.
- **Additional GP kernels** (Matérn, periodic, `cov_GPL1`).
- **Non-Euclidean distance** for GP.
- **Multi-grouping GP** (single grouping level currently hard-coded to `N`).

## Init / start values

- **Auto-inference of init values from prior means.**
- **Per-chain start values.** cmdstan's `init=` accepts a comma-separated list of paths for distinct per-chain starts; today's `[String: Double]` dict can't carry that.
- **Vector / array init values.** V1 ships scalars only.

## Validation gaps

- **Validation of `constraints:` values.** No check that `lower < upper`, or that the constraint is consistent with the distribution's support (e.g. `lower=-1` on `.exponential` would be silently accepted; Stan rejects at runtime).
- **`constraints:` on shaped-parameter nodes** (`VectorPrior`, `MatrixPrior`, `CovMatrixPrior`, `LKJCorrCholeskyPrior`, `WishartPrior`, `OrderedCutpoints`, `SimplexPrior`, `VaryingVectorPrior`) — type-keyword constraints make `<lower=…, upper=…>` either illegal or redundant; should stay unsupported with an explicit gate.
- **Ordered likelihood validation.** K inferred from R's max value; per-index cutpoint priors; explicit truncation rejection.

## Binomial / outcome

- **`append_row(0, delta)` 0-indexed trick** for monotonic effects (lets predictor=0 mean baseline).
- **Multiple monotonic predictors per single targetLhs** (architectural support exists; ordering not yet covered by tests).
- **Per-row binomial trials as vector data** — `binomialRowChecks` currently produces a `transformed data` rejection block; could additionally tighten the outcome declaration bound.

## `stan2alist` reverse pipeline

- **`c(...)` prior regrouping for Family A alist text** — cosmetic reconstruction of group priors not currently attempted.
- **`transformed *` block reconstruction** — currently dropped with a warning.

## Other

- **Single-chain `_output.csv` form** — `chainOutputFiles` glob handles it, but end-to-end test coverage for `num_chains=1` is thin.
