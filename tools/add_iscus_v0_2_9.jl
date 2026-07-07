# add_iscus_v0_2_9.jl
#
# One-off, re-runnable migration for Logjam v0.2.9.
#
# Adds an `ISCUS::Bool` column ("within continental U.S.") to the three
# US-prefixed census loaders that lack it, so all eight carry the field:
#     uscounty, uscenblkgrp, uscsa
# ISCUS is computed per row from (LON, LAT) against the continental-U.S.
# bounding box, appended as the FINAL column. All other columns keep their
# positions and values.
#
# CONUS test (inlined, byte-identical to Logjam's exported `isptinbbox`,
# datatools.jl): pt inside bbox iff LONmin <= LON <= LONmax and
# LATmin <= LAT <= LATmax (inclusive on all four bounds). Box is the same
# ((-125,-65),(24,50)) used to build ISCUS for the existing five loaders.
#
# Guards (build fully + pass ALL asserts BEFORE writing anything):
#   Preflight: recompute ISCUS on the five loaders that ALREADY carry it and
#              assert it reproduces the shipped column exactly -> proves the box.
#   Per table: HALT if LON/LAT has any missing value (never coerce);
#              nrow unchanged; every pre-existing column byte-equal (isequal);
#              ISCUS is the only new column, is Bool, and is last.
#
# Re-runnable: a table that already has ISCUS is detected and skipped.
# Rollback safety net: the data files are git-tracked.

import Pkg
Pkg.activate(raw"C:/Users/kay/Documents/cdev/teach/ISE754-dev")
using DataFrames, Serialization, CSV   # InlineStrings loaded transitively on deserialize

const DATA_DIR = abspath(joinpath(@__DIR__, "..", "data"))
const CUS_BOX = ((-125.0, -65.0), (24.0, 50.0))   # ((LONmin,LONmax),(LATmin,LATmax))
const TARGETS = ["uscounty", "uscenblkgrp", "uscsa"]
const HAVE_ISCUS = ["usplace", "uscentract", "uszcta5", "uszcta3", "uscbsa"]

# Continental-U.S. membership for one (LON, LAT), inclusive bounds.
iscus(lon, lat) = lon >= CUS_BOX[1][1] && lon <= CUS_BOX[1][2] &&
                  lat >= CUS_BOX[2][1] && lat <= CUS_BOX[2][2]

# Vector of Bool ISCUS values for a frame (fresh per row, not aggregated).
iscus_col(df::DataFrame) = Bool[iscus(lon, lat) for (lon, lat) in zip(df.LON, df.LAT)]

# Prove the box: recomputing ISCUS from LON/LAT must reproduce the shipped
# ISCUS on every loader that already has it. HALT on any mismatch.
function preflight()
    for t in HAVE_ISCUS
        df = open(deserialize, joinpath(DATA_DIR, t * ".jls"))
        "ISCUS" in names(df) || error("PREFLIGHT $t: expected an existing ISCUS column, none found")
        recomputed = iscus_col(df)
        recomputed == df.ISCUS ||
            error("PREFLIGHT $t: recomputed ISCUS differs from shipped ($(count(recomputed .!= df.ISCUS)) rows); box is wrong")
        println("PREFLIGHT OK  $t : ISCUS reproduced ($(count(df.ISCUS)) of $(nrow(df)) continental)")
    end
end

function migrate()
    preflight()
    for t in TARGETS
        jls = joinpath(DATA_DIR, t * ".jls")
        csv = joinpath(DATA_DIR, t * ".csv")
        old = open(deserialize, jls)

        # Idempotency: skip if ISCUS already present.
        if "ISCUS" in names(old)
            println("SKIP  $t : already has ISCUS")
            continue
        end

        # Missing-value pre-scan on LON/LAT -> HALT if any (never coerce).
        for col in (:LON, :LAT)
            nmiss = count(ismissing, old[!, col])
            nmiss == 0 || error("HALT $t: $col has $nmiss missing value(s); refusing to compute ISCUS")
        end

        oldnames = names(old)
        new = copy(old)
        new.ISCUS = iscus_col(old)

        # Integrity asserts (throw before any write on failure).
        @assert nrow(new) == nrow(old) "$t: row count changed ($(nrow(old)) -> $(nrow(new)))"
        @assert names(new) == vcat(oldnames, "ISCUS") "$t: ISCUS is not the only new column / not last"
        @assert eltype(new.ISCUS) == Bool "$t: ISCUS eltype not Bool"
        for c in oldnames
            @assert isequal(new[!, c], old[!, c]) "$t: pre-existing column $c differs"
        end

        serialize(jls, new)
        CSV.write(csv, new)
        println("OK    $t : nrow=$(nrow(new))  ISCUS=$(count(new.ISCUS)) continental  cols=", join(names(new), ","))
    end
    println("DONE")
end

migrate()
