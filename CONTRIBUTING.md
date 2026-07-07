# Contributing to Logjam

## Docstring examples must show their output

Every exported function's docstring carries an `# Example` (or `# Examples`) section, and
that example **shows its actual output**. An example that shows only how to *call* a
function documents half the contract; showing the return makes the docstring an oracle —
a reader can write a unit test against it without running anything, and a reader who does
run it sees immediately if behavior has drifted.

There are two tiers, chosen by whether the output is deterministic and stable.

### Tier 1 — deterministic → `jldoctest` (CI-enforced)

Pure functions with stable output use a **script-form** `jldoctest` block: the code, a
`# output` marker, then the expected result.

````julia
"""
    ...
```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [0 3 7 10 6 4; 3 0 4 7 6 7; 7 4 0 3 6 8; 10 7 3 0 7 8; 6 6 6 7 0 2; 4 7 8 8 2 0]
y, TC, W = ufladd(k, C)
(y, TC)

# output

([2, 6], 32.0)
```
"""
````

Use the **`# output`** (script) form, not the `julia> ` (REPL) form. The code above
`# output` is plain, copy-paste-runnable Julia — it runs as a VS Code cell, the workflow
the course uses — while Documenter still checks the result. Reserve the `julia> ` form for
the rare case that needs interleaved intermediate checks.

These blocks are executed by `Documenter.doctest` and **gate every pull request** (see
[Running the doctests](#running-the-doctests)).

### Tier 2 — fragile → runnable block with a captured-output comment

Some functions cannot produce stable, exact output and must **not** be `jldoctest`:

| Fragility | Functions (examples) | Reason |
|-----------|----------------------|--------|
| RNG-dependent | `randX`, `ala` | Julia's RNG stream is not stable across versions |
| Network | `loc2lonlat`, `lonlat2loc` | depend on the Nominatim service / cache |
| Figures | `makemap`, `plotroads!`, `plotroute!` | return plot objects with unstable `show` |
| Bulk data | census/CBSA/CSA + FAF5 loaders | large `DataFrame`s; print format changes across DataFrames.jl versions |

These use a plain ` ```julia ` block annotated with a `# =>` comment showing the *stable*
part of the result — column names, row counts, return shape, or discrete fields — captured
from a live run:

````julia
```julia
df = uscbsa()
names(df)   # => ["CBSA", "NAME", "LON", "LAT", "POP", "ALAND", "AWATER", "IS_MSA", "CSA", "ISCUS"]
filter(r -> r.IS_MSA, df)       # => 382 of 918 are Metropolitan Statistical Areas
```
````

### Choosing a tier

```
Is the output deterministic AND stable across platform/version?
├─ yes → jldoctest  # output      (CI-enforced)
└─ no  → julia block + # => comment
         (RNG, network, figures, or a full DataFrame display)
```

## Output stability rules (for Tier 1)

CI runs on **Linux** (Julia 1.12 and `pre`); development is often on **Windows**. Doctest
output is compared literally, so it must be identical across both.

- **Algebraic / exact** (`+`, `*`, correctly-rounded `sqrt`, integer results): show
  verbatim. IEEE 754 guarantees bit-identical results across platforms.
- **Transcendental / floating-point** (`sin`/`cos`/`atan`-based distances, weighted
  centroids): **round** in the example — e.g. `round(dgc(...); digits=1)` or
  `round.(D; digits=1)`. Different libm implementations differ in the last ULP, which
  would break an exact match.
- **Discrete** (symbols, small integers, booleans): show verbatim — quantized output is
  robust to ULP noise (e.g. `aligntext`).
- **DataFrames**: do not doctest a rendered table (its format changes across DataFrames.jl
  versions). Doctest a stable projection instead — `names(df)`, `nrow(df)`, a single value.

Prefer a clean one-line final expression (a scalar or a tuple) over a multi-line array
display where practical; it is easier to read and less brittle.

## Running the doctests

The dedicated docs CI job only runs on release tags, so the doctests are also wired into
the test suite (`test/test_doctests.jl`) and run on **every PR**. To run them locally:

```julia
using Pkg; Pkg.test()          # full suite, including the `doctests` testset
```

or, faster, just the doctests against the docs environment:

```julia
julia --project=docs -e '
    using Documenter, Logjam
    DocMeta.setdocmeta!(Logjam, :DocTestSetup, :(using Logjam); recursive=true)
    doctest(Logjam; manual=false)'
```

When output legitimately changes, the failure message prints the actual value — paste it
into the `# output` block. (`doctest(Logjam; fix=true)` can rewrite outputs automatically,
but it is finicky when the module loads from a precompiled cache; the paste-from-failure
path is more reliable.)

## Sourced examples

Where a canonical, citable example exists, prefer it over an ad-hoc one — a reader can then
verify correctness against the source. The UFL family (`ufladd`, `ufldrop`, `uflxchg`,
`ufl`, `pmedian`) shares Example 8.8 from Francis, McGinnis & White, *Facility Layout and
Location* (2nd ed.; Daskin, *Network and Discrete Location*, 1995, Figs. 7.2/7.3/7.5), the
same example the Matlog originals ship.

## Naming

Follow current Logjam conventions (`k` for fixed cost, `C` for the cost matrix, `W` for the
allocation matrix, `LON`/`LAT` order). Matlog is a useful reference for algorithm provenance
and documentation *style*, but its variable names are dated — do not copy them.
