# SwiftStan User Guide

## Purpose of SwiftStan package

1. A MacOSv26/Xcode/Swift based CLI (Command Line Interface) to Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) executable.

2. Hosting a port of [McElreath](https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919)'s R implementation ulam() in [rethinking](https://github.com/rmcelreath/rethinking) to Swift.

This project is work in progress!!! Work completed or still to be done can be found in [TODO](https://github.com/SwiftProjectOrganization/Stan/blob/main/Docs/TODO.md). Some additional technical details can be found in [CLAUDE](https://github.com/SwiftProjectOrganization/Stan/blob/main/CLAUDE.md). Lots of testing and more examples are needed for the ulam pipeline.
---


## Supported functionality  

### Cmdstan pipeline related commands 

```gfm
| ------------ | ------------------------------------------ |
| Command      | Effect                                     |
| ------------ | ------------------------------------------ |
| compile              | Compile a Stan model                                      |
| sample               | Sample from a compiled model                              |
| stansummary          | Stansummary on a sampled model                            |
| optimize             | Optimize a compiled model                                 |
| pathfinder           | Pathfinder on a compiled model                            |
| laplace              | Laplace on a compiled model                               |
| generated_quantities  | Run generate_quantities on existing draws (see note 2)    |
| runinfo              | See note 1                                                |
| -------------------- | --------------------------------------------------------- |
```
**Notes**

1. The `runinfo` command reads `Results/<name>.config.json` (written by `sample`, which renames cmdstan's `<name>_output_config.json`) and cleans it in place — stripping absolute paths to basenames and sorting keys. It is also used internally by `stansummary` to determine the number of chains created by `sample`.
2. The `generated_quantities` command runs cmdstan's standalone `generate_quantities` method over the draws from a prior `sample` run and writes `Results/<name>.generated_quantities.csv`. The `.stan` file must contain a `generated quantities` block — add a `sim()` line to the alist before running `stancode` (see UlamManual.md §2.3.1), or hand-edit the `.stan` directly.

 
### Ulam pipeline related commands

```gfm
| ------------ | -------------------------------------- |
| Command      | Effect                                 |
| ------------ | -------------------------------------- |
| ulam         | Run the ulam pipeline end-to-end                       |
| stancode     | alist -> .stan (sim() lines emit generated quantities) |
| stan2alist   | .stan -> alist (inverse of stancode)                   |
| alist2dsl    | alist -> smoke driver                                  |
| dsl2stan     | smoke driver -> .stan (swiftc)                         |
| ------------ | -------------------------------------- |
```
**Notes**

1. By default `ulam` prefers the fast in-process `stancode` path when an "<name>.alist.R" is present.                          
2. Command `ulam` falls back to `dsl2stan` against a hand-authored "smoke driver". See DSLManual.md.
3. A `sim()` line in an alist (`y_rep <- sim(dnorm(mu, sigma))`) causes `stancode` to emit a `generated quantities` block. Run `generated_quantities` after `sample` to produce posterior-predictive draws. See UlamManual.md §2.3.1.


### Shared between both pipelines

```gfm
| ------------ | -------------------------------------- |
| Command      | Effect                                 |
| ------------ | -------------------------------------- |
| csv2json     | "<name>.csv" -> "<name>.json"            |
| ------------ | -------------------------------------- |
```

**Notes**
  
1. As with building a Stan binary during `compile`, all commands only operate when the input file's modification timestamp is newer than the corresponding output file timestamp. 
2. Run `csv2json` preferably after a "<name>.stan" file has been set up. In that case the "<name>.data.json" file reflects what is needed. It also adds items like 'N', the number of observations, and other needed data items such as 'N_blocks'.



## Prerequisites  

This [repository](https://github.com/SwiftProjectOrganization/SwiftStan) is an Xcode project. Some familiarity with running Xcode and Swift programs on MacOS is assumed. To edit documentation files, if not from within Xcode, I use [Clearly](https://clearly.md).

### 1. Clone the repository  

To get going, start Xcode and:  
  
  1. Click on `'Integrate'`.
  2. Select `'Clone'`.
  3. Enter the http address for this repository: "https://github.com/SwiftProjectOrganization/SwiftStan".  
  4. Click `'Clone'`.  

The repository will be downloaded and the project will open in Xcode.  
  
### 2. Setup steps

  1. To use Stan's cmdstan, typically an environment variable `"CMDSTAN"` is defined to point to the cmdstan directory. See references 1 and 2 below on how to install cmdstan and below .zshrc fragment how it can be included.
      
  2. `'build and run'` the project.
      
  3. Expand your CMDSTAN definition in your .zshrc with an `'alias'` and two more environment variables, `'STAN_CASES'` and `'SWIFTSTAN_PROJECT_ROOT'`:
  
```.zshrc

export CMDSTAN=/Users/rob/Projects/StanSupport/cmdstan/
launchctl setenv CMDSTAN /Users/rob/Projects/StanSupport/cmdstan/

alias swiftstan="/Users/rob/Library/Developer/Xcode/DerivedData/SwiftStan-*/Build/Products/Debug/SwiftStan"

export STAN_CASES="/Users/rob/Documents/StanCases"
launchctl setenv STAN_CASES /Users/rob/Documents/StanCases

export SWIFTSTAN_PROJECT_ROOT="/Users/rob/Projects/Swift/SwiftStan"
launchctl setenv SWIFTSTAN_PROJECT_ROOT /Users/rob/Projects/Swift/SwiftStan
```

Make sure "SwiftStan-*" points to the most recent version of SwiftStan in "../Xcode/DerivedData"

Environment variables used by the pipeline:

  - `CMDSTAN` — location of the cmdstan installation (required for `compile`/`sample`).
  - `STAN_CASES` — case-root directory name under `~/Documents/`; defaults to `StanCases`.
  - `SWIFTSTAN_PROJECT_ROOT` — location of the SwiftStan source checkout, used by the DSL pipeline's `dsl2stan` to compile a "smoke driver". It defaults to `/Users/rob/Projects/Swift/SwiftStan` and `dsl2stan` prints a notice that the default is being used.

### 3. Testing SwiftStan

After finishing the setup steps, in a (MacOS or other) Terminal:

1. Navigate to the SwiftStan directory, e.g. `cd ~/Project/Swift/SwiftStan`.

2. Enter `swift test`.

To run individual tests, use for example `swift test --filter "chimpanzeesHappyPath()"`.


## Working environment  

After the initial build, the intended usage is to run the commands from a shell. This requires the exported alias in a shell as setup above. It's not always necessary, but advisable, to run `swifstan ...` from the SwiftStan directory.

The above commands can also be run from within Xcode by specifying input arguments before hitting the `'build and run'` button. See below "Usage from within Xcode".  

### File system assumptions
 
All pipeline commands operate on a set of files stored in the directory `"~/Documents/<STAN_CASES>/<name>/..."`. Here <name> is the name of a model, e.g. bernoulli or chimpanzees.

The <STAN_CASES> enviroment variable specifies the actual location, by default this is `'StanCases'`. 

The cmdstan pipeline only uses files in `"~/Documents/<STAN_CASES>/name>/Results"`. All cmdstan output files also end up in Results.

The ulam pipeline looks either for files in `"~/Documents/<STAN_CASES>/<name>/Preliminaries"`, or, in case of the command `stan2alist`, for a `"<name>.stan"` file in `"<name>/Results"`.

Produced files end up in either Preliminaries (`"<Name>.ulam.swift"` and `"<name>.alist.r"`) or in Results (`"<name>.stan"` and `"<name>.data.json"`).

### Files read when using the pipelines

In `"~/Documents/<STAN_CASES>/<name>/Preliminaries"` 3 files can be present:

    1. `"<name>.csv"`: A .csv file containing the data for the <name>.
    2. `"<name>.alist.r"`: A .r fragment containing an R alist as used in `'rethinking'`.
    3. `"<Name>.ulam.swift"`: Intermediate file for debugging or handcoding Ulam DSL.

In `"~/Documents/<STAN_CASES>/<name>/Results"` at least 2 files must be present before the cmdstan pipeline can be used:

    1. `"<name>.data.json"`: If data is needed for the model.
    2. `"<name>.stan"`: Stan language program.
    
See the examples in UlamManual.md and DSLManual.md for details.            

### Per-invocation logs

Every cmdstan call (`compile`, `sample`, `optimize`, `laplace`, `pathfinder`, `stansummary`) writes its raw stdout and stderr to the model's `Results/` directory as:

```
~/Documents/<STAN_CASES>/name>/Results/<name>.<method>.log         # captured stdout
~/Documents/<STAN_CASES>/name>/Results/<name>.<method>.error.log   # captured stderr
```

Both files are written on every run (zero bytes means "ran but emitted nothing"); each invocation overwrites the previous log. cmdstan emits most diagnostics (warmup banners, divergence messages, treedepth warnings) to **stdout**, so the `.log` file is normally where to look first; `.error.log` is reserved for hard failures and a few compile-time messages.

The `sample` command uses `save_cmdstan_config=true` by default. cmdstan writes `<name>_output_config.json`; `sample` renames it to `<name>.config.json`. The `runinfo` subcommand reads that file and cleans it in place (absolute paths → basenames, sorted keys).


## Example cases

The repository ships ready-to-run inputs for every model worked through in the two manuals under the top-level `Examples/` directory. Each example is a self-contained case directory named after the model:

```
Examples/<name>/
├── Preliminaries/     the inputs (<name>.csv, <name>.alist.R, and for the DSL cases <Name>.ulam.swift)
└── Results/           empty — the pipeline writes its output here
```

To follow a manual, copy the case directory into your `~/Documents/<STAN_CASES>/` root and run the pipeline against it. For example:

```bash
cp -R Examples/howell ~/Documents/StanCases/
swiftstan ulam --model howell_m4_4

```

The cases routed through the in-process [`UlamManual.md`](UlamManual.md) (`stancode` path) are `radon`, `bernoulli_1`, `binomial`, `howell`, `radon_np`, `chimpanzees`, `ucb`, `cafe`, and `radon_pp`. The cases routed through the [`DSLManual.md`](DSLManual.md) (`alist2dsl` → `dsl2stan` path) are `radon_dsl`, `radon_np_dsl`, `chimpanzees_dsl`, and `cafe_dsl`. The `radon_pp_template` case demonstrates the reverse `stan2alist` path (§5.2.6): it ships a hand-written `Results/radon_pp_template.stan` (and its `.csv`) but no `.alist.R`.

Each `Results/` ships empty (it carries only a `.gitkeep` placeholder); the pipeline populates it on the first run. The exception is `radon_pp_template`, whose `Results/` ships the hand-written `.stan` that `stan2alist` reads.


## Usage  

The package can be used from the CLI (Terminal) or from within Xcode.

### Usage from the CLI

Help is available with `'swiftstan -h'` or `'swiftstan compile -h'`.

```.zshrc
rob@Rob-Travel-M5 ~ % stan -h
OVERVIEW: A wrapper for running cmdstan.

USAGE: swiftstan <subcommand>

OPTIONS:
  --version                 Show the version.
  -h, --help                Show help information.

SUBCOMMANDS:
  compile                   Compile the Stan model.
  sample                    Sample the Stan model.
  optimize                  Optimize the Stan model.
  pathfinder                Use Pathfinder approximation.
  laplace                   Run cmdstan's Laplace approximation on a compiled model.
  stansummary               Run the Stan summary program.
  csv2json                  Read Preliminaries/<name>.csv, writes Results/<name>.data.json.
  dsl2stan                  Compile a Preliminaries/*.ulam.swift, write Results/<name>.stan.
  alist2dsl                 Translate Preliminaries/<name>.alist.R into  Preliminaries/<Name>.ulam.swift.
  stancode                  Translate Preliminaries/<name>.alist.R straight to Results/<name>.stan (in-process, no swiftc).
  stan2alist                Reverse-translate Results/<name>.stan into Preliminaries/<name>.alist.R (inverse of stancode).
  runinfo                   Clean Results/<name>.config.json in place (basenames, sorted keys).
  ulam                      Run one of the built-in ulam DSL demos (--model Bernoulli|Poisson|Binomial|UCB|Dmvnorm).
  test (default)            Test the CLI functions.

  See 'swiftstan help <subcommand>' for detailed help.
rob@Rob-Travel-M5 ~ % 
```

If the appropriate files are present, a typical Terminal session could continue with:

1. `'swiftstan compile --model bernoulli'`
2. `'swiftstan sample --mode lbernoulli'`

or

3. `'swiftstan ulam --mode lchimpanzees'`

The `alist2dsl` command uses Swift to first create an intermediate `'DSL smoke driver'` which takes roughly 6 seconds longer. But I do like the option to generate the DSL where the structure of the Stan model is clearly labeled and the input data file checked.

### Usage from within Xcode

Edit the schema arguments, e.g. `'compile --model=bernoulli'` and press "build-and-run".

### Bootstrapping the bernoulli example

Use the -I switch to install required files to compile and sample a bernoulli Stan Language Program.

In the SwiftStan directory:

1. `swiftstan compile -I`
2. `swiftstan sample -I`


### Alist distribution names to Stan distribution names

These are the R alist names that `stancode` / `alist2dsl` recognise. DSL-only distributions (not accessible from an `.alist.R` file) are noted in the second column.

| Alist (R) name | Stan sampling name | DSL node | Notes |
|---|---|---|---|
| `dnorm(mu, sigma)` | `normal` | `Prior` / `Likelihood` | |
| `dbinom(1, p)` | `bernoulli` | `Likelihood` | McElreath shorthand; collapses in lowering |
| `dbern(p)` | `bernoulli` | `Likelihood` | Direct 1-arg form |
| `dbinom(n, p)` | `binomial` | `Likelihood` | General case |
| `dbeta(a, b)` | `beta` | `Prior` | |
| `dexp(r)` | `exponential` | `Prior` | |
| `dpois(r)` | `poisson` | `Likelihood` | |
| `dgamma(shape, rate)` | `gamma` | `Prior` | |
| `dcauchy(mu, sigma)` | `cauchy` | `Prior` | |
| `dlnorm(mu, sigma)` | `lognormal` | `Prior` | |
| `dunif(lower, upper)` | `uniform` | `Prior` | |
| `dt(nu, mu, sigma)` | `student_t` | `Prior` | |
| `dmvnorm(mu, sigma)` | `multi_normal` | `Likelihood` | SUR only |
| `dlkjcorr(eta)` | `lkj_corr_cholesky` | `LKJCorrCholeskyPrior` | Grouped-indexed; maps to Cholesky form |
| `dmvnormchol(Mu, L_Rho, sigma)` | `multi_normal_cholesky` | `VaryingVectorPrior` | Grouped-indexed only |
| `dmvnorm2(Mu, sigma, Rho)` | `multi_normal_cholesky` | `VaryingVectorPrior` | Grouped-indexed only; arg order differs from `dmvnormchol` |
| — *(DSL only)* | `wishart` | `WishartPrior` | No alist name |
| — *(DSL only)* | `ordered_logistic` | `Likelihood` + `OrderedCutpoints` | No alist name |
| — *(DSL only)* | `ordered_probit` | `Likelihood` + `OrderedCutpoints` | No alist name |
| — *(DSL only)* | `dirichlet` | `Prior` | No alist name; used with `SimplexPrior` |

### `Sim()` / `sim()` — posterior-predictive draws and `_rng` support

`Sim("y_rep", .dist(...))` in the DSL (written `y_rep <- sim(d*(...))` in an `.alist.R`) emits a `generated quantities` block entry of the form `array[N] int/real y_rep = dist_rng(args);`. The `_rng` name is the Stan sampling name with `_rng` appended; the output type is `array[N] int` for discrete distributions and `array[N] real` for continuous ones.

**Supported — Stan has a scalar-returning `_rng` function:**

| Distribution | Alist `sim()` | DSL `Sim()` | Stan emitted | Output type |
|---|---|---|---|---|
| `normal` | `sim(dnorm(mu, sigma))` | `.normal(mu, sigma)` | `normal_rng(mu, sigma)` | `array[N] real` |
| `bernoulli` | `sim(dbinom(1, p))` | `.bernoulli(p: p)` | `bernoulli_rng(p)` | `array[N] int` |
| `binomial` | `sim(dbinom(n, p))` | `.binomial(n: n, p: p)` | `binomial_rng(n, p)` | `array[N] int` |
| `beta` | `sim(dbeta(a, b))` | `.beta(a, b)` | `beta_rng(a, b)` | `array[N] real` |
| `exponential` | `sim(dexp(r))` | `.exponential(r)` | `exponential_rng(r)` | `array[N] real` |
| `poisson` | `sim(dpois(r))` | `.poisson(r)` | `poisson_rng(r)` | `array[N] int` |
| `gamma` | `sim(dgamma(shape, rate))` | `.gamma(shape, rate)` | `gamma_rng(shape, rate)` | `array[N] real` |
| `cauchy` | `sim(dcauchy(mu, sigma))` | `.cauchy(mu, sigma)` | `cauchy_rng(mu, sigma)` | `array[N] real` |
| `lognormal` | `sim(dlnorm(mu, sigma))` | `.lognormal(mu, sigma)` | `lognormal_rng(mu, sigma)` | `array[N] real` |
| `uniform` | `sim(dunif(a, b))` | `.uniform(lower: a, upper: b)` | `uniform_rng(a, b)` | `array[N] real` |
| `student_t` | `sim(dt(nu, mu, sigma))` | `.studentT(nu: nu, mu: mu, sigma: sigma)` | `student_t_rng(nu, mu, sigma)` | `array[N] real` |
| `ordered_logistic` | — *(DSL only)* | `.orderedLogistic(eta: eta, cutpoints: c)` | `ordered_logistic_rng(eta, c)` | `array[N] int` |

**Not supported in `Sim()` — no scalar Stan `_rng` or wrong return type:**

| Distribution | Reason |
|---|---|
| `multi_normal` | `multi_normal_rng` returns a `vector`, not a scalar — `array[N] real` declaration is wrong |
| `multi_normal_cholesky` | `multi_normal_cholesky_rng` returns a `vector` — same issue |
| `lkj_corr_cholesky` | `lkj_corr_cholesky_rng` does not exist in Stan's function library |
| `wishart` | `wishart_rng` returns a `matrix` — `array[N] real` is wrong |
| `dirichlet` | `dirichlet_rng` returns a `vector` (simplex) — `array[N] real` is wrong |
| `ordered_probit` | `ordered_probit_rng` does not exist in Stan's function library |

Using any of the unsupported distributions with `Sim()` throws `DataInferenceError.unsupportedSimDistribution` at code-generation time — before any Stan is emitted.


## Additional project documentation

- [`../CLAUDE.md`](../CLAUDE.md) — architecture notes for the SwiftStan package (Commands / Methods / Support layering, the `(String, String)` return convention, the Ulam module layout, etc.). Loaded by Claude Code sessions in this workspace.
- [`TODO.md`](TODO.md) — forward-looking punch list for more advanced topics (SUR, LKJ-Cholesky, post-sampling helpers, etc.).



## References

1. [Stan](https://mc-stan.org)
2. [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/)
3. [McElreath, *Statistical Rethinking* (2nd ed.)}(https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919) — `ulam()` is from the accompanying R `rethinking` package.
