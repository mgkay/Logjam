# Logjam Release Notes

## v0.3.1

An additive release. It adds Logjam's U.S. road network, derived from FAF5 (`usrdnode`, `usrdlink`, `usrdnodemap`):
every road of FAF5 as published, each stretch of road between two junctions one link, the two carriageways of a
divided road one two-way link, each interchange and each divided-highway intersection one node with its ramps gone,
and an Interstate flag on each link, so the Interstates are a subset of one network rather than a second dataset (CR
19). It adds `joinroads`, which joins an OpenStreetMap network to it at the edge of the OpenStreetMap network's box.
And `makemap` draws its road layer from it on a map more than 150 miles across. FAF5 as published (`faf5nodes`,
`faf5links`) is unchanged. **No migration:** every call a course makes returns what it returned at v0.3.0; the
pictures of maps over 150 miles across change, and those of smaller maps only where FAF5 has ramps v0.3.0's name rule
missed.

### New

- **`usrdlink(; interstate = false, fclass = nothing, region = nothing)`, `usrdnode(...)` with the same keywords, and
  `usrdnodemap()`: Logjam's U.S. road network, derived from FAF5 (CR 19; names RD1, keywords RD2).** The network is
  made from `faf5nodes()` and `faf5links()` by `tools/v0_3_1/make_faf5net.jl` and ships as the `faf5net` lazy
  artifact (7.9 MB compressed, 29.7 MB as three CSV files), downloaded on first use like FAF5's own; each table is
  read once per session (about 2 s the first time) and each call returns a copy (about 6 ms), so a caller may change
  it freely. 145,722 nodes and 210,119 links (FAF5 as published: 344,998 and 483,530). How it is made:
  - **Ramps and junctions.** A link is a ramp by its name (a ramp, a collector-distributor lane in any of FAF5's
    spellings, a turn lane, or "X TO Y" on a one-way link with a route designation on one side) or by structure (a
    cluster of unnamed one-way links within 0.75 mi that touches two or more routes, one of them on a class 1 or 2
    link); 139,796 links. Each interchange (the ramps between two or more routes, merged into one junction within
    1.5 mi of a seed sharing two of its routes, or 0.25 mi of any) and each at-grade crossing of a divided road (its
    nodes of one route pair within 150 m) is one junction, at the member node nearest the members' center.
  - **Carriageways.** The two one-way carriageways of a route between the same two junctions are one two-way link
    when they lie within the separation of rule C (classes 0 to 2 at most 1,000 m apart at the median; classes 3 and
    up at most 100 m and a name in common; a frontage road never); a road that is genuinely one-way (a downtown
    couplet, a frontage road) stays one-way. A link keeps the node path of its shorter carriageway, so it follows the
    road's course, and a link end moved to its junction's node adds the straight-line distance moved.
  - **Columns.** Links: `osm_roads`' eight first, in its order (`SRC`, `DST`, `DIST`, `SPEED`, `FCLASS`, `DIR`,
    `NAME`, `SOURCE`, so the two kinds of table stack with `vcat`), then `SIGN` (the routes as FAF5 signs them,
    sorted and joined by `;` where the two carriageways differ), `TYPE` (Matlog's road type: `"I"`, `"U"`, `"S"`,
    `"L"`, RD4), `INTERSTATE`, `AB_TIME` and `BA_TIME` (free-flow minutes each way, each from its own carriageway,
    which `links2graph(L; weight = :time)` reads), `STFIP`, `COFIP`, `URBAN`. Nodes: `IDX` (FAF5's own node
    number, so `prune_reindex` or `thin` comes before `links2graph`), `LON`, `LAT`, `SOURCE`. The node map:
    `FAF5_IDX` (every FAF5 node once) and `IDX` (the node that stands for it; `missing` for the 310 nodes of FAF5's
    145 pieces made only of ramps).
  - **Keywords.** `interstate = true` keeps the links whose `INTERSTATE` is `true` (a sign that is exactly an
    Interstate designation, Alaska's and Hawaii's lettered ones included, or a class 1 link so named; Business
    routes not); `fclass` one functional class or a collection (`1:3`); `region = :CUS` the links with both ends
    in the continental U.S. (`CUS_LIMITS`, as `makemap` names it). `usrdnode` with the same keywords returns the
    nodes the kept links use, so the two are one network.
  - **Checked against** 4.1's Interstate files (Interstate miles without the moved ends 3.37% fewer than theirs,
    0.64% of Interstate carriageway left unpaired), road distances and times between 4.1's ten North Carolina cities
    against FAF5 as published (over 50 mi: distance 0.85% mean, time 2.25%), connectivity (26 components, FAF5's
    171 less its 145 pieces made only of ramps), and 4.1 Ex. 3's High Point to Goldsboro routes (the derived route
    within FAF5's own distance of OSRM's: 0.094 mi against 0.793, 0.061 min against 5.464) (`test/test_faf5net.jl`).
  **Lectures served:** Lecture 4.1's Interstate network (Code block 31), which the lecture ships as two CSV files its
  own script derives from FAF5, becomes `usrdnode(interstate = true, region = :CUS)` and
  `usrdlink(interstate = true, region = :CUS)` at the re-pin, and with it the thinning and Ex. 4's transshipment
  terminals (set covering with a linehaul condition); 4.1's Exs. 2 and 3, which build their graphs from FAF5 as
  published, can use it. Every number those examples quote is recomputed at the re-pin: the derived network
  collapses every interchange, not only the 754 Interstate junctions of the lecture's script, so its lower-48
  Interstates thin to 1,488 nodes and 2,109 links where the lecture's files thin to 600 and 989. **No migration.**
- **`joinroads(N, L, Nosm, Losm, bb; radius = 0.5, verbose = false)`: an OpenStreetMap network joined to the U.S.
  road network (CR 19, RD3; the name kept in the interface review, RN36).** For a route that starts or ends
  on a city's streets and runs far beyond them, as v0.2.8's `stitchnetworks` did: inside the box `bb` (the box
  given to `osm_roads`, required) the OpenStreetMap streets replace the national roads; each national link that
  crosses the box edge is joined at its node outside the box by a connector to the OpenStreetMap node nearest the
  point where it meets the edge, on a road of the same or an adjacent class (FAF5 and `osm_roads` share the FHWA
  class scale: class c joins c - 1 to c + 1, FAF5's 0 any class) within `radius` miles, else the nearest road of
  any class that continues it; one connector each way the link can be traveled; then the three sets of links are
  stacked and renumbered with `prune_reindex`. `SOURCE` marks `"FAF5"`, `"OSM"` and `"CONNECTOR"`; a connector's
  `DIST` is great-circle, its `SPEED` the slower road's, so `links2graph(dfL; weight = :time)` times it at
  `60 * DIST / SPEED`. Core, so no extension is needed: it works on the tables `osm_roads` reads. **Lecture
  served:** Lecture 4.2's OpenStreetMap networks; no lecture calls it yet, and `test/test_joinroads.jl` joins
  4.2's committed Raleigh tile to the network and routes from inside it to Greensboro (leaving on I-40) and to
  Winston-Salem. **No migration.**
- **`Logjam.poissoncdf(j, μ)`, `Logjam.pi0` and `Logjam.qbar` with two methods each, and
  `Logjam.poissarr(lmb, n = 1; rng)`: the Poisson inventory measures of Lecture 6.2 and the arrival process of
  Lecture 6.3, public and not exported (E1, D10).** `poissoncdf` is ``F(j; μ)``, the probability of `j` or fewer
  demands during a lead time when that demand is Poisson with mean `μ`, summed one term at a time, each probability
  from the one before it. `pi0(qmax, μ)` and `qbar(qmax, μ)` are a base-stock system's fraction of demand out of
  stock, ``1 - F(q_{\max} - 1; μ)``, and average on hand, the sum of ``F(j; μ)`` for `j` from 0 to `qmax - 1`;
  `pi0(qo, qmin, μ)` and `qbar(qo, qmin, μ)`, 6.2's `pi0rp` and `qbarrp` as methods of the same names, are a
  reorder-point system's, base stock's averaged over the levels `qmin + 1` to `qmin + qo`. `poissarr` returns
  the arrival times of a Poisson process whose rate `lmb[i]` may differ from period to period, generated at the
  peak rate and thinned, every draw taken from `rng` (the global stream by default). Each body is the lecture's
  definition in its order of operations, so each returns exactly what the lecture's does, `poissarr` after the same
  seed. Specification: the ISE 453 F25 spreadsheet `Inventory.xlsx`, whose [BS Pois] and [RP Pois] cells the
  measures reproduce to a relative 1e-12 (the reorder-point sheet tabulates the cycle forms, which 6.2's model
  replaces by the averages), and the MATLAB `poissarr.m`, whose arrivals `poissarr` reproduces on the same draws
  (`test/test_invtools.jl`, `tools/v0_3_1/make_oracles_v031.m`). **Lectures served:** 6.2 and 6.3, which define
  them inline today (6.3 repeating 6.2's measures) and may call Logjam's at the re-pin; not exported, so a
  lecture's own definitions, made after `using Logjam`, do not collide. **No migration.**
- **`maxpayld(s::AbstractVector, tr)` and `maxpayld(sh::AbstractDataFrame, tr)`: the maximum payload of each
  shipment, from its densities or from its table (B6).** Element `i` is the scalar rule at `s[i]` on the truck's
  `Kwt` and `Kcu`, read as the row form `maxpayld(sh, tr)` reads them, so the table form returns exactly what
  `[maxpayld(row, tr) for row in eachrow(sh)]` does. Each density is computed on its own, so a range of densities
  gives the scalar rule's value at each one; the keyword form `maxpayld(s; Kwt, Kcu)`, unchanged, does a range's own
  arithmetic, which differs in the last place at 61 of the 500 densities from 0.1 to 50 in steps of 0.1 on a truck
  of 25 tons and 2,750 ft³. **Lectures served:**
  3.3 Code block 13, 3.4 Code blocks 2, 14, 21, 22 and 24, which write that comprehension, and 5.3 Code block 41's
  `maxpayld.(eachrow(sho), Ref(tro))`, which can call `maxpayld(sh, tr)` at the re-pin. **No migration.**
- **`minTLC(sh::AbstractDataFrame, tr, ppi_ltl)`, and its keyword form: the minimum-TLC shipment of every row of a
  table (B6).** It returns a new table, `sh`'s columns unchanged and in their order with `qᵒ`, `TLCᵒ` and `isLTL`
  added, each row's values those of the row form `minTLC(row, tr, ppi_ltl)`; `sh` itself is not changed. Every call
  mode of the row form works (TL only, LTL only, both; positional or keyword), and a `qᵒ`, `TLCᵒ` or `isLTL` column
  already there is replaced in its place. A table given to `minTLC` was an error before, so no call changes.
  **Lectures served:** 3.3 Code block 13 and 3.4 Code blocks 21 and 22, which add the three columns with
  `transform!(sh, AsTable(:) => ByRow(r -> minTLC(r, tr, ppiLTL)) => AsTable)`, and the homework keys' row-by-row
  calls, can call it at the re-pin. **No migration.**
- **`charge_tl(d::Real, tr)`: the charge of one truckload over `d` miles (B9).** `max(r·d, MC_TL)`, with `r` read
  from `tr.r` or, when `tr` has none, derived from `tr.ppi` as the shipment form derives it (D5), and the minimum
  `mincharge_tl(tr)`. It is the shipment form `charge_tl(q, s, d; ...)` whenever `q` fills at most one truck and
  `d` is at least `1e-4` mi; it has no zero rule, so at `d = 0` it is the minimum charge, where the shipment form
  charges nothing (N4, TRN3). Distinct from the existing methods by arity, so no existing call changes method.
  **Lectures served:** 5.2's Ex. 9, whose independent and route charges are written `max.(2.00 .* dL,
  mincharge_tl())` and `max(2.00 * rteTC(rte, shL, D30), mincharge_tl())` (Code blocks 50 and 52), and 4.3 Code
  block 31, which charges one truck with `charge_tl(qmax, s, d; r, Kwt, Kcu, ppi)`; 3.3 keeps the formula, since
  there it is the lesson. **No migration.**
- **`ala(X0, alloc, P)`, `ala(n, w, P)` and `ala(x, w, P)`: `ala`'s call forms (A7).** A caller's allocate function
  in the place of `w`, as Matlog's `ala(X0, alloc_h, P, p)` takes it, is `ala(X0, w, P; alloc)`, whose `w` only the
  default allocate reads. An integer `n` for the start is `ala(randX(P, n; rng), w, P; rng)`: the generator, or with
  none the global stream, draws the start and then the restarts and the repair, so after the same seed it returns
  exactly what the course's `ala(randX(P, n), w, P)` returns, and an `rng` is passed once. A vector `x` is one NF from
  that point, `ala(reshape(x, 1, :), w, P)`. `ala(n, alloc, P)` and `ala(x, alloc, P)` combine them. Each was an
  error before (a function has no `length`; a number or a vector is not a matrix), no existing call changes method,
  and `Test.detect_ambiguities` finds none. **Lectures served:** 2.3's Code block 16, which passes `w` beside
  `alloc36`, a function that already holds it, and 3.4's Code block 30, which passes `ones(size(P3, 1))` beside
  `alloc_h`: `ala(randX(P, 2), alloc36, P; nruns = 5)`, and `ala(n, alloc_h, P3; nruns = 5)`, since `P3` is `CXY3`
  twice and so has its box; 2.3's Code blocks 14 and 19, 2.4's Code block 24 and the HW 1 key's Q6(b), which write
  `ala(randX(P, n), w, P; ...)`; the HW 1 key's Q6(a), `ala(reshape(xyRR, 1, 2), w, P)`. Each is `==` to the call
  as written, on its own inputs (`test/test_location_v031.jl`). **No migration.**
- **`ala(...; dist = p)` for any real `p ≥ 1`, and `ala(...; unit)` (A5).** `ala` reads its metric as `dists` does:
  any metric `dists` accepts, where its locate step took only 1, 2, Inf and the great-circle units (`dist = 3` was
  an error), and `unit` as the synonym of `dist` for a great-circle unit (S15; both at once is an error). Every
  metric that worked locates exactly as before, the real 1.0 and 2.0 included (their allocate step is `dists`'
  general metric and their locate step d1's and d2's arithmetic, as at v0.3.0). **Lecture served:** none calls it;
  it makes `ala` take what `dists` takes. **No migration.**
- **`dgca(x, Xa, a)`: the area-adjusted distances of one point (A5).** For a vector `x` it returns the vector of
  the matrix method's row, `vec(dgca(reshape(x, 1, :), Xa, a))`, as `dists(x, X2)` does (S15). **Lecture served:**
  2.6's Code block 17, which measures each ZIP code from its plant with `dgca(XDC[i:i, :], XZ[j:j, :], [a])[1]`, can
  write `XDC[i, :]`. **No migration.**
- **`wcentroid(P, w)`: the weighted centroid of an n×2 matrix of points (A8).** It is `wcentroid(P[:, 1], P[:, 2],
  w)`, the form the distance and location functions take their points in. **Lectures served:** 2.2's Code block 32
  and 2.6's Code block 3, `c0 = wcentroid(P[:, 1], P[:, 2], wTL)`. **No migration.**
- **`uflxchg(k, C, y)` takes any vector of integers (A8).** A range (`1:3`), `Int32` or a view, as `ufladd` and
  `ufldrop` take their `y`; `uflxchg(k, C, 2:3)` was a `MethodError`. The signature is widened in place, so a
  `Vector{Int}` runs the same method as before. **Lecture served:** none passes a range today (2.4's Code block 11
  passes ADD's set); it aligns `uflxchg` with its two siblings, which a set written as `1:3` reached and it did not.
  **No migration.**
- **`lonlat2loc(xy)` names a point against `usplace()`, and `lonlat2loc` and `loc2lonlat` take any table (A8).**
  With no table `lonlat2loc(xy)` and `lonlat2loc(XY)` read `usplace()`, a positional default (ruling WP3-3), returning what
  `lonlat2loc(xy, usplace())` returns. `lonlat2loc(xy, df)` and `loc2lonlat(df)` take an `AbstractDataFrame`, so a
  view such as `view(usplace(), mask, :)` works where a `DataFrame` was required, with the answer of the table it
  shows; `loc2lonlat` returns a new `DataFrame` either way (`prt` already took one). **Lectures served:** 2.2's Code
  block 32, 2.5's Code blocks 5 and 32 and 2.6's Code blocks 3 and 12, which pass `usplace()`. **No migration.**
- **`loc2lonlat(df; street_col, city_col, state_col, postalcode_col, county_col)`: the DataFrame method's column
  keywords end in `_col` (A6; the names provisional, D7).** They name the columns that hold each part of an address,
  as `lonlat2loc`'s and the road functions' `*_col` keywords do, by default `STREET`, `CITY`, `STATE`, `POSTALCODE`
  and `COUNTY`, and a string names a column as a `Symbol` does. **Deprecated:** the old names `street`, `city`,
  `state`, `postalcode` and `county` still work, with the same result, and call `Base.depwarn` naming the new one,
  which prints only when Julia runs with `--depwarn=yes` (as `Pkg.test` does), so a script's output is unchanged;
  passing a keyword by both names is an `ArgumentError`. They were renamed because `state` named a column here and is
  a state in the string and vector methods. **A state column that is named and is not in the table is now an
  `ArgumentError`** that says so and points to `state_col`: `loc2lonlat(DataFrame(CITY = ["Athens", "Portland",
  "Jacksonville"]); state = :GA)` read `:GA` as a column and returned `FAIL` for every row, with no warning (review
  A's measurement). No call in `src/`, the lectures or the released HW 1 to 5 keys passes `state` to the DataFrame
  method (all of theirs pass it to the string or vector method, whose `state` is unchanged), and a table with no
  state column and no `state` keyword geocodes as before. **Lecture served:** none calls the DataFrame method with
  these keywords; the names align the geocoder with the package's other column keywords. **No migration.**
- **`loc2lonlat(v)` takes any vector of strings (A4).** A view, a vector of `SubString`s or a column read from a file
  that is not a `Vector`, where a `Vector` was required (a `MethodError` otherwise); the result is the table the
  `Vector` of the same strings gives, its `INPUT` column a `Vector`. **No migration.**
- **`STFIP` on `uszcta5()` and `uszcta3()`: the state of each ZIP Code Tabulation Area (D4).** Appended as the last
  column, an `Int64` as `usplace().STFIP` is, so every column before it keeps its name, place, type and values (D2's
  reading of an appended column). A ZCTA5 takes the state holding the largest share of its land, its county parts'
  land in the U.S. Census Bureau's 2020 ZCTA to County Relationship File summed by state (a county's state the first
  two digits of its GEOID); one with no land the state with the most water, a tie the smaller FIPS code (the file has
  neither). 137 of the 33,682 ZCTA5s cross a state line, as 02861 (Rhode Island 99.54%, Massachusetts 0.46%) and
  56144 (Minnesota 86.86%, South Dakota 13.14%) do; Puerto Rico's 40 are 72. A ZCTA3 takes the state holding the most
  land over its ZCTA5s' county parts; 91 of the 890 have ZCTA5s in more than one state, and counting each ZCTA5
  wholly in its own state gives the same answer for each. Made by `tools/v0_3_1/make_zcta_stfip.jl` (the file's URL,
  vintage and SHA-256 in its header), byte-identical on regeneration (`uszcta5.csv` `fee98453…`, `uszcta3.csv`
  `7c60ed0f…`; the `.jls` is the CSV read back); `test/test_geodata_v031.jl` checks the old columns against
  v0.3.0's files and recomputes every cross-state and three-digit state from the committed extract
  `test/data/zcta_state_parts.csv`. **Lectures served:** 2.5's Code blocks 3 and 15 select North Carolina's ZIP
  codes by their codes' range (`27000 <= ZCTA5 <= 28999`, `270 <= ZCTA3 <= 289`); `STFIP == 37` selects them by the
  state that holds them. Code that checks the tables' exact columns, or that `ISCUS` is last, sees the new column, as
  four checks in v0.3.0's own `test/test_datatools.jl` do. **No migration** for code that reads columns by name.
- **`mapbbox(name; state, place = false)`: the box of a city, town or census-designated place, offline (X7, MakePlan
  D3; `place` provisional, D7).** A name that matches a county of the state still gives the county's box, exactly as
  before (every county of `uscounty()` gives the box it gave, bit for bit, or the same error); a name that matches no
  county, which was an `ArgumentError`, now gives the box of the place of that name, and `place = true` asks for the
  place where a county has the name too: `mapbbox("Durham"; state = :NC)` is Durham County, and with `place = true`
  the city of Durham. A place's box is the extent of its Census 2020 polygon, the bounding box the TIGER/Line 2020
  place shapefile records, kept for each of the 31,617 places of `usplace()` in `data/usplacebox` (1.9 MB as CSV); it
  contains the place's `usplace()` point, and Raleigh's is within 0.0005 degrees of Nominatim's on every side. A place
  is matched by its name as `usplace()` writes it, ignoring case (`"Raleigh"`, `"Durham CDP"`), and failing that
  without its designator (`"Raleigh city"`, `"Durham"` for Durham CDP); a name two places of the state share is an
  `ArgumentError` naming both, with their `PLFIP`s. `xexpand` and `yexpand` widen it as they widen a county's.
  **Served:** a map of a city with no network call, `makemap(mapbbox("Raleigh"; state = :NC))`, and the box
  `osm_roads` downloads a city's streets for; until now a city's box came only from Nominatim's `boundingbox` (CR 28).
  **No migration.**
- **`mapbbox(state::Symbol)`: the box of a state (X7, "at no cost"; the form provisional, D7).** The extent of the
  boxes of its counties, each built as `mapbbox(county; state)` builds it from the Census block groups, so it contains
  every one of them and needs no new data; the state as its two-letter `Symbol` (`:NC`), one of the 50 states or the
  District of Columbia (a territory, which `usstate()` does not hold, is an `ArgumentError`). `xexpand` and `yexpand`
  as for any box. **Served:** a map of a state, `makemap(mapbbox(:NC))`; Lecture 4.2's Code block 3 notes that the box
  around a county or a state can be computed from the block groups, which this does for a state. **No migration.**
- **`dgca(X, Xa, a; method = :empirical)`: Lecture 2.5's empirical average distance to a region (X8, MakePlan D8;
  `method` and its values provisional, D7).** With `r = √(a/π)` and `d` the great-circle distance, `d < r` gives
  `2r/3 + d/48 + 9d²/(20r)` and any other `d` gives `d + 3r²/(23d)`: 2.5's `@eq-daemp`, the average distance from a
  point to the points of a region taken as a disk of its area, fitted by regression to simulated data. It is `2r/3`
  at the region's centroid, as the default's floor is, and more than `d` outside the region. The branch test is
  `d < r`, as MATLAB's `ise754/dagg.m` draws it, so at `d = r` the value is `26r/23`, a step of about 0.6% down from
  its limit `546r/480 = 1.1375r` just below, which belongs to the fitted formula; a zero area gives `d`. The default,
  `method = :max`, is 2.5's `@eq-da2dmax`, `max{d, (2/3)r}`, unchanged bit for bit; both of `dgca`'s methods (the
  matrix one and the one-point one) take the keyword. Checked against 2.5's equation copied as text on its Example 4
  and 5 inputs (`==`), and against `dagg.m` run in MATLAB R2025a on the same distances (`test/oracles/dagg_matlab.csv`,
  `tools/v0_3_1/make_oracles_v031.m`; 30 of 2.5's areas, `d/r` from 0 to 4): equal bit for bit wherever `dagg.m`
  applies one case. For `d/r` from 0.838 to 1 `dagg.m` applies both, because its second statement tests the matrix
  its first has already changed, and returns 10% to 13% more; Logjam follows 2.5's equation there.
  **Lecture served:** 2.5, which gives `@eq-daemp` "for the occasions that warrant it" and runs `@eq-da2dmax` with
  `dgca` (Code blocks 17 and 20); `dgca(P, P, z.ALAND; method = :empirical)` runs the equation. **No migration.**
- **`twoopt(...; verbose = false)` and `mincostinsert(...; verbose = false)`: the trace of what each procedure tries
  (E2, refactor E's R2, Matlog's `dodisp`; the keyword provisional, D7).** With `verbose = true`, `twoopt` prints its
  start as `*TC: r`, then every vector it considers, in the order considered, as ` TC: r′` for a change it does not
  keep and `*TC: r′` for one it keeps, each with the cost the handle returned; `mincostinsert` prints every route it
  tries as `i,j: route = TC`, the positions of the pickup and the delivery. The lines are printed with `println` by
  the loop that finds the result, so the trace is Logjam's own search and not a copy of it. Every `twoopt` method
  takes the keyword: the cost-handle method, for a tour or a route (a reversal that empties the truck is not
  considered, so not printed); the matrix method `twoopt(π, C)`, which still decides by the delta and, for the trace
  only, builds each tour it considers and prints its whole cost, `sum(segcost(π′, C))`, as the handle form would;
  and the two methods for a vector of routes, which print each route's trace in turn. Into an empty route
  `mincostinsert` places `[k, k]` outside its loops and prints nothing, as the lecture's function prints nothing
  there. A route's order of ties (CR 58) is applied after the search, so the route returned can differ from the
  last starred line by the order of two tied shipments. The default, `false`, prints and builds nothing and returns
  exactly what v0.3.0 returned, and `true` returns the same values (`test/test_routing_v031.jl` holds both against
  v0.3.0's bodies, copied as text). On the lectures' inputs the output is the lectures' byte for byte, their
  definitions run as text: Lecture 5.1 Ex. 3's 20 lines from `twoopt(π, πTCh; verbose = true)` and from
  `twoopt(π, D; verbose = true)`; Lecture 5.2 Ex. 1's 4 and 13 routes from its two insertions, and the whole cell's
  21 lines with its `@show`s. Matlog's `twoopt.m` and `mincostinsert.m` print other traces by design, since v0.3.0
  ruled Logjam's 2-opt the lecture's (K7a) and its insertion the F24 loop (CR 38). **Lectures served:** 5.1 Code
  block 15 (`twoopt_prt`) and 5.2 Code block 17 (`mincostinsert_prt`), whose own printing definitions it can
  replace at the re-pin with `twoopt(π, πTCh; verbose = true)` and `mincostinsert(2, [1, 1], rTD1h; verbose =
  true)`; whether the lectures keep their printing versions is a decision about their shape. **No migration.**
- **`Logjam.TSP(c)` and `Logjam.subtours(succ)`: Lecture 5.1's TSP formulation, solved one round of subtour
  constraints at a time, and the cycles of a successor vector (CR 45; `TSP`'s name provisional, D7).** `TSP` builds
  the DFJ formulation on the arc costs `c` (a binary `x[i, j]` for each arc `i ≠ j`, each node left once and entered
  once), solves the assignment problem those rows make with HiGHS (silent, `mip_rel_gap = 0`, so the tour is proved
  optimal), finds the solution's cycles with `subtours`, adds the single-tour constraint for each, and solves again
  until the solution is one tour. It returns `(; TC, tour, rounds)`, the names 5.1 reads: the optimal cost, the tour
  as a location sequence from node 1, and each round's `(; TC, S)`. Each body is the lecture's in its order; `TSP`
  throws an `ArgumentError` for a matrix that is not square (the lecture's `error`) or has fewer than two nodes (on
  which the lecture's loop would not end), and its `rounds` is a typed vector where the lecture's is `[]`. `TSP`'s
  method is the optimization extension's, `LogjamJuMPExt`, which JuMP and HiGHS load together; called without them
  it is a `MethodError` whose hint says `using JuMP, HiGHS`. `subtours` needs neither and is core's. Checked against
  5.1's definitions run as text (`test/test_jump_ext.jl`): `subtours` `==` on all 5,914 permutations of up to seven
  nodes; `TSP`'s cost to a relative 1e-9, its tour (up to rotation and reversal) and every round's subtours equal on
  5.1's Ex. 2 (ten cities, 487.69 mi), Ex. 3(d), Ex. 4(c)'s 100 counties and Code block 24's random instances to
  `m = 20` (and the first two of `m = 50`), and on 5.3's 31 points against its copy (1,131.60 mi). **Lectures
  served:** 5.1 (Sec. 2's implementation rung, its Exs. 2 to 4) and 5.3 (Code blocks 9 and 10), which define both
  inline and may call Logjam's at the re-pin; not exported, so a lecture's own definitions, made after `using
  Logjam`, do not collide (D10). **No migration.**
- **`Logjam.binpack(v, V; tlim = 60.0, gap = 1e-4)`: Lecture 2.7's bin packing model (E3; the name and keywords
  provisional, D7).** A binary for each bin and for each object-bin pair, one potential bin for each object;
  minimize the bins used subject to each bin's capacity and each object in exactly one bin; HiGHS, silent, with the
  time limit `tlim` and the relative gap `gap`. It returns 2.7's `(; bins, used, status, gap, secs)`. The body is the
  lecture's in its order, with an `ArgumentError` for an object larger than a bin (the model's assumption (b), where
  the lecture's call throws from `value`). Its method is `LogjamJuMPExt`'s, with the same hint. Checked against 2.7's
  definition and 5.3's copy run as text: the bin count `==`, every object in exactly one bin, no bin over its
  capacity, and the packing itself equal, on 2.7's Ex. 8 (6 bins), Code block 28's 20 to 200 objects and Code block
  29's 2% gap, and 5.3's Ex. 6 route times (4 trucks; the times as @tbl-ffd-steps prints them, to two decimals).
  **Lectures served:** 2.7 (Sec. 4's implementation rung, Ex. 8, Code blocks 28 and 29) and 5.3 (Code blocks 48 and
  49), which define it inline; not exported (D10). **No migration.**
- **`snapvals(x)` on JuMP variables (SV, X3).** With JuMP and HiGHS loaded, `snapvals` takes an array of a solved
  model's variables, `snapvals(x)` being `snapvals(value.(x))`, as ISE 361 F25 calls it, and one variable, whose
  value it returns snapped, a `Float64` (`value.(x)` of one variable is a number, which the numeric method, calling
  `Array`, does not take). The numeric method is unchanged. Checked `==` against `snapvals(value.(x))` on Lecture
  4.3's production-inventory model (ISE 361 F25's 5-MIP-4 cell 16) on its Ex. 3, Lecture 2.7's Code block 2 and its
  bin packing model, a `DenseAxisArray`, and variables fixed at the numeric method's own pinned values; a
  `SparseAxisArray` (the TSP's `x`) is refused by both alike, its values having no `size`. **Lectures served:**
  every lecture that solves a JuMP model (2.7, 4.1 to 4.4, 5.3), whose `snapvals(value.(x))` keeps working; each
  lecture chooses at the re-pin whether `value.` stays visible (X3). **No migration.**

### Changed

- **`makemap`'s road layer is drawn in three tiers, from FAF5 and the derived network (CR 19, ruling Q2;
  rulings RN23 to RN28).** `roads = :auto` draws, by the size of the map as drawn (after `xexpand` and `yexpand`),
  each tier cropped to the map in `:steelblue`:
  1. **Close, 150 miles across or less** (the larger of the box's north-south and east-west great-circle extents
     through its center, tested first): FAF5's own links, every class (`FCLASS` 1 to 5 as `plotroads!` groups them)
     at widths 1.4, 1.0, 0.7, 0.5 and 0.3 and opacity 0.3, labeled "FAF5 Roads", as at v0.3.0, but with every link
     the network's ramp rule (`Logjam._ramp_links`) calls a ramp left out (139,796 links, where v0.3.0 left out the
     137,156 named ramps): the "X TO Y" ramps, the misspelled collector-distributor lanes and the unnamed clusters at
     interchanges no longer draw (RN23). The derived network was tried here and not kept: it draws each collapsed
     interchange as a star of straight stubs.
  2. **Regional, up to 10 degrees of latitude:** the derived network's classes 1 to 3 (Interstates, other freeways
     and expressways, other principal arterials), labeled "Major Roads" (RN26), the Interstate at opacity 0.32 and
     width 0.7, classes 2 and 3 at 0.3 and 0.15 of its width beneath it, one hue (RN24, RN27).
  3. **National, up to 30 degrees:** the derived network's Interstates (`INTERSTATE`), labeled "Interstate Roads",
     at opacity 0.32 and width 0.85 up to 20 degrees, 0.3 and 0.8 up to 30 (RN24, RN25, RN27).
  4. **None** above 30 degrees, as before; `region = :World` and `:US` draw none, `:CUS` the national tier.
  Tiers 2 and 3 replace v0.3.0's Interstate layer, which drew FAF5's 82,323 Interstate polylines, both carriageways,
  whatever the map's place: one line now stands for a divided road, and its width and opacity are set so that the
  Interstates carry 0.93 to 0.97 of v0.3.0's ink (measured on five maps). `roads = (; color, alpha, linewidth)`
  restyles whichever tier is drawn: `color` the hue, `alpha` the opacity of every class, `linewidth` the
  Interstate's width, the other classes keeping their ratios to it (on the regional tier 0.3 and 0.15).
  `layers.roads` keeps its shapes: a `NamedTuple` of five `Lines` (`class1` to `class5`) on the close tier, one
  `Lines` on the regional tier (with a width for each point, its class's) and on the national tier. **The first
  close-tier map in a session takes 1.6 to 1.9 s longer** (the ramp rule over FAF5's 483,530 links, computed once;
  RN28); a map after it about 9 ms. **Pins moved,** each listed with its reason in its file's moved-cases dict and
  pinned anew in `test/test_map_tiers.jl`: `test/test_map_pins.jl` 8 (`MMPIN_MOVED`), `test/test_map_k11c_pins.jl`
  10 (`K11CPIN_MOVED`), `test/test_map_line_pins.jl` 11 (`MLPIN_MOVED`), 29 cases: 22 under "N4" (the tiers: the
  road layer's point count, and the 20-to-30-degree step's opacity 0.3, not 0.35), 20 under "N4b (RN26)" (the
  regional label) and all 29 under "N4b (RN24)" (the Interstate's opacity and width). No other pin moved.
  **Course figures that change:** every course map over 150 miles across with the default road layer, the call
  shapes pinned in `test/test_map_k11c_pins.jl` (Lectures 2.2, 2.3 and its High Point to Goldsboro generator, 2.6,
  2.7, 4.2, 5.1 to 5.3); and, only where FAF5 has ramps the name rule missed, a map 150 miles across or less (of the
  course's, Lecture 2.7's clinics map is the one at that scale with the default road layer). **No migration.**
- **The ZIP tables' docstrings say which territories they hold (X6).** `uszcta5()` and `uszcta3()` said they held no
  U.S. territory; they hold Puerto Rico's 40 ZCTA5s whose codes begin with 009 (`ZCTA5` 901 to 987) and its ZCTA3
  `9`, with `ISCUS = false`, and none of its 006xx and 007xx ZCTA5s. The docstrings now say so; no data changed.
- **Every example in `src/routetools.jl` shows its output and runs as a doctest (DOC, verifier issue 4).** The
  examples of `segcost`, `isorigin`, `rte2loc`, `twoopt` (the cost-handle and matrix methods), `mincostinsert`,
  `pairwisesavings` and `savings` gave their output in a comment, or `twoopt`'s not at all, and nothing ran them;
  each is now a `jldoctest` whose output is the function's own, checked on every test run (`test/test_doctests.jl`)
  and in the manual's build. Each keeps its example's data and calls. `twoopt(π, C)`'s no longer assigns to `π`,
  `pairwisesavings`' comment that `ijs.s` and `ijs[3]` are the destructured `sˢ` is now a line that runs, and
  `twoopt`'s and `mincostinsert`'s each add a `verbose = true` call, `twoopt(π, C)`'s printing Lecture 5.1's trace.
  The conversion changes no function.

### Internal

- **One ramp rule, in core (D2, RN23).** `Logjam._ramp_links(N, L)` decides what a ramp is for the derivation and
  for the map's close tier alike; the map extension's own name filter (`_RAMP_NAME`, `_isramp`) is retired.
- **`faf5interstateroads()` and `data/faf5_interstate_roads.jls` (3.95 MB) are retired (N4).** The internal
  function was the map's Interstate layer, which the derived network now draws. v0.3.0's Migration table pointed
  scripts that called the removed `faf5interstate()` at `Logjam.faf5interstateroads()`; its replacement is
  `usrdnode(interstate = true)` and `usrdlink(interstate = true)` (with `region = :CUS` for the lower 48).
- **The derivation is a committed script with byte-reproducible output (D7).** `tools/v0_3_1/make_faf5net.jl`
  runs the derivation (`Logjam._faf5net`, `src/faf5net.jl`) on `faf5nodes()` and `faf5links()`, writes the three
  CSV files and packs them as `faf5net.tar.gz` (sorted keys, four decimals for `DIST` and the times, LF endings, no
  time stamps); SHA-256 equal on Julia 1.12.6 and 1.13.4 (tarball `28604d8a…`, git-tree-sha1 `df2473c5…`). It
  takes about 9 s after FAF5's tables are read. The tarball is the `data-faf5net-v1` release asset that
  `Artifacts.toml`'s `[faf5net]` entry names.
- **CI rebuilds a small extract (SC 1, T1.3).** `test/fixtures/faf5net_raleigh/` holds FAF5 cut to a box around
  Raleigh and the network the derivation makes of it (`tools/v0_3_1/make_faf5net_fixture.jl`); the suite derives
  it again and compares the three files byte for byte. `.gitattributes` checks them out with LF endings.
- **The version reads `0.3.1-DEV`** until the release.
- **Dependencies (X2).** PrecompileTools is a dependency (the precompile workloads). JuMP and HiGHS together, and
  Makie, are weak dependencies, each loading an extension (`LogjamJuMPExt`, `LogjamMakieExt`) only when a script
  loads them; a script that loads none of them gets nothing new. All four are already in the course's environment
  (JuMP 1.31, HiGHS 1.25, Makie 0.24, PrecompileTools 1.3), and the compat bounds admit those versions, so the re-pin
  brings no new package.
- **The LTL estimate's domain, named once (B10).** `_LTL_MIN_WEIGHT` (150/2000 ton), `_LTL_MAX_WEIGHT` (5.0 ton),
  `_LTL_MAX_CUBE` (650 ft³), `_LTL_MIN_DIST` (37 mi) and `_LTL_MAX_DIST` (3354 mi) replace their literals in
  `rate_ltl`, `qmax_ltl`, `mincharge_ltl` and `minTLC`, each with its literal's value and type. `totlogcost(q, c,
  sh)` reads an aggregate's `avh` through `_avh`, and without one keeps its order of multiplication, `q·a·v·h`;
  the TL rate derived from the index is one expression (`_tlrate`) for both `charge_tl` methods that derive it, and
  `minTLC`'s check that the carrier and the LTL index are not given twice is one function for its row and table
  forms. No value moves: `test/test_transtools_v031.jl` compares v0.3.0's bodies, copied as text, with the new ones
  bit for bit, and every transport pin and oracle holds.
- **The `sh` and `tr` contract is `?Logjam.shtr` (B11).** The contract was a bare string at the top of
  `transtools.jl`, which `?` could not show; it is now the docstring of `Logjam.shtr`, public and not exported,
  whose value lists the fields of each (`shtr.sh`, `shtr.tr`). It now says that a function of one shipment takes a
  row, and `maxpayld` and `minTLC` the table too (B6); that a function of a set of shipments takes the table; and
  that a field a function reads is used when present, an absent one takes the default the function documents (the
  scalar method's or Matlog's), and one with no default is required. The manual's section shows the docstring in
  place of its own copy of the tables.
- **One metric kernel for `dists`, `ala`'s locate step and `dgca` (A5).** `Logjam._pointdist(x, y, metric)` is the
  distance between two points under a metric resolved once per call (`_L1`, `_L2`, `_Lp`, `_Linf`, `_GC`), with
  no check and no allocation per pair; the caller checks the shapes once, raising the error the first pair raised
  before. `_dists` uses it, `ala`'s locate step uses it in place of `_aladist` (retired), and `dgca` and
  `lonlat2loc` reach it through `dists`; `dgc` shares its great-circle arithmetic (`_haversine`) and its unit
  check no longer builds a vector. Each metric keeps its arithmetic operation for operation (d1's and d2's per-pair
  `sum` and the lₚ and Chebychev reductions run left to right below 16 coordinates, as Base's `sum` and `maximum`
  do there, and from 16 the old expression itself runs), and a point set against one of another dimension still
  broadcasts under the general metric as before. **Bit-identical:** `tools/v0_3_1/kernel_identity.jl` saved the
  outputs of `dists` (every metric: 1, 2, integer 3, the real 1.0, 2.0, 1.5 and 3.0, Inf, `:mi`, `:km`, `:rad`, and
  `unit`), `dgc`, `dgca` and `ala` (a fixed allocation, so every step after the first is the locate step, and the
  default allocate on seeded starts, under every metric it took) at 9b72994, on the distance pins' and the Matlog
  oracles' inputs, Lecture 2.3's I-40 and Carolinas examples, and seeded sets up to 3000 points; after the kernel,
  all 333 cases, 40,784,366 elements, are `===` on Julia 1.12.6 and on 1.13.4, and `test/test_location_v031.jl`
  compares v0.3.0's bodies, copied as text, bit for bit. **Time** of `dists` on 3000 points against 3000 (fastest
  of three, 1.12.6): Euclidean 0.38 s and 755 MiB to 0.022 s and 69 MiB (the result itself), rectilinear 0.24 s to
  0.024 s, Chebychev 0.23 s to 0.024 s, l₃ 0.71 s and 1.4 GiB to 0.15 s, great circle 0.58 s and 481 MiB to 0.28 s
  (reported, not asserted).
- **One batch driver behind `loc2lonlat`'s vector and DataFrame methods (A4).** `Logjam._geocode_batch!` holds what
  the two methods wrote twice: the five result columns, the progress line every 50 rows, the cache read once and
  flushed once in `try`/`finally`, and the columns appended to the result. A geocoded row is written once, as
  `_FAIL` (not found) or `_row(result, status)` (a census-table answer), in place of eight hand-written named
  tuples. (The one tier ladder of review A's A4 was built in v0.3.0's K14.) No value moves:
  `test/test_geodata_v031.jl` runs v0.3.0's geocoder, copied as text, beside the new one on the same inputs (cities,
  ZIP codes, addresses with the address tier stood in for, bad states, empty and 60-row inputs, views) and compares
  the tables column for column, the log records and the cache files written.
- **One memoized loader for the census tables, and a name index for the geocoder (A10).** `Logjam._table(name)`
  reads each census table's `.jls` once per session and keeps it; `usplace()`, `uscounty()`, `uscentract()`,
  `uscenblkgrp()`, `uszcta5()`, `uszcta3()`, `uscbsa()` and `uscsa()` return a copy of it, as `usstate()` and the
  FAF5 loaders already did, so a caller may change what it gets and the next call is not changed (each docstring
  says so). The geocoder's place, ZIP code, county and state tiers read the kept table itself, and the place and
  county tiers look a name up in `Logjam._NameIndex`, the table's names normalized once with their rows by name and
  by state: the same exact, prefix and substring phases over the same rows in the same order, so the same row or the
  same error as v0.3.0's scan, which re-read `usplace()` and re-normalized its 31,617 names on every row.
  `test/test_geodata_v031.jl` checks every name of `usplace()` and `uscounty()`, with its state and with none, and
  200 variants (case, accents, spacing, designators, prefixes, parts, wrong states) against that scan, and that a
  changed copy does not reach the next call. **Time per lookup** (fastest of five, Julia 1.12.6, reported, not
  asserted): `_resolve_place("Raleigh", :NC)` 59.6 ms to 0.002 ms, a name not found in its state 64.8 ms to 0.046
  ms, an ambiguous name with no state 57.6 ms to 0.011 ms, `_resolve_county("Wake", :NC)` 3.7 ms to 0.001 ms,
  `loc2lonlat` of 20 North Carolina cities 61 ms to 0.005 ms a row, `usplace()` 9.0 ms to 0.74 ms (a copy, not a
  read); the first place lookup in a session reads the table (about 0.13 s) and builds its index (about 0.25 s,
  with compilation).
- **`src/datatools.jl` is split by content into three files (A10).** `datatools.jl` keeps the census and FAF5
  tables, their loader and the FIPS codes; `displaytools.jl` takes the display functions (`prt`, `thousands`,
  `snapvals` and their helpers); `geomtools.jl` takes the geometry for drawing (`alloclines`). Text moved, not
  changed: the three files' code lines, in order, are the old file's, and the suite's count is the same before and
  after.
- **The place boxes are a committed derivation with byte-reproducible output (D3).** `tools/v0_3_1/make_placebox.jl`
  reads the U.S. Census Bureau's TIGER/Line 2020 place shapefiles (one per state, the District of Columbia and Puerto
  Rico; each zip's URL, size and SHA-256 in its header, and each unpacked `.shp` and `.dbf` checked by size and
  SHA-256 before it is read) with Base Julia alone: each polygon's bounding box from its `.shp` record header and its
  `STATEFP` and `PLACEFP` from the fixed-width `.dbf`, so no shapefile package enters any environment. It first
  confirms that every key of `usplace()` is a 2020 place in the files (all 31,617 are; the 292 places it does not
  carry are Puerto Rico's), then writes `data/usplacebox.csv` (`STFIP`, `PLFIP`, `LONmin`, `LONmax`, `LATmin`,
  `LATmax`, sorted by key, each float the shortest form that reads back as the shapefile's double, LF, no time stamp;
  SHA-256 `39d6c734…`, the same on two runs) and its `.jls`, the CSV read back. Each `usplace()` point lies in its
  place's box and within 5e-7 degrees of the Census interior point. `mapbbox(name; state)` builds a county's box in
  `Logjam._countybox`, which `mapbbox(state)` shares; every county's box was saved before the change
  (`tools/v0_3_1/save_county_boxes.jl`, `test/data/county_boxes_f3f0c1b.csv`) and `test/test_boxes_v031.jl` checks
  each bit for bit.

## v0.3.0

One breaking release, so a course pinned to v0.2.8 or v0.2.9 re-pins once. It makes the heuristics
and the transport, routing, network, geocoding and display functions agree with Matlog and with what
the lectures write out by hand: wrong answers found in review are corrected (Breaking changes), the
helpers the lectures define for themselves are exported or declared `public` (New), a map of a city
draws its streets (Changed), and the manual is checked name by name (Internal). This section also records the
changes that reached `main` after the v0.2.9 tag while `Project.toml` still read `0.2.9` (PR #13,
PR #18, and PR #14's commits folded into this release). **Migration** lists, as old call and new call,
every breaking change a course script meets; each entry cites the ruled item that decided it.

### Migration

Every breaking change a course script meets, as the old call and the new one. Each item names the entry
below that explains it; a call with no item here is unchanged.

| Old | New | Entry |
|:--|:--|:--|
| `ala(...)` printing nothing | `ala(...; verbose = false)` where no trace is wanted (2.3, 2.4, 3.4, HW 1) | PR #13, D3, S4 |
| a call that leaned on PR #13's leaving an orphan facility alone | pass the call's own `locate` handle | CR 4, CR 9, D4 |
| `y` read in construction order (`[3, 1]`, `[4, 1]`) | `y` is sorted (`[1, 3]`, `[1, 4]`) | CR 6 |
| ` p-median ADD: p facilities selected` from `pmedian` | `pmedian(...; verbose = false)`, or read the ` Add:` and `Xchg:` lines | D3 |
| `loc2lonlat` writing `geocode_cache.csv` in the working directory | `cache = "geocode_cache.csv"`; `cache_dir = dir` becomes `cache = joinpath(dir, "geocode_cache.csv")` | N14 |
| `source == "ADDRESS"` and `status == "OK"` for a street-only match | `"STREET"` and `"PARTIAL"`; a bad state in a batch reads `GC_STATUS == "FAIL"` | CR 26 |
| `.source`, `.uncert`, `.status` on a scalar `loc2lonlat` result | `.GC_SOURCE`, `.GC_UNCERT`, `.GC_STATUS` | R7, S14 |
| a printed `GC_UNCERT` | 0.836 of the old value | R2, S3 |
| `prt` printing a `Bool` as `1` and `0` | `true` and `false` | S13 |
| `d1([0, 0], P[i:i, :])` | `d1([0, 0], P[i, :])` (a vector against a row throws `DimensionMismatch`) | N5 |
| `aggshmt` on a `q` table reading the invented `f` | read `q` | N2 |
| `vcat(shS, DataFrame([aggshmt(...), ...]))` | add `; cols = :intersect` (the new `avh` column) | CR 14, R10, S37 |
| `charge_tl(q, s, d; ppi = p)` relying on the rate 2.00 | `charge_tl(q, s, d; r = 2.0, ppi = p)` | D5 |
| `savings(...)` taken to return every shipment | `sh2rte(1:n, R)` adds the single-shipment routes; drop `[r for r in R if length(r) > 2]` | CR 57 |
| `twoopt(...) == (r, TC)` and `pairwisesavings(...) == ([...], [...], [...])` | compare `Tuple(x)` or the named tuple | V rule 2 |
| `rte2lines(seq, P)` | `tracepath(P, seq)`, then `LON[path]`, `LAT[path]` | P8 |
| a printed route in 5.2, 5.3 or HW 5 | may list equal-cost neighbors in increasing order (the cost never changes) | CR 58 |
| `rteTC_vrp(...)` (5.3, HW 5) | `rteTC(...; full = true)` | CR 42, CR 59, D6 |
| a plain `rteTC` on a truck with `Kwt`, `Kcu` or `maxTC` | returns `Inf` for a route over a limit | CR 42, D6 |
| `addconnectors(...)` joining new points to each other | `addconnectors(...; add_nf_nf = true)` | D8, N16 |
| `c ? 60d / 20 : ...` times for connectors | `addconnectors(...; speed = 20)` and `links2graph(L; weight = :time)` | R4, S2 |
| `links2graph(L; ab_weight = :AB_TIME, ba_weight = :BA_TIME)`; `dir_col = :__NO_DIR__`; sparse IDs | `weight = (:AB_TIME, :BA_TIME)`; `L.DIR .= 0` on a copy; `prune_reindex` first | CR 17, C2, S17, P8 |
| `shortestpaths(g, W, n)` | `shortestpaths(g, n)` | N28 |
| `thin` keeping node labels; `keep_index`, `agg`, `must_match`, `verbose` | nodes come back numbered `1:n`; read `MERGED` | CR 18, CR 25, N6, P8 |
| `faf5interstate()`, `isptinbbox(pt, bbox)` | `Logjam.faf5interstateroads()`; `bbox[1][1] <= pt[1] <= bbox[1][2] && bbox[2][1] <= pt[2] <= bbox[2][2]` | P8 |
| `osm_roads(bb)` finding its pair in the working directory | `osm_roads(bb; cache_dir = ".")` | C3, R9, S18, CR 29 |
| `isempty(NAME)` on an OpenStreetMap link | `ismissing(NAME)` | CR 24, CR 34 |
| `stitchnetworks(...)` | `addconnectors`, then `prune_reindex` | P8 |
| `loc2lonlat("Raliegh"; state = :NC)` read as `FAIL` | reads `GC_SOURCE == "STATE"` | GC |
| `transport_costs(...)` | the smaller of `charge_tl` and `charge_ltl` (Lecture 3.4's own `c0`) | P8 |
| `mat2df(X, cols)`; `snapvals(x, n, m)` | `DataFrame(X, Symbol.(cols))`; `reshape(snapvals(x), n, m)` | P8 |
| `lonlat2loc(lon, lat, df)`; `lonlat2loc(df_in, df_ref)`; `loc2lonlat(...; country = :US)` | `lonlat2loc([lon, lat], df)`; `lonlat2loc([df_in.LON df_in.LAT], df_ref)`; drop `country` | P8 |
| `makemap(...; backend = ...)` | drop the keyword; activate the backend before the call | P8 |
| `plotroute!(ax, path, dfN)`; `plotroute!(ax, rte, sh, P, dfN; tr)`; `show_markers` | `plotroute!(ax, dfN.LON[path], dfN.LAT[path])`; `plotroute!(ax, rte, sh, [dfN.LON dfN.LAT]; tr, P)`; mark ends with `scatter!` | D2, P8 |
| `makemap(...; roadcolor = c, roadalpha = a)`; `maxroadlatspan` | `roads = (; color = c, alpha = a)`; none (`roads = false`) | MAP, C4, CR 56 |

### Breaking changes

- **`ala` prints every step by default (PR #13, PR #14, ruling D3, S4).** `ala` has a
  `verbose::Bool = true` keyword, and the trace is `ufl`'s: the total cost after every allocate
  step (` Alloc: ...`) and every locate step (`Locate: ...`, the allocation held, the new
  facilities moved), and, when `nruns > 1`, a `  k: TC = ...` line closing each run and a
  `  Final: TC = ...` line with the best. Step costs are rounded to four decimal places and run
  costs to one, and Julia prints a cost of a million or more with an exponent
  (`Locate: 7.79978534437e7`, `  Final: TC = 7.79978534e7`). With `nruns = 1` no per-run line is
  printed (PR #13's `  1: TC = ...` line is gone). A caller's own `alloc` handle prints its
  `Alloc` lines only, since only that handle can cost an allocation. An unchanged call now prints.
  **Migration:** pass `verbose = false` where no output is wanted (2.3, 2.4, 3.4 and HW 1 call
  `ala` without it).
- **`ala` restores Matlog's orphan repair, and `TC` and `W` always belong to the `X` returned
  (CR 4, CR 9, ruling D4).** A new facility nearest to no existing facility is moved to a random
  existing facility and the existing facilities are re-allocated, until every new facility serves
  one, as at v0.2.8 and in Matlog's `default_alloc` (PR #13 had removed it). Unlike v0.2.8, which
  costed the relocated locations but returned the un-relocated ones, the returned `X`, `W` and `TC`
  now agree, so a run that needed a repair can return slightly different coordinates (about
  `1e-7` degrees in HW 1 Q6(b)'s seeded runs) and an orphan run can no longer win a multi-start
  with a cost it does not have. The repair draws from the random stream exactly as v0.2.8 did, so
  a seeded `ala` reproduces. **The repair belongs to the default allocate step:** it is skipped
  when the call passes `alloc` (a forced partition may leave a facility empty on purpose) or
  `locate` (a handle may hold a facility fixed, as HW 1 Q6(c) does), so those calls keep their
  meaning. **Migration:** none for the lectures' calls; a call that relied on PR #13's behavior of
  leaving an orphan alone passes its own `locate` handle.
- **The UFL routines return their sites sorted (CR 6, decided 2026-08-29).** `ufladd`, `ufldrop`,
  `uflxchg`, `ufl` and `pmedian` return `y` in increasing order, as Matlog does, where
  `ufladd`, `uflxchg`, `ufl` and `pmedian` returned the order the sites were opened or swapped in
  (`ufldrop` already did). `y` is still a chosen set, so only its printed order and the tie-break
  of an EF between two equally near sites change. **Migration:** code that read the construction
  order out of `y` (Lecture 2.4's `[3, 1]`, `[4, 1]`) reads `[1, 3]` and `[1, 4]`, and
  `pmedian(9, ...)`'s named-city table reorders. Index *sequences* (routes, tours, paths) are not
  sorted.
- **`uflxchg` now returns a 1-swap local optimum (finding N32).** It swapped and reverted inside
  `for i in y`, so `deleteat!` and `push!` reordered the vector being scanned and candidate swaps
  were skipped: from the start `[1, 3]` on a seeded 5-site instance it stopped at total cost 122
  where a better swap (113, Matlog's answer) was open. The scan is now over the set as it stands,
  so `uflxchg` (and `ufl` and `pmedian`, which call it) can return a lower cost than before on
  the instances that hit the bug; no result gets worse. README Example 3 is one: its six-hub
  `pmedian` on the continental 3-digit ZIP areas now ends at 7.3823e10 people-miles where v0.2.8
  ended at 7.3850e10, Oak Lawn (ZIP area 608) in the place of Gary (464). **Migration:** none; a
  number that changes was the wrong answer.
- **`pmedian`'s trace is `ufl`'s (ruling D3).** `pmedian(p, C; verbose = true, construct = :add)`
  keeps its `verbose` keyword (PR #14 removed it) with v0.2.8's default `true`, and prints the
  ADD cost and then the EXCHANGE cost (` Add: ...`, `Xchg: ...`) where v0.2.8 printed the one
  line ` p-median ADD: p facilities selected`. **Migration:** pass `verbose = false` to silence it,
  as 2.7 and the harness already do; Lecture 2.4's four calls show the new lines.
- **The UFL routines check their inputs (finding N13).** `ufladd`, `ufldrop`, `uflxchg`, `ufl` and
  `pmedian` throw an `ErrorException` for a `k` of the wrong length or with a negative entry, a `y`
  that is out of range or repeats a site, and a `p` outside `1:n`, as Matlog does. `ufladd(-100, C)`
  used to open all six sites at a total cost of -600, and `ufladd(k, C; p = 7)` threw a
  `MethodError`. **Migration:** none for a call with valid inputs.
- **`loc2lonlat` writes a cache file only where asked, and only when it adds an entry
  (finding N14).** Before, any call whose input contained a comma or a digit rewrote
  `geocode_cache.csv` in the working directory (or in `cache_dir`), whether or not
  anything new was geocoded, so a student's folder or a package's `test/` folder
  acquired a stray file. Now the new `cache` keyword names the file: `cache = nothing`
  (the default) keeps the call's Nominatim results in memory only and reads and writes
  no file; `cache = "path/to/geocode_cache.csv"` reads that file and, when the call
  ends, appends the addresses it resolved (creating the file and its folder on the
  first entry; a call that adds nothing leaves the file untouched). `cache_dir = dir`
  still works as `cache = joinpath(dir, "geocode_cache.csv")` but is deprecated.
  Existing cache files are read unchanged.
  **Migration:** a script that relied on the working-directory file passes
  `cache = "geocode_cache.csv"`; replace `cache_dir = dir` with
  `cache = joinpath(dir, "geocode_cache.csv")` to drop the deprecation warning.
- **`loc2lonlat` reports a fallback, remembers a failed lookup, and does not invent a house number
  (CR 26).** Three behaviors, one change to what comes back.
  (1) *A fallback is reported.* When an address with a street is answered by a lower tier (Nominatim
  found no match, was not loaded, or the query failed), a warning names the input, why, and the tier
  used (`...located at its city (PLACE), not its street (status PARTIAL)`); v0.2.8 returned the
  city's centroid with only `source = "PLACE"` and `status = "PARTIAL"` to say so, and warned only
  that the extension was not loaded. The values returned are unchanged.
  (2) *A failure is cached.* A query Nominatim could not answer is stored (as `NOTFOUND`, in memory
  and, where `cache` names a file, in it) and not sent again, as Nominatim's usage policy asks; a
  network error is not stored, and `force_download = true` asks again. A cache file with such rows is
  not understood by v0.2.8 (they read as an `ADDRESS` at `NaN`); files v0.2.8 wrote are read as before.
  (3) *No house number is invented.* When the match is the street and not the house (the extension
  now passes the match's `house_number`), the row is `source = "STREET"`, `status = "PARTIAL"`, with
  the street's coordinates and an unknown (`missing`) uncertainty, where v0.2.8 returned it as an
  exact `ADDRESS`/`OK` with uncertainty 0 (`9999 Hillsborough St` came back as a stretch of the
  road). A street typed without a leading number (a landmark) claims none and stays `ADDRESS`/`OK`.
  And a state that is not a state (`"XX"`) no longer aborts a vector or DataFrame call: that row is
  `FAIL`, with a warning, and the others are geocoded; the scalar call still throws.
  **Migration:** code that compares `source` or `status` against `"ADDRESS"`/`"OK"` meets a new
  `"STREET"`/`"PARTIAL"` for a street-only match (4.2's data generator asserts `ADDRESS` for its
  three buildings, which still hold); a script that expected an `ArgumentError` from a bad state in
  a batch reads `GC_STATUS == "FAIL"` instead.
- **`GC_UNCERT` is the mean centroid-to-point distance of the area, `(2/3)·√(a/π)` (R2/S3,
  N25).** `loc2lonlat`'s uncertainty at the place, ZIP, county and state tiers was `0.45·√a` with
  no stated basis; it is now `(2/3)·√(a/π)` = `0.376·√a` for the land area `a` in mi²: the mean
  distance from the centroid to a uniformly random point of a disk of that area, the constant
  `dgca` floors its distances at, so the two now agree (they differ by a factor of 1.2 at v0.2.8).
  Every uncertainty shrinks to 0.836 of its old value: Raleigh's `5.46` mi is `4.56`. An exact
  `ADDRESS` is still `0`. **Migration:** a printed uncertainty column changes (4.2's geocoding
  table at the re-pin; its dictated sentence, "the average distance of a point within the area from
  the centroid", is now true); nothing else reads the value. The docstring also records the basis
  of the package's other two area-to-distance conversions, which stay as they are: `lonlat2loc`'s
  "in" radius is the full `√(a/π)`, and the `STATE` tier is the plain population-weighted mean of
  the county centroids, not `wcentroid`'s weighting (N25).
- **`loc2lonlat` has one set of field names, and `state` may be a vector (R7/S14).** The
  single-string method returned `(LON, LAT, source, uncert, status)` where the vector and DataFrame
  methods return the columns `GC_SOURCE`, `GC_UNCERT`, `GC_STATUS`. Every method now uses the `GC_`
  names: the scalar result is `(LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS)`; `LON` and `LAT` are
  unchanged. The vector method takes `state` as one state or a vector of states, one per location,
  so `loc2lonlat(City; state = St)` replaces `[loc2lonlat(c; state = s) for (c, s) in zip(City, St)]`
  and one `r.GC_STATUS` serves a scalar and a table; a vector of the wrong length is an
  `ArgumentError`, and an entry may be `missing`. **Migration:** rename `.source`, `.uncert` and
  `.status` on a scalar result to `.GC_SOURCE`, `.GC_UNCERT` and `.GC_STATUS` (a course homework asserts `gi.status == "OK"`); code that reads `LON`/`LAT` (`getindex.(S, :LON)`, `[r.LON for r in loc]`) is
  unchanged. The README and notebook example read `geo.GC_SOURCE`.
- **`prt` prints a `Bool` as `true` and `false` (S13).** A `Bool` column or element printed as `1`
  and `0`, beside prose that calls it a Boolean. **Migration:** none for a call; the output changes.
  3.3's `isLTL` column (`minTLC`'s table, Code block 13) now prints `true`/`false`.
- **`d1` and `d2` throw `DimensionMismatch` on points of different shape (finding N5).**
  `d2([0, 0], [3 4])` broadcast the vector against the 1×2 row and returned 7.07 (`d1`: 14.0) where
  the points are 5.0 (7.0) apart: the slip is `P[i:i, :]` for `P[i, :]`. Two arrays must now have the
  same size, anything else (tuples) the same length. **Migration:** write `P[i, :]` for a row; a call
  that passed a vector and a row matrix was returning the wrong number. None of the course's
  lectures or homeworks makes such a call.
- **`charge_tl` applies the TL minimum once per shipment, not once per truck (finding N3, ruling
  D5).** The chapter defines the independent charge as `max{c_TL, MC_TL}` (Freight Transport,
  the independent charge) and Matlog's `transcharge` computes
  `max(ceil(q/qmax) * d * r, mincharge)`; v0.2.8 computed `ceil(q/qmax) * max(r*d, MC)`, so a
  shipment of two or more trucks over a distance with `r*d` below the minimum paid the minimum
  for every truck (`charge_tl(30, 30, 10)` was 90, now 45). The charge is unchanged wherever
  `r*d` is at least the minimum or one truck carries the shipment, which is every call in
  Lectures 3.2 to 4.3 and in HW 3 (`test/test_transport_pins.jl`). The break reaches a
  delivery of two or more trucks to a point closer than `MC/r` miles (22.5 mi at the default
  rate): Project 3's nearest store is 15 mi from the DC (`charge_tl(40, ...)` there is 242 where
  v0.2.8 gave 364 on the pinned stand-in data), so its answer can move where a delivery to that
  store needs two trucks. **Migration:** none for a call that is not in that range; the regression
  run names any lecture or homework value that moves.
- **Nothing shipped, or shipped nowhere, costs nothing: zero charge at `q = 0` or `d = 0`, with Matlog's
  zero tolerance (findings N4, CR 15; Q3 ruling of 2026-10-04, Matlog's reading; rulings TRN3, TRN4).**
  `charge_ltl(0, s, d)` charged the LTL minimum for a zero-weight shipment (50.84 at 500 mi);
  `charge_tl(q, s, 0)` charged the TL minimum (45) for a shipment that is already at its destination;
  and `minTLC` at `d = 0` sized the shipment by that phantom minimum. `charge_tl` and `charge_ltl` now
  return `0.0` when `q == 0` or `d == 0`, and apply Matlog's `tol0 = 1e-4` as its `transcharge` and
  `mincharge` do (`abs(x) < 1e-4`, in tons and miles): a weight of less than `1e-4` ton is charged
  nothing, and a distance of less than `1e-4` mi carries no minimum charge, so the `9e-9` mi an
  optimizer leaves between a facility and its supplier costs the loaded-mile charge alone (about
  `2e-8` dollars a truck) where it paid the minimum. `minTLC` returns
  `(qᵒ = 0.0, TLCᵒ = 0.0, isLTL = false)` for a distance within `1e-4` mi whatever it is asked to
  check (TL, LTL or both); the call with neither `tr` nor `ppi` still returns `(nothing, Inf, false)`.
  **Migration:** none for the course's calls: 3.4's inline `c0`, `tlc_uc` and `tlc_xd`, HW 3 and
  Project 3's copies guard `d` with `isapprox(d, 0, atol = 1e-4)` before they call `charge_tl` or
  `minTLC`, so they already got 0 there and keep working; no lecture or released homework passes a
  distance or a weight below `1e-4` to the three functions directly; the pinned course calls do not
  move.
- **`aggshmt` sums its own base field, and invents no `f` (finding N2).** On shipments with a `q`
  column and no `f`, v0.2.8 returned the first shipment's `q` and an `f` that held the total (`q =
  [10, 20, 15]` gave `q = 10`, `f = 45`); Matlog's `aggshmt.m` sets `q` to the total and creates no
  `f`. The total now goes back into whichever column was the weight base, `f` or, with no `f`, `q`;
  `s`, `v`, `h` and `a` are the same weighted means as before. **Migration:** none for the course:
  every call (3.3, HW 3, Project 3) aggregates a table with an `f` column,
  whose result is unchanged. Code that read the invented `f` from a `q` table reads `q`.
- **`aggshmt` adds `avh`, and `totlogcost` and `minTLC` use it (CR 14, ruling R10/S37).** An aggregate
  shipment carries every product for the same interval, so its inventory cost per ton-year is the
  demand-weighted mean of each product's own `a·v·h`. `aggshmt` averaged `a`, `v` and `h` separately
  (as Matlog's `aggshmt.m` and the ISE 453 sheets do) and `totlogcost` and `minTLC` multiplied the
  three means, which agrees only when `h` and `a` are alike across the products (3.3's Example 1 and
  every other course aggregate with a common `h`) and otherwise understates the inventory cost (HW 3
  Q4's aggregate of products 1 and 2 printed 49,743.00 for a true 63,431.33). `aggshmt` now also returns **`avh = Σ fᵢ aᵢ vᵢ hᵢ / Σ fᵢ`, always
  present whenever the table has `a`, `v` and `h`** (a single row gets its own `a·v·h`); a row that
  carries `avh` is sized and costed by it (`totlogcost(q, c, row)`, `minTLC(row, ...)`), and a row
  without it, or with it `missing`, by `a·v·h` as before. The separate means are still returned and
  still the Matlog values (a recorded departure from Matlog's cost, not its means). Results are
  unchanged for equal `h` (3.3's aggregate). `avh` is computed from the rows aggregated, so a
  hand-edited `a`, `v` or `h` in the result does not update it (HW 3 Q4's `aggx` writes
  `merge(a, (v = vh, h = 1.0))` with the same coefficient, and costs the same by either route).
  **What each DataFrame idiom does with the new field** (`test/test_transtools.jl`):
  `DataFrame([aggshmt(...), ...])` has an `avh` column; `vcat(shS, that_table)` throws `ArgumentError:
  column(s) avh are missing from argument(s) 1`; `vcat(shS, that_table; cols = :intersect)` drops it;
  `vcat(...; cols = :union)` keeps it, `missing` on the rows that have none, and those rows are costed
  from `a·v·h`; and `that_table[:, names(shS)]` drops it silently, so a script that projects its aggregates this way (Project 3's does) keeps the separate averages for those rows.
  **Migration, HW 3 (run through the new code from its own inputs, 2026-11-20).** Q4's
  published answer, `TLC4 = ra.TLCᵒ + (ind[1]).TLCᵒ`, moves from 28,907.02 to **29,137.01** (the
  decision, material 1 alone and materials 2 and 3 as one aggregate, does not change); the `aggshmt`
  column of its plan table moves 49,743.00, 47,611.61, 28,907.02, 37,388.21 (plans 1+2, 1+3, 2+3,
  1+2+3 aggregate) to 63,431.33, 58,941.81, 29,137.01, 53,194.49, which are the homework's own `by_product` column to the cent. Q5's `shP = vcat(shS, DataFrame([byproduct(j) for j in 1:size(F, 2)]))`,
  needs one added keyword, `; cols = :intersect`, and then prints what it printed
  (1,417,865.74 and 1,543,625.16); `vcat(shS, shR[:, names(shS)])` is unchanged and prints
  1,414,881.24 and 1,538,646.26 as before. The same two edits apply wherever that code is repeated, and a script changes only where it feeds `aggshmt` to `minTLC` (Q4).
- **`charge_tl` derives its rate from `ppi` when `r` is not passed (ruling D5, finding T-r/ppi).** `r`
  and `ppi` were uncoupled: `charge_tl(q, s, d; ppi = 131.0)` charged the rate 2.00 and used `ppi`
  only for the minimum. With no `r`, the rate is now `2.00 * ppi / 102.7`, the lectures' own
  `rTL = 2.00ppiTL/102.7`, and 2.00 at the default `ppi` (so a call with neither is unchanged). **A
  rate that is passed is used as it is, never escalated again**, so every course call, which passes
  its escalated `r` (3.2, 3.3, 4.3 and the homeworks) or passes none and takes the default `ppi`, returns
  what it returned. The struct form `charge_tl(q, sh, tr)` always passes `tr.r`.
  **Migration:** a call that passed `ppi` and no `r` and relied on the rate 2.00 passes `r = 2.0`.
- **`totlogcost` is `Inf` for a shipment of no size that costs something (finding N31).** At `q = 0`
  with a positive charge it returned `c·f/eps()`, about 4.5e19, a number that looked like a cost;
  it now returns `Inf` (and, for any `q <= 0`, the same), while `c = 0` or `f = 0` still gives a
  transport term of 0, so `totlogcost(0, 0, ...)` is 0. **Migration:** none; the course never sizes
  a costed shipment at 0 (3.4's `tlc_uc` sizes a zero-distance shipment 0 at a charge of 0).
- **`savings` returns the routes it forms and no others (CR 57, ruled).** v0.2.8 started every shipment
  on a route `[i, i]` and returned every route left, so a shipment in no positive saving came back as
  a single-shipment route mixed in among the routes formed (`length.(savings(...)) .÷ 2` was `[1, 28, 1]`
  on 5.2's Ex. 8), and the index of a route said nothing about whether savings had formed it. Matlog's
  `savings.m` makes a route only when a pair is joined, and its callers add the single-shipment routes
  after, with `sh2rte`; `savings` now does the same, so a shipment on no formed route is on none of
  them. **Migration:** a call that needed every shipment on a route adds the missing `[k, k]` itself
  (Lecture 5.2's `sh2rte(1:n, R)`, which the course already defines, or `[R; [[k, k] for k in 1:n if k ∉
  reduce(vcat, R; init = Int[])]]`); a call that kept `[r for r in savings(...) if length(r) > 2]`
  (5.2's Ex. 9 and `loadform`, and the 2008 qual's four shipments) is unchanged by CR 57, and the
  filter is no longer needed; CR 39 still moves the routes kept (5.2 Ex. 9(c)'s loads, Code block 53,
  total 1,209.92 where they totaled 1,232.64, and its check `indL == idx1` against the lecture's own
  `savings_ijs`, v0.2.8's merge rule, fails: shipments 18 and 21 now join no route). **Where the route count moves**, measured through the pinned calls
  (`test/test_routing_pins.jl`; these are also moved by CR 39's merge rule): 5.2 Ex. 8 (qmd 2374,
  `r30`) three routes (28 shipments and two alone) become two (6 and 18), so the lecture's `oneroute`,
  which inserts only the shipments on a route, makes its one route for thirty shipments of 24 (Code
  block 43's `TC30` is 1,512.80 where it was 1,716.58);
  HW 5 Q1 (`Ra`) 14 routes
  with `[47, 47]` among them become 13, with the route sets also changed by CR 39. **Sites not run through
  the new code** (same call shape, so they move wherever a shipment was in no saving or CR 39 changed a
  merge): 5-rte-3.qmd lines 647, 890, 1039, 1140, 1191, 1235, 1672, 1705, 2160, 2273, 2477, 2788, 2804
  and 3692, HW 5's `Rg`, `Rs`, the `sh2rte(1:2m, ...)` line `R0` and the Clarke-Wright `Rs`, about 16 sites in 5.3 and HW 5. A call that took the first route, `savings(...)[1]` (5.2 Exs. 2, 3
  and 7: qmd 1882, 1928, 2024), is unchanged where every shipment joins one route, as in Exs. 2 and 3.
  **In Ex. 7 they do not:** one pass puts all 99 counties on two routes, of 45 and 54 shipments, whose
  merge CR 39 declines (the shorter inserted into the longer costs 2,472.78 against their 2,374.77), so
  `savings(...)[1]` tours 45 of the counties and Code block 39's 2-opt tour is 987.99 mi where it was
  2,169.02.
- **Several returned values are named tuples, with Matlog's output names (V rule 2).**
  `mincostinsert` and both `twoopt` methods return `(rte, TC)`, `pairwisesavings` returns `(i, j, s)`, as
  do the set `twoopt` and `sh2rte` (`(rte, idx1)`). **Destructuring, `x[1]`, `x[2]`,
  `ijs[3]`, `hcat(ijs...)` and `DataFrame(ijs)` work as they did**, and a search of 5.1, 5.2, 5.3 and
  HW 5 for an `isa Tuple` test or a comparison with a tuple literal found none. What changes is the type: `twoopt(...) == (r, TC)` and
  `pairwisesavings(...) == ([...], [...], [...])` are now `false`, so compare `Tuple(x)` or the named
  tuple, `(rte = r, TC = TC)`. Lecture 5.2's own `randreorder(ijs, p)`, which iterates its argument and
  returns a plain tuple, still runs on the named tuple.
- **`rte2lines` is removed (P8).** The `public` function turned a location sequence and the parent
  vectors of `shortestpaths` into NaN-separated line coordinates. No course call was found (the lectures,
  homeworks and projects; P8), and its name suggested a route when its argument is a location
  sequence. **Migration:** for each segment of `rte2loc(rte, sh, tr)`, `tracepath(P[a], a, b)` gives the
  nodes of the path and `LON[path]`, `LAT[path]` of the nodes table their coordinates. `plotroute!`'s
  route-and-parents methods draw as before, by a private copy of the function in the map extension.
- **A route lists equal-cost neighbors in increasing order (CR 58, ruled).** Where two neighboring
  loadings, or two neighboring unloadings, can trade places at exactly the same cost (the cost
  handle's value `==`), the routes `mincostinsert`, `twoopt` (a route or a vector of routes) and `savings`
  return list the lower-numbered shipment first, and the swap is repeated until none applies.
  It is applied once to the finished route, never inside a search (the searches are unchanged), and a tour
  is left as the search leaves it. **A printed route may change; its cost never does** (every cost on the
  pinned and oracle cases is bit-identical before and after). The rule is on the cost, not on the location,
  so it also fixes the direction of an equal-cost two-stop leg on symmetric data: 5.3 Ex. 1(c)'s second
  Clarke-Wright route `(4, 1, 4, 1)` is now `(1, 4, 1, 4)` and visits nodes 2 then 5, `(1, 2, 5, 1)`, as
  the lecture prints it (it printed `(1, 5, 2, 1)`), and 5.2 Ex. 4(b)'s route unloads shipments 1, 2 and 4
  at location 2 in the published order. A swap that changes the cost is never made (a window or a
  capacity that depends on the order keeps its order). **Migration:** a printed route or a location sequence in 5.2, 5.3
  and HW 5 may read differently; 14 of the 43 pinned course calls reorder
  (`test/fixtures/routing_pins.tsv`, each listed under CR58 in `RPIN_MOVED`), and no pinned cost moves.

- **`rteTC` is Matlog's `rteTC`: one route cost function that reads the truck's limits (CR 42, CR 59, D6;
  the keyword name `full` is for the D9 review).** v0.2.8's `rteTC` summed the segment costs and
  silently ignored `Kwt`, `Kcu` and `maxTC` on a truck (reserved, read by nothing), so a student who set
  a capacity got an uncapacitated answer with no warning. `rteTC(rte, sh, C, tr)` now returns `Inf` for a
  route that breaks one: a load mix over `tr.Kwt` (weights `q` on `sh`), over `tr.Kcu` (cube from `q`
  and `s`, with 5.3's rounding tolerance, so a load of exactly `maxpayld` is not over, S44), a cost over
  `tr.maxTC`, and a depot route that returns to its depot midway (Matlog's degenerate location vector,
  two routes). **A call whose truck carries none of `Kwt`, `Kcu`, `maxTC` returns exactly what it
  returned.** `rteTC(...; full = true)` returns `(TC, Xflg, out)` (a named tuple that destructures as
  Lecture 5.3's `TC, Xflg, out = rteTC_vrp(...)` does): the exit flag (1 feasible, -1 two routes, -2
  weight, -3 cube, -4 maxTC, -5 a time window), and the table of the route's stops with the
  schedule, the columns Lecture 5.3's hours-of-service wrapper reads (`out.Cost` is the driving, `TC` the
  time on duty, S8). **Loading and unloading times (`tL`, `tU` on `sh`) and time windows (`tbmin`,
  `tbmax`, `temin`, `temax` on `sh` and `tr`) are read only with `full = true`**: they change the cost
  of every route, and HW 5 Q1 passes a `tU` column to a plain `rteTC` and adds the unloading
  times itself. The travel cost is the `sum` of the segment costs on every path, as v0.2.8 summed it
  (a different order of addition moves the last places, and a 2-opt tie is decided by them), so
  `TC` equals `sum(segcost(rte2loc(rte, sh, tr), C))` bit for bit; with `full = true` the window scans
  are 5.3's `scanTW` (rows a, b, c), adding left to right, and `maxTC` is tested on cost plus loading
  before them, so it does not bound a windowed route's duration. `rteTC(R, sh, C, tr; full)` costs a
  vector of routes. Equal to 5.3's inline `rteTC_vrp` on its inputs, cost to 1e-9, flag and the whole
  `out` to 1e-9. The default truck is `(;)` and `rte2loc` reads the truck's `b` and `e` only if present,
  so `rte2loc(r, sh, (Kwt = 25,))` works (it threw `FieldError`; 5.3's `tr3 = (Kwt = 25,)`, qmd 1552).
  The cost is computed over typed columns behind a function barrier. `rte2ldmx`
  (CR 59) is exported; `scanTW` is `public`, not exported (D10). **Where it moves** (pinned,
  `test/test_routing_pins.jl`, listed under CR 42): a plain `rteTC` call that passes a truck with
  `Kwt`, `Kcu` or `maxTC` returns `Inf` for a route over it, where it returned the distance: 5.3's
  Code block 12 (`5-rte-3.qmd:996-1002`, `rteTC(r1, sh, D, tr)` on the tour over the cube capacity,
  which now prints `Inf` where its text says "a cost all the same"), HW 5's `rteTC(rte, sha, T, tra)`
  with `tra = (b = 1, e = 1, Kwt = 25, Kcu = 2750)` (HW 5 Q1; its own cost closure returns `Inf` for those routes, so its results do not move). **Migration:** Lecture 5.3's inline
  `rteTC_vrp(...)` becomes `rteTC(...; full = true)` at `5-rte-3.qmd` lines 1138, 1139, 1185, 1234,
  1238, 1646, 2074, 2094, 2159, 2168, 2268, 2278, 2476, 2787, 2789, 2799, 2813, 3687 and 3704 (19 calls;
  the definitions at 1071-1131 and `scanTW` at 1817 and `rte2ldmx` at 1062 are deleted), and in HW 5's own copy of the definitions; the inline definitions still run if left.

- **`rteTC` adds nothing for a segment between two stops at one location (CR 43, ruled).** v0.2.8
  charged `C[i, i]` for each such segment; Matlog's `rteTC` ignores it ("costs `C(i,i)` ignored"). It
  matters only for a matrix with a nonzero diagonal, such as a time matrix that carries a stop time.
  **Decision CR 43 asks for:** a route that returns to its depot midway (two trips) is priced by a
  plain `rteTC` with no limit on the truck, as before, and refused (`Inf`, flag -1) with `full = true`
  or when `Kwt`, `Kcu` or `maxTC` is on the truck. **Where it moves** (pinned, under CR 43): a plain
  call on a matrix with a nonzero diagonal. No released course call passes one to a plain `rteTC`:
  5.3 Ex. 6's `T = D/50 .+ 5/60` (`5-rte-3.qmd:2154`) goes only to `rteTC_vrp`, which already skips
  same-location segments; every other matrix of the lectures and HW 5 has a zero diagonal.

- **`addconnectors` defaults to `add_nf_nf = false` (D8, N16).** v0.2.8 joined the new points to each
  other by default, at 1.3 times their great circle distance; that arc became the shortest NCSU to Virginia
  Tech route (180.7 mi) in the 4.1 reconnaissance (CR 17's addendum), and Matlog leaves the choice to the
  caller (`makeNetwork2.m` discards those arcs). Seven of the eight lecture calls already pass `false`.
  **Migration:** pass `add_nf_nf = true` where the connectors between new points are wanted: Lecture 4.1's
  Code block 40 (`4-net-1.qmd:1317`, the one call that relied on the default) and 2.2's circuity
  generator (`make_circuity_road_vs_gc.jl`, whose route does not change: the arc between its two points is
  longer than the road). The README's pipeline example and the notebook's use the default and print a
  distance matrix without those arcs. Pinned: `l41_cb40_seven_cities_default_call`.
- **`addconnectors(...; speed)` fills the connectors' `SPEED`, and the distance column must be a distance
  (R4, S2).** The new keyword `speed` (mph, default `nothing`: unchanged) writes a speed on each connector,
  so a network of travel times is built from the distance by `links2graph(L; weight = :time)` without
  the by-hand `c ? 60d / 20 : ...` of Lectures 4.1, 4.2, 5.1 and 5.3 (`speed = 20`). A table with no
  `SPEED` column gets one, missing on the road links. The docstring now says that the links' third column
  must be a distance in miles, since a connector's value there is great circle miles times the
  circuity: a table whose third column holds minutes mixes the two (the passage of 4.1, Sec. 5, that
  suggests `weight` columns of time for `addconnectors` is the case this warns against).

- **`links2graph(L; weight)` builds the graph the lectures build by hand (CR 17, NW, C2, S17, P8).**
  Lecture 4.1's Code block 45 teaches two rules (annotation 2) and 4.1, 4.2, 5.1 and 5.3 write them out
  at 11 sites: each link gives an arc in each direction it can be traveled
  (`DIR` 0 both, 1 from `SRC` to `DST` only, **-1 from `DST` to `SRC` only**), and of parallel arcs **the
  shorter is kept** (`combine = min`, where v0.2.8 summed them: CR 17); a link of zero length stays an
  arc. `weight` is a column (position or name, default `3`), a `(forward, backward)` pair of columns or
  vectors (FAF5's `(:AB_TIME, :BA_TIME)`), a vector, or **`:time`**, Lecture 4.1's rule (Code block 51)
  in minutes: the free-flow time `AB_TIME` forward and `BA_TIME` backward where positive, else
  `60 * DIST / SPEED` at the link's `SPEED` (an OpenStreetMap network has no time columns, so it is
  `60 * DIST / SPEED` throughout, as 4.2's Code block 6); a connector's `SPEED` is what
  `addconnectors(...; speed = 20)` wrote. A link with neither a positive time nor a positive speed, in a
  direction it is traveled, throws an `ArgumentError` that names the fix. **Equal to the lectures' graphs
  bit for bit** (test `[S17]`, same arcs, same weights to the last bit): Wake County's two points (4.1
  Code block 45), the ten cities by distance and by time (Code blocks 48 and 51), the 100 county
  points by distance and by time (5.1 Code block 35, 5.3 Code block 64), and the OSM test fixture in
  4.2's form. Node IDs are **checked, not changed**: they must be `1:n` (every ID on a link), and
  `prune_reindex` stays the only function that renumbers; v0.2.8 silently renumbered a sparse network
  (`reindex = :auto`) and warned. **Removed, with no course call (P8):** `reindex`, `return_map`,
  `sparse_ratio`, `max_id_threshold`, `oneway_val`, `dir_col`, `ab_weight`, `ba_weight` (and the helper
  `normalize_links_df`); `src_col` and `dst_col` stay. The number of values returned no longer changes
  with a keyword (`return_map` returned three). **Migration:** `links2graph(L; ab_weight = :AB_TIME,
  ba_weight = :BA_TIME)` is `links2graph(L; weight = (:AB_TIME, :BA_TIME))`, `dir_col = :__NO_DIR__`
  (read every link as two-way) is `L.DIR .= 0` on a copy, and a table with sparse IDs goes through
  `prune_reindex` first. The README and notebook call `links2graph(dfL)` bare, and 4.2's Code block 31
  shrinks to `shortestpaths(links2graph(LU; weight = :time), n)`. **Where it moves:** 2.2's generator
  (`make_circuity_road_vs_gc.jl`) is the one course caller. Its graph has 14,533 arcs where v0.2.8's had
  14,541 (parallel arcs now one), and **its road distance is unchanged, 137.57 mi from High Point to
  Goldsboro (137.46 back)**; the 137.47 that CR 17's entry names is not what the lectures' two rules give
  on this crop (it is a reading with every link two-way: 137.33 here), and the circuity 1.14 stands at
  two decimals either way. Pinned: `l22_generator_links2graph_weights`, listed under CR17.
- **`shortestpaths(g, n)` takes any simple weighted graph; `shortestpaths(g, weights, n)` is deprecated
  (N28).** Where v0.2.8's two-argument method accepted only a `SimpleWeightedDiGraph`, it now accepts a
  `SimpleWeightedGraph` too, so Lecture 4.1's Code block 57 (an undirected graph of the thinned
  Interstates, which falls back to the three-argument form for that reason) is
  `shortestpaths(gI, nv(gI))`. The weight-matrix form still works, warns with `Base.depwarn` (silent
  unless Julia runs with `--depwarn=yes`, as `Pkg.test` does) and its docstring example is gone: it
  built `weights + weights'` from a network that lists both directions, which doubled each weight.
  `n` greater than the number of nodes throws an `ArgumentError`.

- **`thin` is rewritten on typed arcs: direction-aware, independent of the node labels, and the nodes it
  keeps come back numbered `1:n` (CR 18, CR 25, N6, C9, P8).** A node goes when its neighbors are two other
  nodes and it is passed through in every direction it is used (an arc each way to each neighbor, or one
  arc in and one out); the two arcs are replaced by one of their summed cost and, where that leaves two arcs
  between the same nodes in the same direction, the shorter is kept: Matlog's `thin`, repeated until
  nothing is left to remove. **It no longer depends on the labels (CR 18)**: nodes are visited in the order of
  the rows of `dfN` and v0.2.8's skip, which kept a degree-2 node whenever the merged path was longer than
  a parallel arc, is gone. **It keeps the directions of a network with one link per direction (CR 25)**: a
  one-way chain merges as a one-way chain, and OSM's two links per street thin each direction apart; a
  one-way sink, or a node two-way to one neighbor and one-way to the other, stays. Measured on 4.2's
  95,699-node OpenStreetMap tile (read from the lecture's data): 11,312 nodes and 26,629 links remain in
  1 s, and the distances between the kept nodes, 452,480 of them from 40 sources, differ by 4e-14 mi at
  most, with the same pairs unreachable. **The nodes are numbered `1:n` in the order they had, and `SRC`
  and `DST` are renumbered to match (N6)**, so the result goes straight to `links2graph`,
  `addconnectors` and drawing a path by row; the IDs that come in may be any distinct integers (4.1's
  Interstate files carry FAF5's). **The return is always `(N, L)`** and `L` has one more column, `MERGED`,
  the rows of the input links that make up each link in order along the road (v0.2.8's `keep_index = true`
  returned a third value, a `Dict`). A merged link has the distance summed and every other column from its
  first link; `DIR` is 0 for a link that can be traveled both ways. **Removed, with no course call (P8):**
  `agg`, `must_match`, `keep_index` and `verbose`. **Where it moves:** Lecture 4.1's Interstates (the
  FAF5-derived files, 34,746 nodes and 35,165 links): v0.2.8 left 621 nodes and 1,024 links as the file
  is read and 632 and 1,039 if `prune_reindex` came first (the numbering decided it: CR 18); now
  600 and 989 either way (Code blocks 35 and 36, the "Thinning takes ... from ... to ..." sentence, and
  Code block 56 which thins again). Code block 35's text "leaves each remaining node with its original
  index" is no longer true, and `prune_reindex` after `thin` finds nothing to renumber (it still works).
  Unmoved: Code block 32's schematic (6 nodes, 5 links, the one arc of 70, integer costs stay integers), Code
  block 34's Raleigh rectangle (227 nodes and 228 links to 11 and 12). Moved by the same rule: the Raleigh
  cut's intersections in Code block 56 (a triangle of three junctions thins to the one link between two of
  them, as Matlog's `thin` does). Pinned: `l41_cb35_interstates_thin`, `l41_cb32_schematic_thin_ids`,
  `l41_cb56_57_raleigh_intersections`, listed under N6_CR18_CR25. CR 18's own counts (1,255, 1,257 if
  reindexed first, 1,223 on the slide) were on the Oak Ridge network that 4.1 no longer ships.

- **`faf5interstate` and `isptinbbox` are removed (P8, 0 course calls).** A search of the lectures, the
  homeworks and the projects found no call of either, and neither appears in the README,
  the notebook or the docs' examples. `faf5interstate()` returned the NaN-separated interstate polylines
  that `makemap` and `plotroads!` already draw from the internal cached `faf5interstateroads()`, which a
  script that wants them can still call as `Logjam.faf5interstateroads()` (not public API). `isptinbbox(pt,
  bbox)` was a four-comparison test: `bbox[1][1] <= pt[1] <= bbox[1][2] && bbox[2][1] <= pt[2] <= bbox[2][2]`
  does it in one line, and `filter(r -> ..., df)` is the DataFrame form. **Migration:** none for a course
  call; replace a use of either by the above.

- **`osm_roads` reads a saved copy with no LightOSM, writes nothing unless asked, and is silent (C3, R9, S18,
  CR 29).** Reading a saved tile pair is now in Logjam itself, so Lecture 4.2 and a homework render from
  the copy they ship without `using LightOSM`; only a download needs it, and a call that
  misses its saved pair without it throws an error that says `using LightOSM`. The
  keyword stays `cache_dir`, a folder (`loc2lonlat`'s `cache` names a file), so every call a course makes
  keeps its keyword, but its default is now `nothing`, which reads and writes nothing; v0.2.8's `"."` wrote
  the pair into the working directory, 73 MB of it in a student's repository for a homework's city. Progress
  messages (`Loading cached OSM data`, which Lecture 4.2's page printed twice, and the download's counts)
  are behind `verbose = false`. The size warning (a box over 300 square miles, measured at the box's own
  latitude; v0.2.8 described its threshold as 200, reported it as 360 and fired at about 290) comes before
  a download only, not before reading a saved pair. **Migration:** a call that passed no `cache_dir` and
  relied on finding its pair in the working directory passes `cache_dir = "."`; every course call passes one.
  The saved pair's name is unchanged (a default call has no class part, below), so every pair saved before is
  found, and a saved pair needs no provenance file.

- **A download of `osm_roads` uses the posted speed, drops roads closed to cars and roads of an unknown
  class, keeps nodes that reach each other, and returns the types a saved pair reads back as (CR 21, CR 34,
  CR 24).** *Speed (CR 21):* `SPEED` is the way's `maxspeed` where OpenStreetMap has one, in mph (a number with
  no unit is km/h, as OpenStreetMap reads it; `none`, `signals`, a list and the like are not a speed), and the
  class's typical speed only where it has none, which is what the docstring always said: v0.2.8 never read the
  tag, though on a downtown Raleigh tile 97.6% of the links carry one and a quarter of them differ from the class
  speed (a tertiary road posted 25 mph was given 30). The posted speed is also kept, as `MAXSPEED` (`missing`
  where none is posted), so a table can show both. *Closed roads (CR 34):* a way whose most specific access tag
  for a car (`motorcar`, `motor_vehicle`, `vehicle`, `access`) is `no`, `private`, `agricultural`, `forestry`,
  `emergency` or `psv` is dropped, where LightOSM's `:drive` filter dropped only `motor_vehicle=no`,
  `motorcar=no` and `access=private`: a gated road tagged `vehicle=no` and `bus=yes` is no longer a street a car
  takes. The tag that decided is kept as `ACCESS` and a conditional rule (`vehicle:conditional`, ...) as
  `CONDITIONAL`, not applied (the tag omits the days, so applying it would open a road on a weekend). *Unknown
  class and connectivity (CR 24):* a road of a class not in the table (a `crossing`, 6 links on one Raleigh
  tile, which v0.2.8 gave the residential codes) is not downloaded, and the nodes are trimmed to the largest
  strongly connected set, where v0.2.8 kept the largest weakly connected one (on one Raleigh tile 797 strong
  components remained, 2.3% of the nodes mostly one-way stubs at the box edge, and a point joined to one had
  an infinite distance). *Types:* `NAME` is `missing`, not `""`, where there is no name, so a download and a
  saved pair agree (`ismissing`, which Lecture 4.2's `streets` and a homework's tests use, now works on
  both), and the three new columns are `Union{Missing,Int}` and `Union{Missing,String}`. A pair saved before
  v0.3.0 has none of the three columns and reads back exactly as it did (the committed cache of Lecture 4.2
  reads back value for value; every number it prints is unchanged, tested), so the lecture's numbers move only
  when the data are downloaded again, which is when OpenStreetMap's own changes move them anyway. **Migration:**
  code that adds the class speed to a table finds `SPEED` already posted; code that tests `isempty(NAME)` tests
  `ismissing`; a download is smaller than v0.2.8's by the closed roads. Pinned, moved under CR21, CR24 and
  CR34: the OSM test fixture's translation (`osm_fixture_translation_tables`, `_types`), its cache round
  trip, and Lecture 4.2's form on it (`l42_cb6_osm_fixture_two_graphs`).

- **A saved tile pair reads back with declared column types, the same as a download returns (CR 24).**
  v0.2.8 read the CSV with inferred types: `SOURCE` as `String3`, and `NAME` as `Union{Missing,String31}` on
  one tile and `Union{Missing,String}` on another, while a download gave `String` for both, so code written
  against one failed on the other (`isempty(NAME)`). A read is now `IDX`, `SRC`, `DST`, `SPEED`, `FCLASS`,
  `DIR` as `Int`; `LON`, `LAT`, `DIST` as `Float64`; `SOURCE` as `String`; `NAME` as `Union{Missing,String}`,
  `missing` where a name is blank, which Lecture 4.2's `streets` and a homework's tests with `ismissing`. Every
  value is unchanged: the committed cache of Lecture 4.2's two examples (10,674 and 95,699 nodes) reads back
  value for value (pins `l42_cb2_tile1_read_values`, `l42_cb31_tile2_read_values`, 0 moved), and so do the
  downstream numbers the lecture prints. Only the two `_read_types` pins move, under CR24. **Migration:** none
  for code that tests `ismissing` or `isequal(SOURCE, "CONNECTOR")`.

- **`stitchnetworks` is removed (P8, 0 course calls; N29 is then moot).** A search of the lectures, the
  homeworks and the projects found no call, and no lecture's apparatus panel lists it. It
  joined a regional OpenStreetMap network to a FAF5 network by connectors within a distance in meters, the only
  meters in Logjam; its docstring described a grade-separation step the code did not perform; and its wrapper's
  defaults (2,000 m, every class) were not its implementation's (500 m, FCLASS up to 3), so the documented call
  and the code disagreed. **Migration:** none for a course call. `addconnectors` joins points to a network, and
  `prune_reindex` renumbers a combined one, which is what a script that needs two networks in one builds on.
- **`prt` drops the digits that are zero in every value of a column of fractions, and takes the decimal
  places per column (PR).** A column in which every value is below 1 in magnitude printed `allfrac` (4)
  places whatever its values: `0.5000`, `0.4500`. It now follows Matlog's `mdisp` ("Ignore all 0 digits
  in column of fractions"): the column prints with the smallest number of places from 1 to `allfrac` at
  which every value times a power of ten is an integer, so `0.45` and `0.449` print as `0.450` and
  `0.449`, a column of `0.5` as `0.5`, and a column rounded to three places (Lecture 2.7's utilization,
  `round(..., digits = 3)`) as its three places. A column with a value that needs more keeps `allfrac`
  places, a `NaN` or `missing` in the column leaves it at `allfrac` places (as `mdisp` does), and mixed
  columns keep their fixed `fracdig`, so money keeps its trailing zeros (`1,357.20`). No value loses a
  digit it has. `fracdig` and `allfrac` also take a specification for each column: a vector for a matrix
  or vector, a `NamedTuple` or `Dict` keyed by column name for a DataFrame (`prt(df; fracdig = (Radius =
  1, rmse = 5))`); a column the specification does not name keeps 2 and 4, a name that is no column is an
  `ArgumentError`, and a column named in `fracdig` shows that many places at most even when it holds
  fractions, unless `allfrac` names it too. The DataFrame method takes any `AbstractDataFrame`. The rule
  is checked against `mdisp` itself on 77 columns (`test/oracles/mdisp_digits.csv`). **Migration:** none
  for the code; the printed tables of Lectures 2.5 (Code blocks 13 and 14), 2.7 (Code block 18), 3.3
  (Code block 13) and 3.4 (Code blocks 12 to 14 and 21 to 23), HW 3 (Q3) and HW 5 (Q3) change where a
  column of fractions has trailing zeros (`0.4490` is `0.449`, `0.8570` is `0.857`, a column of 0.5 and
  0.3 is `0.5` and `0.3`), and a call that wants the old fixed places passes them per column.
- **`loc2lonlat` sends a plain string down the same tier ladder as an address string (GC).** A string
  with no comma and no digit was looked up as a place and nothing else, and returned `FAIL` when nothing
  matched, while the same name with a comma (`"Raliegh, NC"`) fell back to its state. A plain string now
  enters the one ladder, a five-digit string as a postal code and any other as a city, so
  `loc2lonlat("Raliegh"; state = :NC)` returns the North Carolina row (`GC_SOURCE = "STATE"`,
  `GC_STATUS = "PARTIAL"`), as `loc2lonlat("Raliegh, NC")` does, in the scalar, vector and DataFrame
  forms alike. A name with no state and no match stays `FAIL`, as does an empty string, a ZIP that is not
  in the table, and a name that matches several places; with a `state`, a ZIP that is not in the table and
  a name that matches several places in it fall back to the state. A name that is found is answered at its
  own tier as before. **Migration:** none for a course call (every plain name the course geocodes is a
  real place with its state, so Lectures 3.4, 4.1, 5.2 and 5.3, HW 2, HW 3, Project 3 and the six queries
  of 4.2 return what they returned); a script that read `GC_STATUS == "FAIL"` as "not found, with a state
  given" reads `GC_SOURCE == "STATE"`.
- **`transport_costs` is removed (P8, 0 course calls).** A search of the lectures, the homeworks and the projects found no call: every lecture and homework calls `charge_tl`, `charge_ltl` and `minTLC` itself.
  It chose the cheaper of the two modes for each row of a table, through a keyword router of its own
  (`ppi_tl`, `ppi_ltl`, and a bare `ppi` that overrode both, a third PPI convention). **Migration:**
  none for a course call. The cheaper mode's charge of one shipment (Lecture 3.4's own `c0`, Matlog's
  `transcharge`) is the smaller of `charge_tl(q, sh, tr)` and `charge_ltl(q, sh; ppi)`, row by row.
- **`mat2df` and `snapvals(x, n, m)` are removed (P8, 0 course calls).** No lecture, homework or project calls `mat2df`, which built a DataFrame from a matrix and column names, with an optional row-label column,
  and none passes `snapvals` a shape (the course's calls are all `snapvals(x)`).
  `snapvals(x; atol)` is unchanged. **Migration:** `DataFrame(X, Symbol.(cols))` for `mat2df(X, cols)`,
  and `insertcols!(df, 1, :ID => rows)` for its `rows` and `row_title`; `reshape(snapvals(x), n, m)` for
  `snapvals(x, n, m)`.
- **`lonlat2loc`'s `(lon, lat, df)`, `(x, y, df)` and `(df_in, df_ref)` methods, and `loc2lonlat`'s
  `country` keyword, are removed (P8, 0 course calls).** The course's `lonlat2loc` calls (lectures, homeworks and projects) all pass one coordinate pair or an n×2 matrix, `lonlat2loc(xy, df)`, which is unchanged,
  and no `loc2lonlat` call passes `country`, which only the street tier honored (the census tables are
  U.S. only). **Migration:** `lonlat2loc([lon, lat], df)` for `lonlat2loc(lon, lat, df)`;
  `lonlat2loc([x y], df)` for `lonlat2loc(x, y, df)`; for a table of coordinates,
  `r = lonlat2loc([df_in.LON df_in.LAT], df_ref)`, whose columns `NAME`, `ST`, `dist`, `bearing`, `dir` and
  `desc` replace the `GC_NAME`, `GC_ST`, `GC_DIST`, `GC_DIR` and `GC_DESC` the table method appended;
  drop `country = :US` (the address tier still sends `countrycodes=us`). The README and notebook example
  that passed the pair now pass a vector.
- **`makemap`'s `backend` keyword and the GLMakie extension are removed (P8, 0 course calls).** No
  lecture, homework or generator passes `backend` (Lecture 1.2 tells students CairoMakie is all they need),
  `LogjamGLMakieExt` was never loaded by the test suite, and it could not work alone, since the map
  extension triggers on CairoMakie and GeoMakie. `makemap(...; backend = :GLMakie)` and
  `backend = :CairoMakie` now throw a `MethodError` (an unsupported keyword), `GLMakie` leaves
  `[weakdeps]`, `[extensions]` and `[compat]`, and the README's and manual's GLMakie rows go.
  `makemap` also stops calling `CairoMakie.activate!()` on every call. Measured at v0.2.8 on
  CairoMakie 0.15 and Makie 0.24: that call left `px_per_unit`, `visible`, `inline` and the active
  backend as the caller had set them, and reset one thing, the image type to `"png"`; the lectures
  that run `CairoMakie.activate!(px_per_unit = 2)` (3.2 on) set no type, so none changes. **Migration:**
  drop the keyword. `makemap` no longer switches backends, so the active Makie backend draws: a script
  that wants another backend activates it before the call (Logjam's tests run CairoMakie only, so a
  GLMakie map is untested), and `CairoMakie.activate!(type = "svg")` is now left alone.
- **`plotroute!` is three methods, and draws arrowheads (D2, P8, 0 course calls).** v0.2.8's five methods,
  `(ax, lx, ly)`, `(ax, path, dfN)`, `(ax, paths, dfN)`, `(ax, rte, sh, P, dfN; tr)` and
  `(ax, routes, sh, P, dfN; tr)`, the origin and destination markers (`show_markers`, `origin_color`,
  `dest_color`, `markersize`) and their line builder `_rte2lines` are replaced by `plotroute!(ax, x, y)`, any
  sequence of locations; `plotroute!(ax, rte, sh, XY; tr, P)`, one route; and `plotroute!(ax, R, sh, XY; tr, P,
  colors)`, several routes, one color each. `XY` is the n×2 matrix of the locations; with `P`, the parent
  vectors `shortestpaths` returns, each leg is traced along the network (`tracepath`) and `XY`'s rows are the
  network's nodes. An arrowhead sits `arrow_at = 0.55` of the way along each leg (`arrows = false` draws none,
  `arrow_every = k` one on every k-th leg, `arrow_size` its length in pixels; a leg of no length, a location
  visited twice, has none). The arrowheads point along the leg as it is drawn, on a map and on a plain `Axis`
  and again after a `resize!`: the angle comes from the axis's own transform and limits, not from degrees of
  longitude and latitude, and `plotroute!` calls nothing in GeoMakie. Measured from rendered pictures of
  legs on both axes at three figure sizes, the heading is within 1 degree of the leg's (the test allows 2).
  The call returns `(; lines, arrows)`, the plots drawn (a vector of each for several routes), where it
  returned a vector of plots. The README's route images change because the arrows are on.
  **Migration:** `plotroute!(ax, path, dfN)` is `plotroute!(ax, dfN.LON[path], dfN.LAT[path])`; for
  `(ax, paths, dfN)` call it once for each path; `plotroute!(ax, rte, sh, P, dfN; tr)` is
  `plotroute!(ax, rte, sh, [dfN.LON dfN.LAT]; tr, P)`, and the several-route form likewise with `R`; mark the
  ends with `scatter!` where `show_markers` drew them (`scatter!(ax, [x[1]], [y[1]]; color = :green)`). A
  removed call or keyword throws a `MethodError`. Arrowheads are D2's; its labels, route numbers and
  `plotshmt!` come in v0.3.1.
- **`makemap`'s `roadcolor`, `roadalpha` and `maxroadlatspan` keywords are removed, and it returns
  `(; fig, ax, layers)` (MAP, C4, CR 56; 0 course calls for the keywords).** No lecture, generator or homework passes the three keywords (README Example 2 passed the first two). `roads = (; color, alpha, linewidth)`
  restyles the same Interstate layer, which is still drawn only up to 30 degrees of latitude span, at the
  same opacity and width by zoom for what the call leaves out. The return is a `NamedTuple` of three where it
  was a tuple of two: `fig, ax = makemap(...)` takes the first two as it took them, and the third, `layers`,
  holds the base-layer plots by name (`roads`, `states`, `countries`; `nothing` for one not drawn). Every
  course call (99 in the lectures, generators and homeworks, 49 files) destructures exactly two; the only
  call that takes three, `fig, ax, h = makemap(region=:CUS)` in the F24 notebook cells staged at
  `2-location/source/2-Loc-4-cells.jl`, threw at v0.2.8 and now gets `layers` in `h`. `doRoadbkgd` stays as a
  deprecated alias for `roads` (`false` is `roads = false`, `true` is `roads = :auto`), for the course's 14
  sites: it warns only under `--depwarn=yes`, so a rendered lecture shows nothing, and giving it together with
  `roads` is an `ArgumentError`. **Migration:** `roadcolor = c, roadalpha = a` is
  `roads = (; color = c, alpha = a)`; `maxroadlatspan` has no replacement (use `roads = false` for none); the
  README and notebook Example 2 changed their line, and the prose beside it.

### New

- **`osm_roads` keeps where its data came from, asks again when the server is busy, and takes a class filter
  (CR 22, CR 29).** A download writes, beside the pair it saves, `osm_<tile>_provenance.csv` (a `KEY`,
  `VALUE` table: the box, the fetch time in UTC, the data's own `osm_base` timestamp, the class filter, the
  counts, the Logjam version and the ODbL notice, © OpenStreetMap contributors), so a saved tile can say what
  day of the map it is; the name starts `osm_` and ends `.csv`, so a homework's ignore line `osm_*.csv`
  covers it, and a read never needs it (Lecture 4.2's tiles have none). A busy server (HTTP 429, 502, 503,
  504) is asked again after 30 s, then 60, then 120, as Overpass asks, where v0.2.8 gave up with "check your
  connection"; the request carries the User-Agent of `loc2lonlat`'s Nominatim call, which names the package
  and no person, where LightOSM's was HTTP.jl's default; and it declares a time and memory limit sized to the
  box (about 90 s and 128 MiB for a 116 sq mi tile, the size the public server refused three times at LightOSM's
  defaults and admitted at once with these), over HTTPS. `osm_roads(bb; highways = ["motorway", "trunk"])`
  downloads only roads of those classes (the classes of the table in its docstring), which makes a freeway
  network of a large box a request the server answers; the saved pair's name then carries the classes
  (`..._hw-motorway+trunk_nodes.csv`), and a call without the filter keeps the names it had, so a pair saved
  before is found. **No migration.**
- **`osm_roads(bb; crop)` takes `mapbbox`'s box and can crop to it; `mapbbox(bb; xexpand, yexpand)` and
  `cropnetwork(N, L, bb)` take it too (CR 35, CR 23, C6).** `osm_roads(mapbbox(x, y; xexpand = 2, yexpand =
  0.5))` works: the box is `((xmin, xmax), (ymin, ymax))`, as `mapbbox` returns it, and the four-number
  `(xmin, xmax, ymin, ymax)` of v0.2.8 is still accepted, so every call a course makes today is unchanged and
  returns what it returned (the splat `(bb[1]..., bb[2]...)` is no longer needed). `crop = true` crops the
  network to the box asked for, which Lecture 4.2 and a homework do by hand with `cropnetwork(dfN, dfL, x,
  y; xexpand, yexpand)`; the two are equal (tested), and the default `crop = false` still returns the whole
  tile. `cropnetwork(N, L, bb)` crops a network to a box with no expansion unless `xexpand` or `yexpand` is
  given (its column keywords are unchanged), and `mapbbox(bb; xexpand, yexpand)` widens a box. **No
  migration;** the call sites drop the splat when the course re-pins.
- **`pathroads(p, L; name = :NAME, fallback = nothing, weight = 3, miles = false)` (CR 30).** The roads a
  path follows, for FAF5 and OpenStreetMap links alike: a table with a numbered row, `Seg`, for each run
  of one road name (`Street`) and the steps it covers (`Steps`, as `"3-7"`: step `t` is the link from
  `p[t]` to `p[t+1]`, so each street traces back into the path), and with `miles = true` the weight along
  the run (`Miles`). It is Lecture 4.2's `streets` (Code block 8) made general: a step is read as the
  link that can be traveled that way (`DIR` respected, so a path that runs against a FAF5 two-way link's
  `SRC` to `DST` works), parallel links give the one of least weight, `fallback` names a column to read
  where `name` is `missing` or blank (FAF5's `:SIGN`, "I 40"), a link with no name, a connector, is passed
  over without ending a run, and a step along no link throws an `ArgumentError`. **Equal to `streets`**
  on 4.2's own inputs: the 52 paths (11,196 steps) of the shortest and the fastest route, out and back,
  between 13 point pairs on the lecture's cached 95,699-node tile, and on the OSM test fixture (test
  `test_pathroads.jl`). Exported (CR 30). **Migration:** Lecture 4.2's Code block 8 becomes
  `pathroads(p, Lc)`.
- **`ala(...; rng)` and `randX(P, n; rng)` (S5; rulings LOC8, LOC11).** An optional random-number
  generator for the restarts and the orphan repair. The default, `rng = nothing`, draws from the global
  stream exactly as v0.2.8 did, byte for byte (the draws behind HW 1 Q5 and Lectures 2.3 and 2.4 are
  locked and compared), so `Random.seed!(s)` before the call still reproduces a run. A generator
  passed as `rng` leaves the global stream untouched. The keyword is typed
  `rng::Union{Nothing,AbstractRNG} = nothing` (`Random` is a dependency since this release's
  environment work), so a value that is not a generator is a `TypeError` that names `rng`.
- **`minTLC(sh; tr, ppi_ltl)`, the keyword form beside the positional `minTLC(sh, tr, ppi)` (ruling
  S6).** The third positional argument is the *LTL* PPI while
  `tr.ppi` is the TL PPI, which is easy to misread; the keywords name them. **The positional form is
  kept and unchanged**: about 40 course calls write it (3.3, 3.4, 4.3, HW 3, Project 3) and `test/test_transport_pins.jl` pins each. Its deprecation is a note in `?minTLC` and nothing
  else (no warning). Naming an argument both ways is an `ArgumentError`. S9: the docstring says a mode
  is *selected* (`isLTL = true` iff LTL is selected), where it said *wins*.
- **`qmax_ltl(s)` (R5/S7, name for the D9 review).** `min(5, 650·s/2000)`: the largest shipment, in
  tons, for which the LTL rate estimate is defined at density `s`, which `minTLC` searches up to.
  Four lecture sites re-derive it by hand (`650s/2000` in 3.2 and 3.3), and a figure caption was once
  false because a search ran over the whole trailer. Exported; a lecture or homework that defines its own `qmax_ltl` after `using Logjam` still runs (none does).
- **`twoopt(π, C::AbstractMatrix)`, the delta-cost 2-opt of a closed tour (CR 48, S19; name and
  argument order for the D9 review).** For a cost that is the sum of arc costs given by a matrix, each
  change is evaluated by the arcs removed against the arcs added (for an asymmetric `C`, plus the
  reversed stretch's backward against forward arcs, from prefix sums), so a change is O(1) and a scan
  O(m²) where `twoopt(π, rTCh)` recomputes the whole tour, O(m) a change and O(m³) a scan. It makes the
  same changes in the same order and returns the same tour and cost: 5.1's six traces of Matlog's
  `tsp2opt` and Ex. 3's asymmetric six nodes are reproduced exactly, and so are 120 seeded symmetric
  and asymmetric instances; 400 random points take well under a second where CR 48 measured minutes
  at 1,000. **The tour argument is named `π`**, as 5.1's rung is (S19). The general method
  `twoopt(r, rTCh)` is unchanged and still takes any cost, a route's included. A route vector (every
  element twice) is refused with an `ArgumentError`: its cost is not a sum of arc costs. A
  best-improvement variant and neighbor lists, which CR 48 lists as optional, are not built.
- **`savings(rteTCh, sh; ijs)` (CR 40; name for the D9 review).** `ijs`
  is the savings list the procedure takes its pairs from, in the order given: the tuple `(i, j, s)`
  `pairwisesavings` returns (only `i` and `j` are read) or an `m x 3` matrix, Matlog's `IJS`; the
  default is `pairwisesavings(rteTCh, sh)`, so an unchanged call is unchanged. It replaces 5.2's
  `savings_ijs(rteTCh, sh, ijs)`, which is Logjam's v0.2.8 `savings` with the list given. A list that
  names a shipment outside `1:n` is an `ArgumentError`. 5.2's randomized savings passes it the list its
  own `randreorder(ijs, p)` reorders (tested with the lecture's definition in the suite).
- **`pairwisesavings(rteTCh, sh; TC1)`, the independent cost of each shipment (CR 41; keyword, where
  Matlog's `pairwisesavings.m` takes it as a third positional argument; name for the D9 review).** The
  saving of a pair is `TC1[i] + TC1[j] - cost(combined route)`, and `TC1[k]` is `rteTCh([k, k])` unless
  given: a total logistics cost measures its savings from each shipment shipped on its own at its own best
  size and mode (`minTLC`, LTL allowed), which a route cost handle need not equal. A vector of the wrong
  length is an `ArgumentError`. An unchanged call is unchanged (the pinned calls do not move), and
  Matlog's makeRouting2.m Example 1, which passes the direct distances, is reproduced. `savings` takes the same keyword (below).
- **`savings(rteTCh, sh; TC1, ijs)`: one independent-cost keyword for the list and the merges (CR 40, CR 41; name for the D9 review).** `ijs` now defaults to `pairwisesavings(rteTCh, sh; TC1)`, and when `TC1`
  is given the merge tests of `savings` use `TC1[k]` where they used `rteTCh([k, k])`, so a list that
  ranks pairs by one independent cost no longer has its merges accepted on another (Matlog has the same
  split; 5.2 arranges the two equal and asserts it, `5-rte-2.qmd:2834`). An unchanged call is unchanged:
  `TC1 = nothing` is `rteTCh([k, k])` in both places. A vector of the wrong length is an `ArgumentError`.
- **`rtesegsum(rte, x = ones)` (CR 53; Matlog's name).** `rtesegsum` is the sum
  of a value of each shipment over each segment of a route, as 5.2's Code block 4 and 5.3's Code block 3
  define it: `x` is indexed by shipment number, any route is accepted (no normalization), and it equals the
  lectures' definition on the 90 orderings of 5.2 Ex. 1(c), bit for bit. Exported; a lecture that defines its own `rtesegsum`
  after `using Logjam` still runs, and **lint LOGJAM-01 will flag the lecture's copy** until it is deleted
  at the re-pin. `rte2ldmx` (output unchanged) and route 2-opt's empty-truck test now read the same
  scan, which builds no `Set` per call: that test takes 0.19 microsecond on a 60-stop route where it took
  0.53, and 2-opt from the identity route of 5.2 Ex. 8 takes about 0.20 s where it took 0.27 s.
- **`rte2idx(rte)` and `sh2rte(idx, R)` (CR 53; Matlog's names).** `rte2idx` is `rte[isorigin(rte)]`
  for a route and the vector of those for a vector of routes: the two methods of 5.2's Code block 49.
  `sh2rte(idx, R)` appends the single-shipment route `[k, k]` for each shipment of `idx` on no route of `R` and
  returns the named tuple `(rte, idx1)`, `idx1` being the **shipments** added, in increasing order as
  Matlog's `setdiff` returns them (the lecture's definition keeps `idx`'s order, the same for `1:n`);
  it equals the lecture's on its own call and on the routes `savings` forms on 5.2 Ex. 8 and 5.3 Ex. 1(c).
  Matlog's optional print-only cost handle is left out. Exported; the lecture's own definitions made after
  `using Logjam` still run, and **lint LOGJAM-01 will flag them** until they are deleted at the re-pin.
- **Routes as a set, by dispatch, Matlog's cell array (RS).** `twoopt(R, rTCh)` improves each route
  (or tour) of a vector of routes `R` and returns the named tuple `(rte, TC)`, the routes and the vector of
  their costs; `twoopt(R, C::AbstractMatrix)` does the same for a vector of tours with the delta method of
  `twoopt(π, C)`; `rte2loc(R, sh, tr)` gives a location sequence for each route; `sh2rte(sh, R)` is
  `sh2rte(1:nrow(sh), R)`; `rteTC(R, ...)` is as it was. They replace the comprehensions of 5.2 and
  5.3 (`[twoopt_rte(r, h)[1] for r in savings(h, sh)]` followed by `h.(R)`, `[rte2loc(r, sh, tr) for r in R]`),
  which still work, and make the two-line load formation `R, TC = twoopt(savings(h, sh), h)` then
  `R, idx1 = sh2rte(sh, R)`, equal to 5.2's `loadform` on Ex. 8's shipments at the one-truck charge. There
  is no `Route` or `Routes` type and no `loadform` export (ruled). Every call that worked still works.
- **`ala` accepts `dist = Inf` (N31),** the Chebyshev metric, as `dists` already did.
- **`pmedian(...; construct = :both)` (D-2).** Runs ADD → EXCHANGE and DROP → EXCHANGE and keeps the
  better, as Matlog's `pmedian` does; the default `:add` is the v0.2.8 behavior. DROP wins in
  about 2 to 4% of instances with `n` close to `p`.
- **`thousands(x; digits = 0, sep = ",")` (CR 8, R6/S12).** One exported thousands-and-money
  formatter in place of the course's lecture-local `commafmt`, `usd`, `commas`, `com` and `mnum`,
  six variants that disagreed: `$1357.2` (3.2), `$1,357.2` (4.3), `$64,580.9` and `$30.0` (4.4),
  `$1124` and `$114620` (2.5) and `$10529.75` (6.3) all print as fixed decimals with trailing zeros
  kept, separators on the whole part only, and a correct sign (`thousands(1357.2; digits = 2)` is
  `"1,357.20"`). `sep = "{,}"` is 1.1's `mnum`. It shares `prt`'s formatting core. The name is a
  proposal (D9): no lecture, companion script or homework defines `thousands`, and a script
  that does `using Logjam` and then defines its own still runs.
- **`dists(x, X, p)` for one point returns a vector, and `unit =` is a synonym (R8/S15).** The
  one-point call `dists(x::Vector, X, :mi)` was a `MethodError`, so sites wrote `reshape(x, 1, 2)`,
  `x'` or `XY[1:1, :]` and then flattened; it now returns the length-k vector of distances. A
  great-circle unit may be given as `dists(X, Y; unit = :mi)`, as `dgc` and `dgca` take it. Nothing
  existing changes: the one-point forms the course writes today return the same numbers.
- **`makemap(bb)` draws a box (MAP, C6).** `makemap(bb; ...)` takes the box `mapbbox` returns,
  `((xmin, xmax), (ymin, ymax))`, and draws exactly it, as `makemap(bb[1], bb[2]; xexpand = 0, yexpand = 0, ...)`
  does, with the vector method's other keywords and the same figure and axis. Lecture 4.2's two maps of a
  whole downloaded box, `makemap(bb[1], bb[2]; doRoadbkgd = false, xexpand = 0, yexpand = 0)`, are
  `makemap(bb; doRoadbkgd = false)`, with the figure, limits and layers the long form gives (tested against
  the long form's pin). `xexpand` and `yexpand` are not keywords of the box method and throw an
  `ArgumentError`; the `(x, y)` forms, the tuple pair among them, are unchanged. **No migration.**
- **`makemap` draws into a cell, takes a `size`, and its layers are keywords (MAP, C4; CR 46, CR 56).**
  `makemap(fig[1, 2], x, y; ...)`, `makemap(cell, bb)` and `makemap(cell; region = ...)` draw the map in a cell of
  a figure that exists, and `makemap(x, y; ...)` is the same drawing in a figure it creates; `fig` is the figure
  that holds the cell, and `size` is not a keyword of a cell. Lecture 5.1's Code block 7 draws three frames on
  plain axes with the state borders added by hand (CR 46); each is now a map in its cell. `size = (w, h)` gives
  the figure's size, with the default `(600, 450)` Makie's own, so every pinned figure is as it was (26 of 38
  lecture calls follow `makemap` with a `resize!`); `size = (w, :auto)` takes the height `round(Int, w * height /
  width) + 10` from the projected limits, which is Lecture 5.3's `fitmap!` (tested against it). `roads = :auto`
  (the default) is today's road layer exactly, `roads = false` draws none, and `roads = (; color, alpha,
  linewidth)` restyles it; `borders = true` (the default) is today's border layers, `borders = false` draws
  none, and `borders = (; color, linewidth)` restyles them, which is what Lecture 5.3's `basemap` does by looping
  over `ax.scene.plots` (tested against it). Nothing visible changes unless a caller asks, pinned by
  `test/test_map_pins.jl` and `test/test_map_line_pins.jl`. `plotroads!` draws what it drew, its three styling
  loops now one that takes the zoom regime from the same rule `makemap`'s road layer uses (a latitude span of at
  most 10, then 20 degrees); it still returns its `Dict`, which Lecture 2.5 iterates as `k => v`. **No
  migration.**
- **The line builders are one family: `x2ln(i, j, x)`, `tracepath(P, i, j)` and `tracepath(P, seq)` (MAP, C8).**
  `x2ln(i, j, x)` takes the index vectors of the links, a table's `SRC` and `DST` or the shipments' `b` and `e`,
  and a coordinate vector, and returns the NaN-separated segments, one for each link: Lecture 4.1 builds a graph
  only to draw its links (`gR = SimpleWeightedGraph(rL.SRC, rL.DST, rL.DIST)`, `x2ln(gR, rN.LON)`, Code block
  34) and Lecture 5.2 defines `sh2ln` for the shipments (Code block 9), both of which `x2ln(i, j, x)` draws
  (tested against each: the same segments, and a graph has one edge where a pair of nodes has two links).
  `tracepath(P, i, j)` is `tracepath(P[i], i, j)`, which repeats `i` at nine course sites, and
  `tracepath(P, seq)` is the path through a sequence of locations, the idiom `reduce(vcat, [tracepath(P[i], i, j)[1:end-1]
  for (i, j) in legs])` and then the last node of Lectures 5.1 (Code block 37) and 5.3 (Code block 71): a
  location where one leg ends and the next begins is one node, a leg from a location to itself adds none, and the
  result begins with `seq[1]` and ends with `seq[end]` (tested equal to the idiom on random networks, one-way
  links included). The existing `x2ln(g, x)` and `tracepath(parents, origin, dest)` are unchanged, and the new
  methods are not ambiguous with them. `plotroute!` with `P` draws its line with `tracepath(P, loc)`, so a
  junction node is in its line once where it was twice; the drawn picture is the same. **No migration.**
- **`lonlat(df)`, `lonlat(row)`, `lonlat(v)` and `loc2lonlat` on integer ZIPs (LL, A1).** `lonlat` hands the
  distance and location functions the coordinates they take: `lonlat(df)` is the `n × 2` `Float64` matrix
  `hcat(df.LON, df.LAT)`, the line the lectures write wherever a table becomes a matrix of points (Lecture
  2.3's Code block 2, Lecture 5.1's Code block 27, Lecture 2.6's, among many); `lonlat(r)` is the vector
  `[r.LON, r.LAT]` of a table's row or of a named tuple such as `loc2lonlat` returns for one place (Lecture
  3.4's Code block 18, Lecture 4.1's `closest`, the `[w.LON, w.LAT]` Lecture 2.2 hands `optimize`); and
  `lonlat(v)` is the matrix of a vector of such named tuples, which Lecture 3.4 builds as
  `[getindex.(S, :LON) getindex.(S, :LAT)]`. Each is equal, bit for bit, to the lecture's line on the
  lecture's data (tested). A place with a `missing` `LON` or `LAT`, a place `loc2lonlat` did not find, is an
  `ArgumentError` that names the first such row, where `hcat` carried the `missing` into the distances.
  `loc2lonlat(27601)` and `loc2lonlat([27606, 32606, 48234, 27518])` geocode integer ZIPs at the `POSTALCODE` tier,
  zero-padded as the DataFrame method pads a `postalcode` column (`2139` is `"02139"`), and return what the
  string call returns; a homework locates a list of integer ZIPs with a `leftjoin` against `uszcta5()`, and
  `lonlat(loc2lonlat(zips))` is the same matrix (tested). Two course scripts define a `lonlat` of their own
  (two homeworks, one a method of a table and one of a vector of ZIPs) and two generators name a variable
  `lonlat`; each still runs and calls its own after `using Logjam` (tested in a fresh process). **No
  migration;** the homeworks' local definitions can go when the course re-pins.
- **`usstate()`, the state-level table of the census ladder (CR 12).** One row for each state and the District
  of Columbia (51), on its siblings' schema: `STFIP`, `ST`, `NAME`, `LON`, `LAT` (center of population,
  longitude first), `POP`, `ALAND`, `AWATER`, `ISCUS`. It is aggregated from `uscounty()`, with no new data
  file, so it agrees with the ladder: the populations sum to the county total (tested, state by state), and the
  center of population is the population-weighted mean of the county centers, as `loc2lonlat`'s `STATE` tier
  takes it, which is within 2e-4 degrees of the mean of the block groups' centers (tested). It is the 48-state
  demand set Lecture 2.5's ladder can show below the 3-digit ZIP areas, in the 2020 census (the course's
  ISE 361 data set of the 48 states is the 2010 census, 7% fewer people). The table is built once and each call
  returns a copy. `ISCUS` is false for Alaska and Hawaii only. **No migration.**
- **`Logjam.usstates()` is `public` and returns a copy (MAP, C12, V6).** Lecture 5.1 draws the state borders with
  `lines!(ax, Logjam.usstates()...)` and four of the Lecture 2.2 figure generators call it the same way, so the
  name is declared `public` and documented. It stays unexported (a script's own `usstates` does not collide with
  it, and it is one letter from `usstate`, the table). The border file was already read once per session; each
  call now returns a copy of the vectors, so a caller that changes them (the course never does) no longer changes
  the next call's. The values are unchanged (pinned: 3,642 points, 103 `NaN` separators, the same bytes); the
  first call takes 0.19 s and a later one 0.015 ms, where it took 0.19 s and under 0.001 ms. **No migration.**

- **`mapbbox("Wake"; state = :NC)`, the box of a county, offline (CR 28, V8).** A county's box from Logjam's own
  tables, in the shape `mapbbox(x, y)` returns, `((xmin, xmax), (ymin, ymax))`: the extent of the county's Census
  block groups, each widened by the radius of a disk of its land area, which is how Lecture 4.2's Code block 3
  computes Wake County's box. It equals that code's `bbW` (reordered) to the last bit (tested), so `osm_roads`
  snaps it to the same tile. It is a method of `mapbbox` and not a new name (V8), and takes `xexpand` and
  `yexpand` as the other methods do; `state` is required, and an unknown county or state is an `ArgumentError`
  that names it. A city's box (CR 28's Nominatim path) and a state's are not here: no lecture asks for them. **No
  migration;** 4.2's block of code can become the one call at the re-pin.

### Changed

- **The default road layer of a map 150 miles across or less is the FAF5 network, as Lecture 2.5 draws it by hand (S22, S23).**
  `makemap`'s `roads = :auto` drew the Interstate skeleton on any map up to 30 degrees of latitude, which is too
  sparse for a metropolitan one, and Lecture 2.5's `dotmap` therefore switches the layer by hand at a distance
  (`CLOSE = 150.0` miles, the larger of the box's north-south and east-west great-circle extents through its
  center) and draws the network with `plotroads!`. `makemap` now makes that switch: when the map as drawn (the box
  after `xexpand` and `yexpand`) is at most 150 miles across by that measure, `roads = :auto` draws the FAF5
  network, cropped to the box (every link whose segment meets it, so the roads run to the frame's edge; no
  connectors; and no ramps, which pile up into blotches at interchanges: the 137,156 links FAF5 names a ramp, a
  collector-distributor lane or a turn lane are left out), in `:steelblue` at opacity 0.3, the classes (FCLASS 1 to 5 as `plotroads!` groups them) at widths
  1.4, 1.0, 0.7, 0.5 and 0.3, the Interstate on top. Every stroke is below 0.35, the opacity under which the
  course's figure-label gate takes a map stroke for the muted base a label may cross; Lecture 2.5's hand-drawn 0.45
  is over it. A larger map draws what it drew, the Interstate layer in the same tiers by latitude span and none
  above 30 degrees; `:World`, `:US` and `:CUS` are never close. A `roads = (; color, alpha, linewidth)` restyles the
  network as it restyles the Interstate layer: `color` replaces the hue, `alpha` the opacity of every class, and
  `linewidth` the Interstate's width, the other four keeping their ratios to it. `roads = false` draws nothing, as
  before. `layers.roads` of a close map is a `NamedTuple` of the five class plots (`class1` to `class5`, `nothing`
  for a class with no link in the box), where it is one `Lines` on a larger map. `plotroads!` is unchanged.
  **Course figures that change:** one, Lecture 2.7's clinics map (`fig-clinics`, `2-loc-7.qmd:2120`, 53 miles
  across), which drew the Interstates and now draws the network. No other lecture, generator or homework calls
  `makemap` with the default road layer on a map of 150 miles across or less: the ten call shapes that use it are
  pinned, with their extents, in `test/test_map_k11c_pins.jl`, and apart from the clinics map and one probe (the
  Triangle's FAF5 nodes, 81 miles) they are 163 miles across (the High Point to Goldsboro generator of Lecture 2.3)
  or over 230. Lecture 2.5's `dotmap` already passes `doRoadbkgd = false` on a close map, and its own network is
  drawn by `plotroads!`, which is unchanged.
  **Migration:** none; `dotmap`'s hand-drawn network can be dropped for `makemap(lon, lat; xexpand = 0.02,
  yexpand = 0.02)`.

### Fixes

- **`addconnectors` gives the same connectors on every run, and leaves the random stream where it was (finding: DelaunayTriangulation's default random stream).** Where four nodes lie on a circle (a regular grid of nodes), the two triangles the
  Delaunay triangulation can make of them are equally good, and the one chosen came from the global random
  stream, so a point inside such a cell was joined to one diagonal's corners on one run and the other's on the
  next, and the call advanced the caller's stream as well, so the `rand()` after `Random.seed!(s)` and the
  call was not the one after `Random.seed!(s)` alone. Every triangulation `addconnectors` makes (and
  `aligntext`'s, which also splits ties) now takes a generator of its own, so the choice depends on the
  points alone and the caller's stream is untouched. A network whose nodes are in general position has one triangle holding a point and is unchanged, and no pinned course value moved (`test/test_road_pins.jl`). The `Random` standard library is now a dependency, for the
  generator. **Migration:** none; a script that depended on the draw `addconnectors` took from the global
  stream (its own later draws shifted by it) draws differently.

- **`plotroads!`'s signature line says what it returns (CR 24's docstring item).** It read `-> Vector{Lines}`
  while its Returns section, and the code, give a `Dict{Symbol, Any}` of named handles; the signature line is
  now `-> Dict{Symbol, Any}`. (CR 24's other docstring item, `stitchnetworks`' wrapper defaults, goes with the
  function: P8.) **No migration.**

- **`osm_roads`'s grid snap keeps an edge that is on a grid line (CR 23).** The box is rounded outward to a
  grid of 0.05° of longitude and latitude with `floor` and `ceil` in floating point, so an edge exactly on a
  line could gain a whole cell: `ceil(-78.60 / 0.05)` is `ceil(-1571.9999...)`, and a box ending at -78.60
  downloaded to -78.55, doubling the area in that direction. An edge within a millionth of a cell of a line is
  now on it, and a box of no width or height is one tile. Any other edge is rounded outward exactly as before,
  so every box off the grid, which is every box a course call makes, gives the same tile and the same file
  names (Lecture 4.2's two boxes, Ex. 1's and Ex. 3's, are pinned and unchanged). Pinned:
  `osm_snap_on_grid_edges` moves under CR23, `osm_snap_off_grid_edges` does not. **No migration.**

- **`minTLC`'s LTL search has a bracket guard, and its silent range case is documented (finding N31,
  ruling R5/S7).** Below a density of `150/650` lb/ft³ the search bracket is empty (the cube bound
  `650·s/2000` is under the 0.075-ton minimum) and Optim stopped with an error; the LTL option is now
  left out, as Matlog leaves it out, and the call returns the TL result or `(nothing, Inf, false)`.
  Beyond 3,354 mi `rate_ltl` is `Inf` for every size, so `minTLC` has no LTL option there and says so
  to nobody (no warning, no error): LTL-only returns `(nothing, Inf, false)`, both modes return the TL
  result. The docstring now says so, with the example, and `qmax_ltl` (below) is the bound. No course
  call is in either range.
- **`loc2lonlat` reads an address string by a grammar, from the end (finding N1).** v0.2.8 took the
  last two *letters* of the text as a state code, so sixteen spelled-out state names put the city in
  the wrong state (`"Atlanta, Georgia"` was Iowa, `"Tulsa, Oklahoma"` Massachusetts, `"Houston,
  Texas"` failed), and it took the *first* five-digit run as the ZIP, so `"10420 Falls of Neuse Rd,
  Raleigh, NC 27614"` lost its city and state. Now the ZIP is the last token (ZIP+4 allowed), the
  state a whole word (a spelled-out name, longest first, or a two-letter code), and what is left is
  street and city. A `state` keyword is never overridden by the text: when they disagree the keyword
  is used and a warning names both. The parse of every address the course passes (4.2's, the
  `Raleigh, NC` forms, HW 1's `Roanoke Rapids, NC`) is unchanged, so saved cache keys still match.
  **Migration:** none; a result that changes was in the wrong state.
- **A ZIP with a leading zero geocodes, and a numeric ZIP column is accepted (findings N7, N8,
  S36).** `loc2lonlat("02139")` failed because the query string was compared with the table's
  integer codes as text (`"02139"` against `"2139"`), so 2,485 ZCTAs, 7.6% of the U.S. population,
  could not be found by ZIP, and `loc2lonlat(df)` threw `MethodError` on a ZIP column that CSV.jl had
  read as `Int64`. ZIPs are now five-character strings **inside the geocoder only**: an integer (or a
  whole-valued float) is zero-padded, a text of one to four digits is padded the same way, and a
  ZIP+4 keeps its first five digits. The census tables are not touched: `uszcta5().ZCTA5` and
  `uszcta3().ZCTA3` stay integers, so the course's integer filters, `÷` and joins on them keep
  working (`test/test_geocode.jl` and the pins check both). **Migration:** none.
- **`ufladd` no longer changes the caller's `y` (CR 5).** A warm start `y` was grown in place with
  `push!`; the routine now works on a copy, and `ufl` hands DROP the set it was given rather
  than ADD's extended one. `ufladd`'s `p` is documented as what it always was, the exact number of
  sites to open (Matlog: "add exactly `p` NFs"), not a cap (N13).
- **`uflxchg`'s docstring states Matlog's single-site exception (N24):** with one open site no
  swap is tried, so the local-optimality promise holds from two open sites.
- **Faster UFL heuristics (N23).** `ufladd`, `ufldrop` and `uflxchg` keep each EF's cheapest
  open cost (and, for DROP and EXCHANGE, the second cheapest) instead of re-slicing `C` for every
  candidate, as Matlog does. The sets are unchanged (tested against the naive algorithms on 60 and
  80 seeded instances). ADD's printed total can differ in its last place, since it is now summed
  incrementally (Lecture 2.6's `Add: 7.512802738280858e8` prints `...859e8`, 2.7's `...018e8`
  prints `...017e8`). `pmedian(10, C)` on a random 600×600 matrix takes 0.19 s on
  the build machine; the whole-package review timed v0.2.8 at 1.8 s for the same call.
- **Docstrings (PR #14).** `wcentroid` no longer lists `ala` and `randX` under "See also"
  (neither uses it); `ala`'s examples are Lecture 2.3's I-40 case, run as a doctest with its
  printed trace, and a seeded three-NF, six-city case whose restarts land in different local
  optima. Every example added or changed in this release shows its output and names its source.
- **`prt` prints a value of any magnitude (CR 2).** Neither formatting path converts to `Int64` now,
  so `prt([1e300 1.0])` no longer throws `InexactError`: a float prints its own digits, grouped by
  commas, and an `Int` above `2^53` keeps its last digit (it went through `Float64` before and
  printed `...992` for `...993`). No new display rule: there is no switch to scientific notation.
- **`prt` prints `missing` (CR 32).** `missing` prints blank, as `NaN` does, in the matrix, vector and
  every DataFrame path. An all-numeric frame with a `missing` threw a `TypeError` (4.2's
  `prt(string.(df))` worked around it), and a mixed frame printed the word `missing`.
- **`prt` with `fracdig` or `allfrac` of 5 or more prints the fraction (N11).** The fraction was built
  from `string(round(frac; digits))`, which turns to scientific notation below `1e-4`:
  `prt([1.000001 2.5]; fracdig = 6)` printed `1.0e-600`. The fraction is now digits, at any `digits`.
  A rounding carry (`1.996` at 2 places is `2.00`) reaches the whole part, and a value that rounds to
  zero prints without a minus sign.
- **`prt` treats `Symbol` and `Union{Missing,String}` columns as text (N12).** `prt(DataFrame(ST =
  [:NC, :VA], POP = [1, 2]))` threw `MethodError: isnan(::Symbol)`. A DataFrame column is formatted
  from its own element type, not from `Matrix(df)`, which promoted `Bool` and `Int` columns to
  `Float64`.
- **One keyword set on every `prt` method (keyword parity, V7).** The vector method takes `fracdig` and
  `allfrac`; the DataFrame method takes `rows`, `fracdig`, `allfrac` and `row_title`, and its
  mixed-column path uses `fracdig` and `allfrac` where it hard-coded 2 and 4 (the defaults are the
  same, so an unchanged call prints the same). An all-numeric frame is still numbered `1:nrow` and a
  frame with a text column is still not, as at v0.2.8. Every call the course makes prints
  byte for byte what it printed (`test/test_prt_pins.jl`), except the ruled changes above.
- **`dists(X, Y, p)` accepts any integer `p` (N19).** `dists(X, Y, 3)` threw while `dists(X, Y, 3.0)`
  worked, although the docstring promises any real `p >= 1`; an integer other than 1 and 2 is now the
  general lₚ metric, the same numbers as the float.
- **`dgca`'s example exercises the floor (N27).** Its 500 mi² disk never reached any of its >100 mi
  distances; the example now floors one entry (Raleigh to Durham, 20.6 mi raised to 26.6 mi by a
  5,000 mi² disk) and says what the areas are.
- **`dgc` keeps the sphere, and its docstring says how far a Matlog number agrees (D7; rulings DST1, DST2).**
  Every `dgc` distance is on the sphere of constant radius every course number rests on (3958.75 mi,
  6371.00 km), unchanged, and `dgc` takes no Earth-model keyword. Matlog's `dists` uses a latitude-dependent
  radius (`3963.34 - 13.35|sin φ̄|` mi, `φ̄` the mean latitude), which differs from the sphere by under 0.1% at
  North Carolina's latitudes (Raleigh to Charlotte: 129.759 against 129.655 mi), so a Matlog or 2022 MATLAB
  great-circle number agrees with `dgc` to about three significant figures. The tests compare with MATLAB's
  `dists(X, Y, 'mi')` within that named tolerance (relative 1e-3).
- **Every distance in `dgc`, `d1`, `d2`, `dists` and `dgca` is unchanged for a call with valid arguments (N5, N19, N1)**
  (`test/test_dist_geo_pins.jl` pins the course's calls value for value), except the ruled
  changes in this section.
- **`mincostinsert` runs the F24 lecture's loop and never returns a vector that is not a route (CR 38).**
  v0.2.7's AI fix (`a09375a`) widened the pickup loop to `i = 1:m + 1`, so the search also tried
  loading and unloading the new shipment after the last stop, `[r..., k, k]`, on which the truck is
  empty between the route and the shipment. The loops are now `i = 1:m`, `j = max(2, i):m + 1`, the
  loops of the 5-Rte-2 notebook and Lecture 5.2's `mincostinsert_rte`: the `m(m + 3)/2 - 1` routes of Eq. insert-count.
  An infeasible insertion (every position `Inf`) still returns the route unchanged with cost `Inf`.
  **Moves:** 5.2 Ex. 8's randomized insertion, first start, 1,630.77 to 1,630.35 mi (the lecture's own
  `mincostinsert_rte` prints 1,630.35); a call that inserted the larger shipment of a pair into the
  route of a smaller one under a one-truck charge, as the 2008 qual's pair table never does (it inserts the smaller into the larger's route and agrees with the lecture's loop).
  `savings` and `pairwisesavings` call it: on every instance in 5.2, 5.3 and HW 5 they return
  what they returned (`test/test_routing_pins.jl`). `test_routetools.jl`'s R1 regression, which asserted
  the end position, asserts its reverse. **Migration:** none for the course; `mincostinsert_rte` in
  5.2 and the homeworks is deleted at the re-pin and its calls become `mincostinsert`.
- **`twoopt` on a route vector moves a route's ends and never leaves the truck empty (CR 37, CR 54).**
  The one `twoopt` took the closed tour's loops for every vector, so on a route (each shipment twice,
  the first its pickup) the first and last stops never moved, and a reversal that emptied the truck
  between shipments (`(1, 2, 1, 2)` reversed in the middle is `(1, 1, 2, 2)`, two routes) was taken
  whenever it was cheaper. A vector now counts as a route when **every element appears exactly twice**
  (a tour visits its locations once and returns to the first, so it never does): a route runs Matlog's
  `twoopt.m` neighborhood, `i = 1:m - 1`, `j = i + 1:m`, reversing `r[i:j]`, and skips a reversal that
  leaves the truck empty, which is Lecture 5.2's `twoopt_rte` line for line; **a tour runs v0.2.8's loops
  unchanged**, so 5.1's `twoopt(loc, h)` returns exactly what it did (`test/test_routing_pins.jl`).
  Moves, on the course's inputs: makeRouting2.m's 8-city route from insertion 150.38 to 148.63 mi,
  from the identity 152.81 to 148.63, from the seeded random start 152.81 to 150.38 (MATLAB's three
  routes and costs); Ex. 1's `(1, 2, 2, 1)` from 1,024.49 to 731.82. **No course call moves**: 5.2, 5.3,
  and HW 5 call their own `twoopt_rte` on routes and the export only on tours. **Tie
  sensitivity:** a reversal that is a zero change in exact arithmetic (all the deliveries
  of a depot route reversed) is kept or dropped by a strict `<` according to the machine's order of
  summation, 1e-13 either way, so the route a run ends at can differ with `--check-bounds` or between
  Julia versions, for this export and for `twoopt_rte` alike (makeRouting3.m Ex. 1's route ends at
  1,133.10, 1,151.13 or 1,181.34 by the summation, and 5.2's Ex. 3 at 452.69 or 446.61). The suite
  therefore asserts that MATLAB's final routes are local optima of this neighborhood, not that a
  run reaches them.
- **`savings` makes Matlog's three merges and none that does not save (CR 39).** v0.2.8 started every
  shipment on a route `[i, i]`, took the pairs of the list in order, and inserted the shorter route's
  shipments into the longer one on the pair's own saving, never asking whether the merged route cost
  less than the two it replaced: a merge could raise the total (a route costing more than shipping
  its shipments alone; E22 on route TLC, 5 of 17 merges). `savings` is now Matlog's `savings.m`: for
  a pair with neither shipment on a route a new route is formed (kept if `c(i) + c(j)` exceeds its
  cost); with one on a route the other is inserted into it (kept if `c(k) + c(route)` exceeds the new
  route's cost, a shipment already tried against an unchanged route not tried again); with both on
  different routes the shorter is inserted into the longer (kept if the two costs exceed the
  combined one); and the list is passed over again until a pass changes nothing or every shipment is
  on a route. Inserts go through `mincostinsert`. Matlog's three-case routes are reproduced exactly
  on makeRouting2.m Examples 1 (six cities), 2 (8-city TSP as shipments) and 3 (51 cities). **Moves
  (pinned, `test/test_routing_pins.jl`):** 5.2 Ex. 8's 30 NC shipments, whose old routes (one of 28
  shipments and two alone) become a route of 6, a route of 18 and six alone; 5.3's Clarke-Wright
  example (the same two routes, the first now written `(2, 3, 5, 3, 5, 2)`), makeRouting3.m's 30
  shipments (with and without the truck's limits), HW 5 Q1's route set. Unmoved: 5.2's
  Ex. 6(a) and the 2008 qual's four shipments (the assertion `savings(...) == [r3]` still holds).
  **Also moved, measured in the course regression and not pinned:** 5.2 Exs. 7 and 9(c) (under CR 57
  above) and HW 5 Q3's shuttle, 12 routes where it formed 5 (every trip still served once, every time
  window kept). The routes formed come first
  and a shipment no merge reached follows as `[k, k]` (CR 57 changes that next).
  **Not reproduced:** makeRouting3.m Ex. 1 (all 30 shipments from one depot): MATLAB's route costs
  1,271.57 where this ends at 1,205.50, because Matlog's `mincostinsert` also tries the positions
  before the first stop and after the last and skips a delivery directly after a stop at the location
  of the one before it, which on a depot route forbids delivering first (the skip is a defect in
  `mincostinsert.m`, ruled 2026-11-21, so Logjam does not copy it); CR 38 has `mincostinsert`
  follow the F24 lecture's loop and `savings` inserts with it. And 5.2 Ex. 8 differs from MATLAB's `savings`
  (which joins shipment 12 to the 18-shipment route and ends 7 mi above) for the same reason, as does
  5.2 Ex. 7, which MATLAB's `savings` makes one tour (the CR 57 entry above).
- **`addconnectors` finds each new point's connectors by an exact local point location, at every size
  (CR 62, CR 27, C1).** v0.2.8 triangulated every network node before locating any point: 3 s at the
  19,233 nodes of 5.1's county crop, 31 s at 54,620 nodes, 120 s on 4.2's 95,699-node OpenStreetMap tile
  (why a homework on a city-sized network works around it). A new point now triangulates its 16 nearest nodes (twice
  as many, as often as needed), takes the triangle that holds it, and accepts the triangle only when its
  circumcircle holds no other node, tested exactly with DelaunayTriangulation's adaptive predicate. An
  empty circumcircle makes it a triangle of the whole network's Delaunay triangulation, so **the
  connectors are the whole triangulation's**, not an approximation (a plain 40-nearest-nodes version
  matched for 5 of 10 cities and 67 of 100 counties). One code path at every size, no threshold. Same
  connectors as the whole triangulation on 10 of 10 NC cities (4.1 Code block 48) and 100 of 100
  counties (5.1 Code block 35), on 3 of 3 points of the 4.2 tile, on seeded random networks (a property
  test, inside the hull and outside it), and on every pinned course call (`test/test_road_pins.jl`,
  none moved). Timing, 10 points: 4,712 nodes 0.02 s against 0.18 s; 22,392 nodes 0.01 s against
  3.1 s; 54,620 nodes 0.03 s against 31 s; 5 points on the 95,699-node tile 0.05 s against 120 s.
  **A point outside the hull of the network's nodes** still uses the whole triangulation (its two
  hull-edge nodes, as before): that case costs what v0.2.8 cost, 120 s on the tile. The nodes of a
  point's connectors are listed in increasing order (v0.2.8's order varied from run to run). Where four
  nodes lie on one circle, the Delaunay triangulation is not unique and either triangle is correct; the
  OSM test fixture's lattice is such a case, and v0.2.8 itself chose differently from run to run there.
  `addconnectors` accepts any `AbstractVector` of coordinates, a view included, and any
  `AbstractDataFrame`. **No migration.**

### Internal

- **Three extensions, and every function an extension draws is declared in core (MAP, C5).** The map extension
  (`LogjamMapExt`) is triggered by GeoMakie alone and is written against Makie through GeoMakie, with no
  `using CairoMakie` of its own (the course's `using CairoMakie, GeoMakie` still loads it and CairoMakie
  draws); it now holds `dcf` too, so `LogjamCairoMakieExt` is deleted (0 course calls to `dcf`). The OpenStreetMap
  extension (`LogjamOSMExt`, downloads only) and the Nominatim extension are as they were. `makemap`,
  `plotroads!`, `plotroute!` and `dcf` are declared in core (`function makemap end`) with every docstring, and
  the extension adds their methods, so `methods(plotroads!)` lists its `show_connectors` keyword where it listed
  the stub's `kwargs...`, and a keyword typo fails at the call; the first method of `makemap` is its no-argument
  one, written out with every keyword (default arguments had made it a method whose list read `...`), so the
  course's `logjam_kwargs`, which prints the first method's keywords, lists them for `makemap` as well; the
  manual builds without Makie, as it did.
  The nine forwarding `Ref`s and their stubs are gone but Nominatim's query function, which the tests swap to
  stand in for the network. A call made without its extension is a `MethodError` whose hint names what to
  load (`using CairoMakie, GeoMakie` for the four map functions, `using LightOSM` for a download), and is silent
  on any other error; where a stub threw an `ErrorException` with its own text, a call without the extension
  is now that `MethodError`, and a wrong first argument to a `makemap` cell method (`makemap(5, x, y)`) is a
  `MethodError`, where it was an `ArgumentError`, because the cell is typed `Makie.GridPosition` (a cell of a
  nested layout, `fig[1, 1][1, 2]`, is not accepted; no lecture draws one). `[weakdeps]` and `[compat]` are
  unchanged, so CairoMakie's compat cap keeps binding a course environment. **Migration:** none for a
  script that loads CairoMakie and GeoMakie, as every lecture does; a script that loaded CairoMakie alone for
  `dcf()` loads GeoMakie too. The README's table of what each `using` enables is changed to match.
- **`faf5nodes()` and `faf5links()` read their CSV once per session and return copies (MAP, C12).** Every call
  re-read the file (measured on Julia 1.12.6 with the shipped data: 0.4 s and 0.8 s after the first call, which
  takes 1.6 s and 1.0 s with loading), and a lecture that calls them twice (Lecture 2.5's `dotmap` calls both
  inside a function) paid for it each time. The tables are now kept after the first read and each call
  returns a copy (3 ms for the nodes, 16 ms for the links, so a later call takes 4 ms and 18 ms); the first call
  takes what it took, plus the copy. A caller may add a column or filter in place without changing the next
  call's table (tested, and pinned against the values before the change). The cache holds both tables, about as
  much memory again as the two the caller has. `usstates()`, `countries()` and `faf5interstateroads()` were
  cached already and are not renamed or exported here. **No migration.**
- **The OpenStreetMap extension loads on `using LightOSM` alone (principle 9).** Its trigger was LightOSM and
  NearestNeighbors, and the extension used NearestNeighbors only for `stitchnetworks`, removed above. The
  line Lecture 4.2 and a homework write, `using LightOSM, NearestNeighbors`, still loads it
  (`test/test_osm.jl` loads the extension with each form in a fresh process and reads a saved pair);
  `using LightOSM` now does too. The error a download without the extension throws says `using LightOSM`.
  **Migration:** none; NearestNeighbors need no longer be installed for `osm_roads`.
- **LightOSM compat is `0.3` (0.3.x only), where it read `0.3 - 0`, which admitted every later release (maintenance).** The
  extension calls two of LightOSM's internal functions (`overpass_bbox_network_query`, `graph_from_file`),
  so a LightOSM update can break a download with no offline test failing; the bound moves only with a
  checked release.
- **The README and the example notebook install Logjam from the tag (maintenance).** The install line reads
  `Pkg.add(url="https://github.com/mgkay/Logjam", rev="v0.3.0")`, so the line keeps installing this release
  after later ones.
- **Documenter checks every exported or `public` name (`checkdocs = :public`; DT, D10).** The manual lists
  `scanTW`, `_osm_cache_path` and `_osm_snap_bbox`, which it lacked.
  Documentation only; the manual needs nothing from a user.
- **CI runs Linux and Windows on Julia 1.12, 1.13 and the prerelease, with the current action versions; the
  CompatHelper workflow installs Julia itself (maintenance)** (the runner image no longer ships it, so the daily run
  failed with `julia: command not found`). The `Artifacts`, `LazyArtifacts` and `Random` standard libraries
  have `compat` entries. A test default that named a local folder (`LOGJAM_LECTURE_DATA`, and the networked
  tests' tile folder, now `LOGJAM_TEST_CACHE_DIR`) is read from the environment only; unset, those tests
  are skipped, as they are in CI.
- **`rte2loc` and `isorigin` are typed (N20).** `rte2loc`'s default truck was `(b = [], e = [])`, so
  `vcat(Any[], Vector{Int}, Any[])` made every location sequence a `Vector{Any}` and every route cost
  inside `twoopt`, `mincostinsert` and `savings` indexed the matrix through dynamic dispatch; the default
  is now `(b = Int[], e = Int[])` and `isorigin` keeps its seen-set in the route's element type. The
  values are unchanged (every pinned call of the course returns what it returned,
  `test/test_routing_pins.jl`); a truck passed as `(b = [], e = [])` still works. The same default is
  `rteTC`'s. Matlog's degenerate-location rule (a depot route that returns to the depot midway is more
  than one route) is kept as the internal `Logjam._isdegenerate`, which the checked route cost uses for its
  exit flag -1; `rte2loc` itself still returns the sequence of such a route, as the scalar `rteTC`
  prices it (Matlog's returns `NaN`).
- **`savings` keeps its own insertion (CR 38, CR 39).** The internal `_savings` and `_insert_route` take an
  `insert` function (default `mincostinsert`, so every call is unchanged); there is no public keyword.
  The test suite passes Matlog's `mincostinsert.m` position set (a skip of a delivery directly after a
  stop at the same location, which on a depot route forbids delivering first) and so reproduces
  MATLAB's routes on makeRouting3.m Exs. 1 to 4 and 6 exactly, while `savings` itself finds a shorter
  route on Ex. 1 (1,205.50 against MATLAB's 1,271.57).
- **NF/EF wording (PR #13).** The `ufladd`, `ufldrop`, `uflxchg`, `ufl`, `pmedian` and
  `ala` docstrings and `ala`'s error messages use the new-facility (NF) and
  existing-facility (EF) terms throughout; `ufl`'s example shows its default trace.
  Documentation only.
- **CairoMakie compat capped at `0.12 - 0.15.15` (PR #18)**, because GeoMakie 0.7.17
  did not precompile against Makie 0.24.16.
- **Workflow keep-alive (maintenance)** (`ae1bbcd`): an empty commit that reset GitHub's 60-day
  inactivity clock for the scheduled CI workflow. No content change.
- **Repository hygiene (maintenance).** The Jupyter checkpoint copies under `src/.ipynb_checkpoints/`
  and `test/.ipynb_checkpoints/` are no longer tracked (and no longer ship with the
  package); `.ipynb_checkpoints/` is ignored. Paths in `test/test_osm.jl` and `tools/`
  updated for the 2026-09-01 move of the development tree.
- **HTTP and JSON3 in the test target (maintenance)**, so the Nominatim extension now loads in every
  test run (checked offline, no query sent) and `test_nominatim.jl` loads its trigger
  packages itself.
- **`loc2lonlat` reads its cache once per call (N14).** The vector method used to re-read and
  rewrite the cache file once per element; the vector and DataFrame methods now read it
  once and append once, also when the call stops on an error, so entries resolved
  before the error are kept.

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
