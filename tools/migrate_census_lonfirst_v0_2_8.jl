# migrate_census_lonfirst_v0_2_8.jl
#
# One-off, re-runnable migration for Logjam v0.2.8, component K1.
#
# For each of the 8 census tables in ../data:
#   - swap the adjacent LAT,LON columns so LON immediately precedes LAT
#     (all other columns keep their positions and values)
#   - apply the per-table type/casing fix:
#       uscentract.ST : String3 -> Symbol
#       uscsa.NAME    : Union{Missing,String} -> String   (C2 guard: no missing)
#       uscbsa        : M_MSA::String31 replaced IN PLACE by IS_MSA::Bool
#                       (true == "Metropolitan Statistical Area")
#
# Integrity guards (build fully + pass ALL asserts BEFORE writing anything):
#   C1: nrow unchanged; every untouched column byte-equal (isequal) old vs new;
#       changed columns satisfy their semantic mapping.
#   C2: uscsa.NAME scanned for missing first; HALT if any found.
#
# Re-runnable: a table already LON-first is detected and skipped (idempotent).
# Rollback safety net: the data files are git-tracked.

import Pkg
Pkg.activate(raw"C:/Users/kay/Documents/cdev/teach/ISE754-dev")
using DataFrames, Serialization, CSV   # InlineStrings loaded transitively on deserialize

const DATA_DIR = abspath(joinpath(@__DIR__, "..", "data"))
const TABLES = ["usplace", "uscounty", "uscentract", "uscenblkgrp",
                "uszcta5", "uszcta3", "uscbsa", "uscsa"]
const METRO = "Metropolitan Statistical Area"

# Return the column-name order with the adjacent LAT,LON pair swapped so LON
# comes first. Asserts LAT is immediately before LON.
function lonfirst_order(cols::Vector{String})
    i = findfirst(==("LAT"), cols)
    j = findfirst(==("LON"), cols)
    i === nothing && error("no LAT column")
    j === nothing && error("no LON column")
    j == i + 1 || error("LAT not immediately before LON (LAT=$i, LON=$j)")
    out = copy(cols)
    out[i], out[i+1] = out[i+1], out[i]   # -> LON, LAT
    return out
end

# Build the migrated DataFrame for table `t` from `old`.
function build_new(t::String, old::DataFrame)
    order = lonfirst_order(names(old))
    if t == "uscbsa"
        replace!(order, "M_MSA" => "IS_MSA")   # same position
    end
    pairs = Vector{Pair{String,AbstractVector}}()
    for name in order
        if t == "uscentract" && name == "ST"
            push!(pairs, name => Symbol.(old.ST))
        elseif t == "uscsa" && name == "NAME"
            push!(pairs, name => String.(old.NAME))
        elseif t == "uscbsa" && name == "IS_MSA"
            push!(pairs, name => (old.M_MSA .== METRO))
        else
            push!(pairs, name => old[!, name])
        end
    end
    return DataFrame(pairs...)   # copycols=true by default
end

# All integrity asserts. Throws on any failure -> nothing written.
function check!(t::String, old::DataFrame, new::DataFrame)
    @assert nrow(new) == nrow(old) "$t: row count changed ($(nrow(old)) -> $(nrow(new)))"

    # LON-first order.
    li = findfirst(==("LAT"), names(new))
    lo = findfirst(==("LON"), names(new))
    @assert lo < li "$t: LON not before LAT after migration"

    changed = Set{String}()   # columns whose values legitimately differ
    if t == "uscentract"; push!(changed, "ST"); end
    if t == "uscsa"; push!(changed, "NAME"); end
    if t == "uscbsa"; push!(changed, "M_MSA", "IS_MSA"); end

    # Every column present in both frames (by name), except the changed ones,
    # must be byte-equal.
    common = intersect(Set(names(old)), Set(names(new)))
    for c in common
        c in changed && continue
        @assert isequal(new[!, c], old[!, c]) "$t: untouched column $c differs"
    end

    # Semantic mappings for the changed columns.
    if t == "uscentract"
        @assert Symbol.(old.ST) == new.ST "$t: ST Symbol mapping failed"
        @assert eltype(new.ST) <: Symbol "$t: ST eltype not Symbol"
    elseif t == "uscsa"
        @assert String.(old.NAME) == new.NAME "$t: NAME string mapping failed"
        @assert eltype(new.NAME) == String "$t: NAME eltype not String"
    elseif t == "uscbsa"
        @assert !("M_MSA" in names(new)) "$t: M_MSA still present"
        @assert eltype(new.IS_MSA) == Bool "$t: IS_MSA eltype not Bool"
        @assert (old.M_MSA .== METRO) == new.IS_MSA "$t: IS_MSA mapping failed"
        # IS_MSA sits where M_MSA was.
        @assert findfirst(==("IS_MSA"), names(new)) == findfirst(==("M_MSA"), names(old)) "$t: IS_MSA moved"
    end
    return nothing
end

function migrate()
    for t in TABLES
        jls = joinpath(DATA_DIR, t * ".jls")
        csv = joinpath(DATA_DIR, t * ".csv")
        old = open(deserialize, jls)

        # Idempotency: skip if already LON-first.
        if findfirst(==("LON"), names(old)) < findfirst(==("LAT"), names(old))
            println("SKIP  $t : already LON-first")
            continue
        end

        # C2: uscsa NAME missing pre-scan -> HALT if any.
        if t == "uscsa"
            nmiss = count(ismissing, old.NAME)
            nmiss == 0 || error("HALT $t: uscsa.NAME has $nmiss missing value(s); refusing to coerce")
        end

        new = build_new(t, old)
        check!(t, old, new)          # throws before any write on failure

        serialize(jls, new)
        CSV.write(csv, new)          # comma-containing NAME quoted by default
        println("OK    $t : nrow=$(nrow(new))  cols=", join(names(new), ","))
    end
    println("DONE")
end

migrate()
