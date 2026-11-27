# make_zcta_stfip.jl -- append STFIP, the state of each ZIP Code Tabulation Area, to Logjam's `uszcta5` and `uszcta3`
# tables (PCV WP5 of v0.3.1; MakePlan D4, his "accept" at Gate 1).
#
#   julia +1.12.6 --project=<repo> tools/v0_3_1/make_zcta_stfip.jl <relationship file> [<output directory>]
#
# INPUT, the one argument required: the path of
#   U.S. Census Bureau, 2020 ZCTA to County Relationship File, national (vintage 2020: 2020 ZCTA5s to 2020 counties),
#   https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_county20_natl.txt
#   6,821,287 bytes, SHA-256 3ed41278d637dc249e0323306f68be8a6c234e3090f4de88ef328dee71aeaaaf.
# The file is not committed. Its size and SHA-256 are checked before it is read, and it is read as text: "|"-separated,
# one row for each part of a ZCTA in a county (GEOID_ZCTA5_20, GEOID_COUNTY_20, and the part's land and water area in
# square meters, AREALAND_PART and AREAWATER_PART); a row with no ZCTA is a county's area outside every ZCTA and is
# skipped. A county's state is the first two digits of its GEOID.
#
# THE RULE (D4):
#   - a five-digit ZCTA takes the state holding the largest share of its land area, its county parts' AREALAND_PART
#     summed by state;
#   - a ZCTA with no land takes the state holding the largest share of its water area (AREAWATER_PART);
#   - a tie goes to the smaller state FIPS code;
#   - a three-digit ZCTA takes the state holding the most land summed over its five-digit members (the ZCTA5s of
#     `uszcta5` whose first three digits are its code, uszcta3 being their aggregate), each member's county parts
#     counted in the state that holds them; with no land, the most water; a tie to the smaller FIPS code.
# The 40 Puerto Rico ZCTAs (009xx) must come out 72, and do; the script stops if not. Every ZCTA of the two tables
# must be in the file: one that is not is a stop, never a guess.
#
# OUTPUT, to the repository's data/ (or to <output directory>, for a trial run):
#   - uszcta5.csv, uszcta3.csv: STFIP (Int64, the element type of usplace().STFIP) appended as the LAST column. Every
#     existing column keeps its name, order, element type and value, which the script asserts before it writes: each
#     line of the new file is the line of the table as committed (read back from data/, line endings normalized to
#     LF) with "," and the state appended. Rows in their existing order, LF line endings, no time stamps, so a run
#     gives the same bytes every time (CSV.jl's writer; the existing columns were already written by it).
#   - uszcta5.jls, uszcta3.jls: regenerated from the CSV just written, read back; the script asserts that the table
#     read back is the old .jls with STFIP appended, value for value and type for type.
#   - zcta_state_parts.csv (to test/data/ of the repository, or to <output directory>): the extract the tests recompute
#     the rule from, one row for each (ZCTA5, state) of every ZCTA5 of `uszcta5` that is either cross-state or a
#     member of a three-digit ZCTA whose members lie in more than one state: ZCTA5, STFIP, ALAND_M2, AWATER_M2 (the
#     ZCTA's county parts in that state, summed), sorted by ZCTA5 and STFIP.
# Re-runnable: a table that already has STFIP has it set aside, recomputed and checked equal, and is written again
# byte for byte. Prints each written file's SHA-256, the number of cross-state ZCTAs with five examples and their land
# shares, the Puerto Rico check, and the three-digit ZCTAs whose state a member-by-member count (each member wholly in
# its own STFIP) would give otherwise.
#
# Run at v0.3.1 (Julia 1.12.6, twice, from the v0.3.0 tables and again from its own output; the same bytes each time):
#   uszcta5.csv  SHA-256 fee98453f863f4ac6e93eaf7cbabf8a6ad5431d72ff139af32f616ba173e1adc  (33,682 rows)
#   uszcta3.csv  SHA-256 7c60ed0ff6859b6b33c7e91a5c2e7f2688fb66c873a165450765f1897881dcac  (890 rows)
#   zcta_state_parts.csv  SHA-256 8c442f6d4577b9ccdde6cd7dbc0a5f2cbefcee309eabf786766062503ddcfbc6  (3,784 rows)
#   137 cross-state ZCTA5s, none with no land, no tie; the 40 009xx ZCTA5s 72; 91 three-digit ZCTAs with members in
#   two or more states, for none of which the member-by-member count differs. ZCTA3 967 (Hawaii's): the file also has
#   96799 (American Samoa), which uszcta5 does not hold.

using DataFrames, CSV, Serialization, SHA, Printf

const REL_URL = "https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_county20_natl.txt"
const REL_BYTES = 6_821_287
const REL_SHA256 = "3ed41278d637dc249e0323306f68be8a6c234e3090f4de88ef328dee71aeaaaf"
const REPO = abspath(joinpath(@__DIR__, "..", ".."))
const DATA = joinpath(REPO, "data")

# ---- the relationship file: land and water in m² for each (ZCTA5, state) ---------------------------------------
function read_parts(path)
    filesize(path) == REL_BYTES || error("$path: $(filesize(path)) bytes, not the $REL_BYTES of $REL_URL")
    h = bytes2hex(open(sha256, path))
    h == REL_SHA256 || error("$path: SHA-256 $h, not $REL_SHA256 ($REL_URL)")
    lines = readlines(path)
    hdr = [lstrip(f, '﻿') for f in split(lines[1], '|')]
    col(n) = something(findfirst(==(n), hdr), 0) > 0 ? findfirst(==(n), hdr) : error("no column $n in $path")
    iz, ic, il, iw = col("GEOID_ZCTA5_20"), col("GEOID_COUNTY_20"), col("AREALAND_PART"), col("AREAWATER_PART")
    parts = Dict{Int, Dict{Int, NTuple{2, Int}}}()       # ZCTA5 => state => (land, water)
    for l in @view lines[2:end]
        f = split(l, '|')
        isempty(f[iz]) && continue                       # a county's area outside every ZCTA
        occursin(r"^\d{5}$", f[iz]) && occursin(r"^\d{5}$", f[ic]) || error("unexpected row: $l")
        z, st = parse(Int, f[iz]), parse(Int, f[ic][1:2])
        d = get!(parts, z, Dict{Int, NTuple{2, Int}}())
        a = get(d, st, (0, 0))
        d[st] = (a[1] + parse(Int, f[il]), a[2] + parse(Int, f[iw]))
    end
    return parts
end

# the state holding the most land, else the most water; a tie to the smaller FIPS code
function pick(d::AbstractDict{Int, NTuple{2, Int}})
    sts = sort!(collect(keys(d)))
    k = sum(d[s][1] for s in sts) > 0 ? 1 : 2
    best = sts[1]
    for s in sts
        d[s][k] > d[best][k] && (best = s)               # strictly greater: the smaller code keeps a tie
    end
    return best
end

# ---- a table as committed: its .jls, any STFIP set aside, and its CSV lines (LF) -----------------------------------
function committed(name)
    df = open(deserialize, joinpath(DATA, name * ".jls"))
    lines = split(replace(read(joinpath(DATA, name * ".csv"), String), "\r\n" => "\n"), '\n')
    isempty(lines[end]) && pop!(lines)
    old_stfip = nothing
    if "STFIP" in names(df)
        names(df)[end] == "STFIP" || error("$name: STFIP is not the last column")
        old_stfip = copy(df.STFIP)
        df = select(df, Not(:STFIP))
        lines = [String(chopsuffix(l, "," * split(l, ',')[end])) for l in lines]
    end
    return df, String.(lines), old_stfip
end

csvbytes(df) = (io = IOBuffer(); CSV.write(io, df); take!(io))

function write_table(out, name, base::DataFrame, lines::Vector{String}, stfip::Vector{Int}, old_stfip)
    old_stfip === nothing || old_stfip == stfip || error("$name: the STFIP already there differs from the rule's")
    # the existing columns as committed: CSV.jl's writer reproduces the committed file's lines exactly
    String(csvbytes(base)) == join(lines, '\n') * '\n' || error("$name: the committed CSV is not CSV.write of its .jls")
    new = copy(base)
    new.STFIP = stfip
    b = csvbytes(new)
    nl = split(String(copy(b)), '\n')                                  # String(v) would empty `b`
    pop!(nl)                                                          # the final newline
    length(nl) == length(lines) || error("$name: line count changed")
    nl[1] == lines[1] * ",STFIP" || error("$name: header")
    all(nl[i+1] == lines[i+1] * "," * string(stfip[i]) for i in eachindex(stfip)) ||
        error("$name: an existing column's text changed")
    count(==(UInt8('\r')), b) == 0 || error("$name: CR in output")
    # the .jls from the CSV read back: the old table with STFIP appended, value for value and type for type
    back = CSV.read(IOBuffer(b), DataFrame; ntasks = 1)
    names(back) == vcat(names(base), "STFIP") || error("$name: names")
    for (n, c) in zip(names(new), eachcol(new))
        typeof(back[!, n]) == typeof(c) || error("$name: column $n reads back as $(typeof(back[!, n])), not $(typeof(c))")
        isequal(back[!, n], c) || error("$name: column $n reads back changed")
    end
    eltype(back.STFIP) == Int64 || error("$name: STFIP eltype")
    csvp, jlsp = joinpath(out, name * ".csv"), joinpath(out, name * ".jls")
    write(csvp, b)
    serialize(jlsp, back)
    j = open(deserialize, jlsp)
    (isequal(j, back) && eltype.(eachcol(j)) == eltype.(eachcol(back))) || error("$name: .jls does not read back")
    @printf("wrote %-12s %8d rows  csv sha256 %s\n", name, nrow(back), bytes2hex(sha256(b)))
    @printf("      %-12s            jls sha256 %s\n", "", bytes2hex(open(sha256, jlsp)))
end

function main(relpath, out = DATA)
    isdir(out) || mkpath(out)
    parts = read_parts(relpath)
    z5, l5, old5 = committed("uszcta5")
    z3, l3, old3 = committed("uszcta3")
    eltype(z5.ZCTA5) == Int64 && eltype(z3.ZCTA3) == Int64 || error("ZCTA codes are not Int64")

    # five-digit
    miss = [z for z in z5.ZCTA5 if !haskey(parts, z)]
    isempty(miss) || error("STOP: ZCTAs of uszcta5 not in the relationship file: $miss")
    st5 = Int[pick(parts[z]) for z in z5.ZCTA5]
    pr = findall(z -> 900 <= z <= 999, z5.ZCTA5)
    println("Puerto Rico (009xx): ", length(pr), " ZCTAs, STFIP ", unique(st5[pr]),
            ", ISCUS ", unique(z5.ISCUS[pr]))
    (length(pr) == 40 && all(==(72), st5[pr])) || error("STOP: the 009xx ZCTAs do not all come out 72")
    cross = [i for (i, z) in enumerate(z5.ZCTA5) if length(parts[z]) > 1]
    noland = [z for z in z5.ZCTA5 if sum(v[1] for v in values(parts[z])) == 0]
    ties = [z for z in z5.ZCTA5 if (d = parts[z]; k = sum(v[1] for v in values(d)) > 0 ? 1 : 2;
                                    count(v -> v[k] == maximum(w[k] for w in values(d)), collect(values(d))) > 1)]
    println("cross-state ZCTAs in uszcta5: ", length(cross), " of ", nrow(z5), "; with no land: ", length(noland),
            "; ties: ", length(ties), (isempty(ties) ? "" : " $ties"))
    for i in cross[round.(Int, range(1, length(cross), length = 5))]
        d = parts[z5.ZCTA5[i]]; tl = sum(v[1] for v in values(d))
        shares = join([@sprintf("%02d %.4f", s, d[s][1] / tl) for s in sort!(collect(keys(d)))], ", ")
        @printf("  ZCTA %05d: land shares by state %s -> STFIP %02d\n", z5.ZCTA5[i], shares, st5[i])
    end

    # three-digit
    members = Dict{Int, Vector{Int}}()
    for (i, z) in enumerate(z5.ZCTA5)
        push!(get!(members, z ÷ 100, Int[]), i)
    end
    filez3 = Dict{Int, Set{Int}}()
    for z in keys(parts)
        push!(get!(filez3, z ÷ 100, Set{Int}()), z)
    end
    st3 = Int[]
    differ = Int[]
    mixed = Set{Int}()
    for c in z3.ZCTA3
        haskey(members, c) || error("STOP: ZCTA3 $c has no member in uszcta5")
        extra = setdiff(filez3[c], Set(z5.ZCTA5[members[c]]))
        isempty(extra) || println("note: ZCTA3 $c: the file also has ZCTA5 $(sort!(collect(extra))), which uszcta5 ",
                                  "does not; uszcta5's members are used")
        issubset(Set(z5.ZCTA5[members[c]]), filez3[c]) || error("STOP: ZCTA3 $c has members the file lacks")
        agg = Dict{Int, NTuple{2, Int}}()
        for i in members[c], (s, v) in parts[z5.ZCTA5[i]]
            a = get(agg, s, (0, 0)); agg[s] = (a[1] + v[1], a[2] + v[2])
        end
        s = pick(agg)
        push!(st3, s)
        length(agg) > 1 && push!(mixed, c)
        # the other reading: each member wholly in its own state
        whole = Dict{Int, NTuple{2, Int}}()
        for i in members[c]
            d = parts[z5.ZCTA5[i]]; a = get(whole, st5[i], (0, 0))
            whole[st5[i]] = (a[1] + sum(v[1] for v in values(d)), a[2] + sum(v[2] for v in values(d)))
        end
        pick(whole) == s || push!(differ, c)
    end
    println("three-digit ZCTAs whose members lie in more than one state: ", length(mixed), " of ", nrow(z3),
            "; whose state a member-by-member count would give otherwise: ", isempty(differ) ? "none" : differ)
    all(==(72), st3[z3.ZCTA3 .== 9]) || error("STOP: ZCTA3 009 is not 72")

    write_table(out, "uszcta5", z5, l5, st5, old5)
    write_table(out, "uszcta3", z3, l3, st3, old3)

    # the tests' extract
    keep = sort!(unique(vcat(z5.ZCTA5[cross], [z5.ZCTA5[i] for c in mixed for i in members[c]])))
    ex = DataFrame(ZCTA5 = Int[], STFIP = Int[], ALAND_M2 = Int[], AWATER_M2 = Int[])
    for z in keep, s in sort!(collect(keys(parts[z])))
        push!(ex, (z, s, parts[z][s]...))
    end
    expath = out == DATA ? joinpath(REPO, "test", "data", "zcta_state_parts.csv") : joinpath(out, "zcta_state_parts.csv")
    io = IOBuffer()
    println(io, "# The land and water (m²) of each ZCTA5 of uszcta5() in each state, its county parts summed, for every")
    println(io, "# ZCTA5 that is cross-state or a member of a three-digit ZCTA whose members lie in more than one state.")
    println(io, "# Extracted by tools/v0_3_1/make_zcta_stfip.jl from the U.S. Census Bureau's 2020 ZCTA to County")
    println(io, "# Relationship File, $REL_URL")
    println(io, "# (SHA-256 $REL_SHA256); test/test_geodata_v031.jl recomputes STFIP from it.")
    CSV.write(io, ex; append = false, writeheader = true)
    eb = take!(io)
    write(expath, eb)
    @printf("wrote %-12s %8d rows  csv sha256 %s  (%d ZCTA5s, %d bytes)\n", "extract", nrow(ex),
            bytes2hex(sha256(eb)), length(keep), length(eb))
end

length(ARGS) in (1, 2) || error("usage: make_zcta_stfip.jl <relationship file> [<output directory>]")
main(ARGS...)
