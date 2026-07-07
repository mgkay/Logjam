# Logjam Release Notes

## v0.2.9

### Improvements

- **Uniform `ISCUS` column.** `uscounty`, `uscenblkgrp`, and `uscsa` now carry an
  `ISCUS::Bool` column ("within continental U.S.") as their final column, matching
  the five census loaders (`usplace`, `uscentract`, `uszcta5`, `uszcta3`, `uscbsa`)
  that already had it — so all eight US-prefixed census tables share the field and
  downstream code can rely on it. `ISCUS` is computed from each row's `LON`/`LAT`
  against the continental-U.S. bounding box, identical to the existing loaders.
  Additive and non-breaking: existing columns and their order are unchanged.

## v0.2.8

### Breaking changes

- **Census loaders are LON-first.** The eight census/gazetteer tables
  (`usplace`, `uscounty`, `uscentract`, `uscenblkgrp`, `uszcta5`, `uszcta3`,
  `uscbsa`, `uscsa`) now return the `LON` column immediately before `LAT`,
  following Logjam's `(LON, LAT)` convention; all other columns are unchanged.
  Migration: use named column access (`df.LON`, `df.LAT`) rather than positional
  indices, which now resolve `LON`/`LAT` in swapped positions.
- **`uscbsa` `M_MSA::String31` → `IS_MSA::Bool`.** The metro/micro classification
  is now a boolean: `true` marks a Metropolitan Statistical Area (382 of them),
  `false` a Micropolitan Statistical Area. Migration: replace
  `filter(r -> r.M_MSA == "Metropolitan Statistical Area", uscbsa())` with
  `filter(r -> r.IS_MSA, uscbsa())`.
- **`makemap` returns `(fig, ax)`.** The third return value and the `hborders`
  and `limits` keywords are removed. Migration: destructure two values
  (`fig, ax = makemap(...)`) and restyle the built-in road overlay with the new
  `roadcolor`/`roadalpha` keywords (e.g. `makemap(x, y; roadcolor=:steelblue,
  roadalpha=0.5)`) instead of mutating a returned line handle
  (`hb[1].color[] = ...`).
- **`mapbbox` returns the expanded bounding box only.** The function now returns
  the single box `((xmin, xmax), (ymin, ymax))` directly rather than a tuple whose
  first element is the box. Migration: drop the trailing `[1]` —
  `mapbbox(x, y; xexpand=0.1, yexpand=0.1)` instead of `...[1]`.

### Improvements

- **`Float64` cost returns.** `d1` and the total-cost (`TC`) return of `ufladd`,
  `ufldrop`, `uflxchg`, `ufl`, and `pmedian` are now always `Float64`, even for
  integer inputs; `ufl(verbose=true)` accordingly prints values such as
  `Add: 17.0`.
- **`uscentract.ST::Symbol` and `uscsa.NAME::String`.** `uscentract().ST` is now a
  `Symbol` (matching `usplace().ST`, so `filter(r -> r.ST == :NC, uscentract())`
  works directly), and `uscsa().NAME` is now a plain `String`.
- **Runnable docstring examples.** The census and FAF5 loaders and the data
  helpers (`mat2df`, `snapvals`, `isptinbbox`, `st2fips`, `fips2st`) now carry
  self-contained, runnable `# Example` code blocks reflecting the LON-first order.
- **`mat2df` `row_title` keyword.** `mat2df` gains a `row_title::AbstractString=""`
  keyword that labels the inserted row-index column.

## v0.2.7

### New functions

- **`ala`** — alternating location–allocation for continuous facility location.
  Locates `n` facilities among `m` weighted demand points, alternating a
  nearest-facility allocation step with a per-facility minisum location step;
  supports custom `alloc`/`locate` handles, orphaned-facility relocation, and
  best-of-`nruns` random restarts. Returns `(X, TC, W)`.
- **`dgca`** — area-adjusted great-circle distance matrix. Floors each
  `dgc` distance by `(2/3)√(aⱼ/π)`, the mean centroid-to-random-point distance of
  a disk of area `aⱼ`, capturing intra-zone access travel. Returns raw distances
  without circuity (the caller applies any circuity factor).
- **`wcentroid`** — weighted geographic centroid with a `cos(lat)` correction for
  meridian convergence. Returns a `(LON, LAT)` named tuple and composes with
  `combine(groupby(df, :k), [:LON, :LAT, :w] => wcentroid => [:LON, :LAT])`.
- **`dists` — Minkowski / Chebyshev metrics.** New `dists(X1, X2, p::Real)` method:
  `p = Inf` gives the Chebyshev (L∞) metric `maximum(abs, Δ)`; finite real `p`
  gives the Minkowski `Lₚ` metric `(Σ|Δ|ᵖ)^(1/p)`. The existing integer
  (`1`, `2`) and symbol (`:mi`, `:km`, `:rad`) methods are unchanged.

`ala`, `dgca`, and `wcentroid` are exported and documented (module docstring,
`@docs` blocks, and README Example 7 — Continuous Location).

### Breaking changes

- **Scalar transport argument order `(q, s, d)`.** The scalar forms of
  `charge_tl` and `charge_ltl` now take positional arguments in `(q, s, d)`
  order (quantity, density, distance), following the canonical `sh` field order
  and matching `rate_ltl`. Update all call sites: the old `(s, d, q)`-style
  ordering silently maps to different parameters.
- **Geocode UPPERCASE geographic fields + `ST::Symbol`.** `loc2lonlat` and
  `lonlat2loc` now return geographic fields in UPPERCASE — `LON`, `LAT`, `NAME`,
  `ST` — while metadata fields remain lowercase (`source`, `uncert`, `status`,
  `dist`, `bearing`, `dir`, `desc`). `ST` is now a `Symbol` matching
  `usplace().ST`, so `filter(r -> r.ST == res.ST, usplace())` works directly.
  DataFrame forms continue to append `GC_*` columns. Replace `r.lon`/`r.lat`/
  `r.name`/`r.st` with `r.LON`/`r.LAT`/`r.NAME`/`r.ST`.
- **`aggshmt` output shape.** `aggshmt` now returns a complete `sh` row: it
  copies `sh[1]`, sums `f`, recomputes `s` (total weight / total volume) and the
  demand-weighted `v`/`h`/`a`, and passes `d` (and all other fields) through from
  `sh[1]` — no distance averaging. The aggregated result chains directly into
  `minTLC` with no intervening `combine`.
- **`transport_costs` column names `q` / `s` / `d`.** The output column names
  `:weight` / `:density` / `:distance` are renamed to `:q` / `:s` / `:d`, aligning
  with the canonical `sh` field names.
- **Keyword-ization of `ppi` and `maxpayld`.** The `ppi` argument of the
  struct-form `rate_ltl(q, sh; ppi=...)` and `charge_ltl(q, sh; ppi=...)` is now a
  keyword with a default; `maxpayld(s; Kwt=25.0, Kcu=2750.0)` takes its capacity
  parameters as keywords with defaults matching `charge_tl`.

### Fixes (Tier 1)

- **`mincostinsert`** — the insertion loop now searches the append-after-end
  position (`for i in 1:length(rte)+1`), so a shipment can be appended to the end
  of a route; the empty-route case returns `([idx, idx], cost)`.
- **`loc2lonlat(::String)`** — a `nothing` state no longer triggers
  `MethodError(String, Nothing)`; it is treated like a missing state and falls
  through the tier hierarchy.
- **`prt`** — negative fixed-point values in `(-1, 0)` now retain their sign
  (e.g. `-0.5000`, `-0.1250`); the sign was previously lost by fixed-width
  formatting.
- **`transport_costs`** — keyword arguments are filtered to each callee
  (`charge_ltl` receives only `ppi`), and the TL (102.7) and LTL (104.2) PPI
  baselines are applied distinctly; `transport_costs(shipments; r=2.5)` no longer
  throws a `MethodError`.
- **`ufl` refinement** — `uflxchg` now returns a fresh vector (no aliasing of its
  input), so the ADD/DROP refinement branch runs and the refined total cost is no
  worse than the single-exchange result.
- **Docstring numerics** — stale example outputs in `rate_ltl`, `mincharge_ltl`,
  `charge_tl`, `charge_ltl`, `ufl`, and `d2` were re-run against the current code
  and corrected.
- **README / notebook `:gc` → `:rad`** — the `dists` great-circle-in-radians
  symbol was corrected in both the README and the example notebook, and the
  geocode-casing and argument-order changes above were synced across both with
  byte-identical code blocks.

### Packaging

- `Project.toml`: HTTP compat widened to `"1 - 2"`; version bumped to `0.2.7`.
- CI: added a weekly `schedule: cron` trigger.
- `docs/src/index.md`: `@docs` entries added for `ala`, `dgca`, `wcentroid`, and
  `rte2lines`.
