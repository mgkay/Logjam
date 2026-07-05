# Logjam Release Notes

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
