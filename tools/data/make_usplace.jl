# make_usplace.jl -- Logjam's place table, `usplace()` (data/usplace.csv and data/usplace.jls), made from the U.S.
# Census Bureau's files: Logjam's processing of the place data, so that a new Census release goes through the same
# steps (PCV PL of v0.3.1; round `v031pl`, his direction of 2026-11-28).
#
#   julia +1.12.6 --project=<repo> tools/data/make_usplace.jl <raw-data directory> [<output directory>] [--nolabel]
#
# INPUT, the one argument required: a directory holding the three files below (none is committed; Logjam's copies
# are in makeLogjam/rawdata/). Each file's size and SHA-256 are checked before it is read; a file that differs is a
# stop. A new release is read by putting its files' names, sizes and SHA-256s in `INPUTS`. The URLs are where the
# Census publishes each file; the script makes no network call.
#   1. 2020_Gaz_place_national.txt: U.S. Census Bureau, 2020 Gazetteer Files, Places (the places of the 2020 Census,
#      the 50 states, the District of Columbia and Puerto Rico), tab-separated, the file in
#        https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_place_national.zip
#      6,413,985 bytes, SHA-256 aba21bc4138ae2d45f79bf4fd2cb8f969f4cd21a7ca79163447265cab9b8c7b3. Its last column's
#      name, INTPTLONG, is padded with spaces in the file, so the column is found by its stripped name.
#   2. DECENNIALPL2020.P1-Data.csv: U.S. Census Bureau, 2020 Census Redistricting Data (Public Law 94-171), table P1
#      (Race), every place, as data.census.gov exports it (a second header row of labels, then one row per place);
#      only GEO_ID ("1600000US" and the place's seven-digit GEOID) and P1_001N (total population) are read,
#        https://data.census.gov/table/DECENNIALPL2020.P1?g=010XX00US$1600000
#      11,170,003 bytes, SHA-256 e61f8c7977e3118bafbba242bb95074932551552740ea10ac4968797bf86617f. (The 2020
#      Demographic and Housing Characteristics File's table P1, which `usplace`'s docstring cites, gives the same total
#      for each of the 31,617 places, checked at v0.3.1.)
#   3. list2_2023.csv: U.S. Census Bureau, 2023 delineation files, list 2, principal cities of metropolitan and
#      micropolitan statistical areas, published as
#        https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list2_2023.xlsx
#      and saved as CSV: the row of column names first, one row per principal city, the title and note rows of the
#      sheet removed (Latin-1 text; only the numeric columns "CBSA Code", "FIPS State Code" and "FIPS Place Code" are
#      read), 101,891 bytes, SHA-256 b9a796615848446e8cbccfc1472c39d86e1f55d3f181695fd015a1a8193ed44f.
#
# THE STEPS, every step that made the table v0.3.0 ships (`git log data/usplace.csv`): the place cells of
# makeLogjam/notebooks/makeAggDemandData_good.ipynb (cells 2, 4, 5 and 6), then v0.2.8's change to this table
# (tools/migrate_census_lonfirst_v0_2_8.jl, and the change of `ST` to `Symbol` made in the .jls before it), then
# v0.3.1's `LABEL`:
#   1. the Gazetteer: `GEOID` as seven digits, `STFIP` its first two and `PLFIP` its last five; `NAME` with every " city"
#      and every " town" removed (the notebook's `replace`, so "Raleigh city" is "Raleigh" and "Kearns metro township"
#      is "Kearns metroship");
#   2. the population: P1_001N as `POP`, joined to the Gazetteer on GEOID (an inner join, so a place in one file only
#      is dropped), in the Gazetteer's order; the columns `STFIP`, `PLFIP`, `NAME`, `ST` (USPS), `LAT` (INTPTLAT),
#      `LON` (INTPTLONG), `POP`, `ALAND` (ALAND_SQMI), `AWATER` (AWATER_SQMI), `LSAD`, `FUNCSTAT`; the rows with
#      `STFIP` above 56 (Puerto Rico) dropped;
#   3. `CBSA`, the code of the statistical area of which the place is a principal city, by a left join on (`STFIP`,
#      `PLFIP`), `missing` for any other place. The rows come in the order the notebook's `leftjoin` gave them (in
#      DataFrames 1.x): the principal cities first, then the other places, each in the Gazetteer's order. That order
#      is made explicit here, so that no later DataFrames can change it;
#   4. `ISCUS`, whether the place's point lies in `CUS_LIMITS`, ((-125, -65), (24, 50)), bounds included (the
#      notebook's `isptinbbox`);
#   5. `ST` a `Symbol`, and `LON` before `LAT` (v0.2.8);
#   6. `LABEL`, the place's short name for a map label, `Logjam._place_label(NAME)` (round `v031pl`, rulings PL-2 to
#      PL-4; the rules are in its docstring and `usplace`'s), appended as the last column. `--nolabel` skips this step.
# The script checks that no GEOID repeats in either of the first two files and that no place matches two rows of
# list 2, so that each join keeps one row per place, and the element type of every column.
#
# OUTPUT, to the repository's data/ (or to <output directory>, for a trial run):
#   - usplace.csv, written by CSV.jl's writer: LF line endings, each float in the shortest form that reads back as
#     itself, a missing `CBSA` empty, no time stamp, so every run gives the same bytes;
#   - usplace.jls: the CSV read back (`NAME` and `LABEL` as `String`, `ST` as `Symbol`, `CBSA` as a `Vector` with
#     `missing`, the other columns as CSV.jl reads them: `LSAD` and `FUNCSTAT` pooled `String3` and `String1`),
#     serialized; the script asserts that it is the table it built, value for value and column type for column type.
#     Logjam reads the .jls.
# Prints each file's SHA-256 and size, the number of names each label rule changed, the labels longer than 25
# characters, and the number of labels two or more places of a state share.
#
# Run at v0.3.1 (Julia 1.12.6, DataFrames 1.8.1, CSV 0.10.15):
#   with --nolabel: 31,617 places; usplace.csv SHA-256 48a74278d1d2eb5774b47ef2f27f2d2df40a3201de0968b6484d16d496d86b46
#     (2,291,889 bytes), byte for byte v0.3.0's data/usplace.csv (the same at 1236fcc, the start of PL); the .jls
#     `isequal` to v0.3.0's column by column, with the same column types (its bytes differ: a .jls is not a
#     byte-identity target, the CSV is);
#   with the label, twice, to a scratch directory and to data/, the same bytes each time: usplace.csv SHA-256
#     6029f48b9419393700fee01385acd8719b46da3ec14bf772a522148f2d8420f5 (2,611,562 bytes), usplace.jls SHA-256
#     b3d4bcbd429c46168fab8e0f58923f356e4e9cac4d6046c50f8d04a3a817f893 (2,944,751 bytes); 17,085 of the 31,617
#     names changed (CDP 12,098, village 3,732, borough 1,216, parentheses 17, "(balance)" 8, County 8, metroship 5,
#     unified government 5, municipality 4, and borough 3, comma 2, consolidated government 2, metropolitan
#     government 2, corporation 1, metro government 1, urban county 1; a name two rules change is counted under
#     both); 46 labels longer than 25 characters; 192 labels shared by two or more places of a state, 117 of them by
#     places whose NAMEs differ.

using Logjam, DataFrames, CSV, Serialization, SHA, Printf

const REPO = abspath(joinpath(@__DIR__, "..", ".."))
const DATA = joinpath(REPO, "data")

# file => (bytes, SHA-256)
const INPUTS = Dict(
    "2020_Gaz_place_national.txt" => (6_413_985, "aba21bc4138ae2d45f79bf4fd2cb8f969f4cd21a7ca79163447265cab9b8c7b3"),
    "DECENNIALPL2020.P1-Data.csv" => (11_170_003, "e61f8c7977e3118bafbba242bb95074932551552740ea10ac4968797bf86617f"),
    "list2_2023.csv"              => (101_891, "b9a796615848446e8cbccfc1472c39d86e1f55d3f181695fd015a1a8193ed44f"))

# the columns of the table and their element types, as v0.3.0 has them, then LABEL
const COLUMNS = ["STFIP" => Int64, "PLFIP" => Int64, "NAME" => String, "ST" => Symbol, "LON" => Float64,
                 "LAT" => Float64, "POP" => Int64, "ALAND" => Float64, "AWATER" => Float64, "LSAD" => CSV.String3,
                 "FUNCSTAT" => CSV.String1, "CBSA" => Union{Missing, Int64}, "ISCUS" => Bool]
const LABEL_COLUMN = "LABEL" => String

function checked(dir, name)
    path = joinpath(dir, name)
    bytes, sha = INPUTS[name]
    isfile(path) || error("STOP: no $name in $dir")
    filesize(path) == bytes || error("STOP: $path is $(filesize(path)) bytes, not $bytes")
    h = bytes2hex(open(sha256, path))
    h == sha || error("STOP: $path has SHA-256 $h, not $sha")
    println("input  ", rpad(name, 30), lpad(bytes, 10), " bytes  sha256 ", h)
    return path
end

function checkschema(df, cols, what)
    names(df) == first.(cols) || error("$what: the columns are $(names(df)), not $(first.(cols))")
    for (n, T) in cols
        eltype(df[!, n]) == T || error("$what: column $n is $(eltype(df[!, n])), not $T")
    end
end

function build(dir; label::Bool = true)
    # 1. the Gazetteer (notebook cell 2)
    df1 = DataFrame(CSV.File(checked(dir, "2020_Gaz_place_national.txt")))
    ilon = findfirst(n -> strip(n) == "INTPTLONG", names(df1))
    ilon === nothing && error("the Gazetteer has no INTPTLONG column")
    df1.LON = df1[:, ilon]
    df1.GEOID = string.(df1.GEOID, pad = 7)
    df1.STFIP = parse.(Int64, first.(df1.GEOID, 2))
    df1.PLFIP = parse.(Int64, last.(df1.GEOID, 5))
    df1.NAME = replace.(df1.NAME, r" city" => "", r" town" => "")
    allunique(df1.GEOID) || error("the Gazetteer repeats a GEOID")

    # 2. the population, joined in the Gazetteer's order (notebook cell 2)
    df2 = DataFrame(CSV.File(checked(dir, "DECENNIALPL2020.P1-Data.csv")))[:, ["GEO_ID", "P1_001N"]]
    popfirst!(df2)                                       # the row of labels below the column names
    rename!(df2, Dict("GEO_ID" => "GEOID", "P1_001N" => "POP"))
    df2.POP = parse.(Int64, df2.POP)
    df2.GEOID = replace.(df2.GEOID, r"1600000US" => "")
    allunique(df2.GEOID) || error("the population file repeats a GEOID")
    df3 = select(innerjoin(df1, df2, on = :GEOID, order = :left),
        :STFIP, :PLFIP, :NAME, :USPS => :ST, :INTPTLAT => :LAT, :LON, :POP,
        :ALAND_SQMI => :ALAND, :AWATER_SQMI => :AWATER, :LSAD, :FUNCSTAT)
    deleteat!(df3, df3.STFIP .> 56)

    # 3. the principal cities' CBSA (notebook cells 4 and 5), in the order the notebook's leftjoin gave
    df4 = DataFrame(CSV.File(checked(dir, "list2_2023.csv")))
    rename!(df4, Dict("CBSA Code" => "CBSA", "FIPS State Code" => "STFIP", "FIPS Place Code" => "PLFIP"))
    df5 = leftjoin(df3, df4[!, ["CBSA", "STFIP", "PLFIP"]], on = [:STFIP, :PLFIP], order = :left, source = :_JOIN)
    nrow(df5) == nrow(df3) || error("a place is the principal city of two statistical areas in list 2")
    df5 = df5[[findall(==("both"), df5._JOIN); findall(==("left_only"), df5._JOIN)], :]
    select!(df5, Not(:_JOIN))

    # 4. ISCUS (notebook cell 6)
    isptinbbox(pt, bbox) = (pt[1] >= bbox[1][1] && pt[1] <= bbox[1][2] &&
                            pt[2] >= bbox[2][1] && pt[2] <= bbox[2][2])
    df5.ISCUS = map((x, y) -> isptinbbox((x, y), CUS_LIMITS), df5.LON, df5.LAT)

    # 5. v0.2.8: ST a Symbol, LON before LAT
    df5.ST = Symbol.(df5.ST)
    select!(df5, first.(COLUMNS))
    checkschema(df5, COLUMNS, "the table")

    # 6. v0.3.1: LABEL, the short name for a map label
    if label
        df5.LABEL = Logjam._place_label.(df5.NAME)
        checkschema(df5, [COLUMNS; LABEL_COLUMN], "the table")
    end
    return df5
end

# the label rules' counts, the labels over 25 characters, and the labels two places of a state share
function report(df)
    counts = Dict{String, Int}()
    for n in df.NAME
        applied = String[]
        Logjam._place_label(n; applied)
        for r in unique(applied)
            counts[r] = get(counts, r, 0) + 1
        end
    end
    println("labels: ", count(df.LABEL .!= df.NAME), " of ", nrow(df), " names changed; names changed by each rule:")
    for (r, c) in sort!(collect(counts); by = x -> (-x[2], x[1]))
        println("  ", rpad(r, 26), lpad(c, 6))
    end
    long = sort!([(length(l), l, st) for (l, st) in zip(df.LABEL, df.ST) if length(l) > 25]; rev = true)
    println("labels longer than 25 characters: ", length(long))
    for (n, l, st) in long
        println("  ", lpad(n, 3), "  ", st, "  ", l)
    end
    g = Dict{Tuple{Symbol, String}, Vector{String}}()
    for (st, l, n) in zip(df.ST, df.LABEL, df.NAME)
        push!(get!(g, (st, l), String[]), n)
    end
    shared = count(v -> length(v) > 1, values(g))
    bylabel = count(v -> length(v) > 1 && length(unique(v)) > 1, values(g))
    println("labels two or more places of a state share: ", shared, " (", bylabel,
            " of them where the places' NAMEs differ, so the rules made them shared)")
end

function main(dir, out = DATA; label::Bool = true)
    isdir(dir) || error("no directory $dir")
    isdir(out) || mkpath(out)
    df = build(dir; label)
    io = IOBuffer()
    CSV.write(io, df)
    b = take!(io)
    count(==(UInt8('\r')), b) == 0 || error("CR in the CSV")
    # the .jls: the CSV read back, NAME and LABEL as String, ST as Symbol
    types = Dict{Symbol, Type}(:NAME => String)
    label && (types[:LABEL] = String)
    back = CSV.read(IOBuffer(copy(b)), DataFrame; ntasks = 1, types)
    back.ST = Symbol.(back.ST)
    for n in names(back)                                 # CBSA, which CSV.jl reads as a SentinelVector, a Vector
        T = eltype(back[!, n])
        Missing <: T && (back[!, n] = Vector{T}(back[!, n]))
    end
    checkschema(back, label ? [COLUMNS; LABEL_COLUMN] : COLUMNS, "the CSV read back")
    isequal(back, df) || error("the CSV does not read back as the table")
    typeof.(eachcol(back)) == typeof.(eachcol(df)) || error("the CSV read back has other column types than the table")
    csvp, jlsp = joinpath(out, "usplace.csv"), joinpath(out, "usplace.jls")
    write(csvp, b)
    serialize(jlsp, back)
    j = open(deserialize, jlsp)
    (isequal(j, back) && eltype.(eachcol(j)) == eltype.(eachcol(back))) || error("the .jls does not read back")
    @printf("wrote usplace.csv  %d rows  %d bytes  sha256 %s\n", nrow(df), length(b), bytes2hex(sha256(b)))
    @printf("wrote usplace.jls             %d bytes  sha256 %s\n", filesize(jlsp), bytes2hex(open(sha256, jlsp)))
    label && report(df)
    return nothing
end

let args = filter(!=("--nolabel"), ARGS)
    length(args) in (1, 2) || error("usage: make_usplace.jl <raw-data directory> [<output directory>] [--nolabel]")
    main(args...; label = !("--nolabel" in ARGS))
end
