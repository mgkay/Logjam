# test_place_labels.jl -- the tests of PL (PCV, Logjam v0.3.1): the short place names of `usplace()`'s `LABEL` column
# and `Logjam._place_label`, which makes them (src/datatools.jl), by round `v031pl`'s rulings PL-1 to PL-4.
#   1. `_place_label` on every example of his PL-2 card, on the 17 names with a second name in parentheses (PL-3), on
#      names whose small words stay (rule 4), on Alaska's "and borough", and on names no rule may touch;
#   2. the table: `LABEL` the last column, a `String`; the columns before it the table at the start of PL (1236fcc), by
#      element and column type and by the SHA-256 of the CSV CSV.jl writes of them, which is that commit's
#      data/usplace.csv; the committed CSV tools/data/make_usplace.jl's output byte for byte, and the .jls that CSV
#      read back; no label empty or ending in a designation; `LABEL == NAME` wherever no rule applies, a shorter
#      label wherever one does, each label the start of its `NAME` or the name in its parentheses;
#   3. the number of names each rule changed and the labels longer than 25 characters (PL-4), as the script printed.
# The script itself is not run here: it reads the Census files, which are outside the repository. Its two runs, with
# the label step off (byte for byte 1236fcc's data/usplace.csv) and on, are in PL's row of the build record.

using Test
using Logjam
using DataFrames
using CSV

# SHA by its package id, as test_datatools.jl reaches it (not a dependency of the test target)
const _PL_SHA = Base.require(Base.PkgId(Base.UUID("ea8e919c-243c-51af-8825-aaa63cd721ce"), "SHA"))
_pl_sha(b) = bytes2hex(_PL_SHA.sha256(b))
_pl_lf(path) = (b = read(path); b[b .!= UInt8('\r')])          # the file as committed: a Windows checkout may add CRs
_pl_csv(df) = (io = IOBuffer(); CSV.write(io, df); take!(io))

# 1236fcc's data/usplace.csv (the table at the start of PL), and the committed CSV with LABEL, as the script printed
# them (Julia 1.12.6; the label step off, then on, two runs each)
const _PL_SHA_START = "48a74278d1d2eb5774b47ef2f27f2d2df40a3201de0968b6484d16d496d86b46"
const _PL_SHA_LABEL = "6029f48b9419393700fee01385acd8719b46da3ec14bf772a522148f2d8420f5"
const _PL_START_NAMES = ["STFIP", "PLFIP", "NAME", "ST", "LON", "LAT", "POP", "ALAND", "AWATER", "LSAD", "FUNCSTAT",
                         "CBSA", "ISCUS"]
const _PL_START_TYPES = [Int64, Int64, String, Symbol, Float64, Float64, Int64, Float64, Float64, CSV.String3,
                         CSV.String1, Union{Missing, Int64}, Bool]

# his PL-2 card's list of designations, rule 1, and "(balance)", rule 2
const _PL_DESIGNATIONS = ["CDP", "village", "borough", "municipality", "metroship", "corporation", "urban county",
                          "unified government", "consolidated government", "metropolitan government",
                          "metro government", "(balance)"]

# the examples of his PL-2 card, as `usplace()` names them
const _PL_CARD = [
    "Indianapolis (balance)" => "Indianapolis",
    "Nashville-Davidson metropolitan government (balance)" => "Nashville-Davidson",
    "Louisville/Jefferson County metro government (balance)" => "Louisville/Jefferson",
    "Urban Honolulu CDP" => "Urban Honolulu",
    "Lexington-Fayette urban county" => "Lexington-Fayette",
    "Anchorage municipality" => "Anchorage",
    "Augusta-Richmond County consolidated government (balance)" => "Augusta-Richmond",
    "Macon-Bibb County" => "Macon-Bibb",
    "Athens-Clarke County unified government (balance)" => "Athens-Clarke",
    "Schaumburg village" => "Schaumburg",
    "Arlington CDP" => "Arlington",
    "Arlington" => "Arlington",
    "Lynchburg, Moore County metropolitan government" => "Lynchburg"]

# PL-3: the 17 names with a second name in parentheses, before and after
const _PL_PARENS = [
    "El Paso de Robles (Paso Robles)" => "Paso Robles",
    "San Buenaventura (Ventura)" => "Ventura",
    "Village of Oak Creek (Big Park) CDP" => "Big Park",
    "Fredonia (Biscoe)" => "Biscoe",
    "Raymer (New Raymer)" => "New Raymer",
    "Howard City (Boelus) village" => "Boelus",
    "Canton City (Hensel)" => "Hensel",
    "Centerville (Thurman) village" => "Thurman",
    "Gann (Brinkhaven) village" => "Brinkhaven",
    "Hartford (Croton) village" => "Croton",
    "Rome (Stout) village" => "Stout",
    "Penn State Erie (Behrend) CDP" => "Behrend",
    "Tharptown (Uniontown) CDP" => "Uniontown",
    "Krupp (Marlin)" => "Marlin",
    "Addison (Webster Springs)" => "Webster Springs",
    "Bath (Berkeley Springs)" => "Berkeley Springs",
    "Womelsdorf (Coalton)" => "Coalton"]

# rule 4, the small words inside a name stay (Cardiff-by-the-Sea is no 2020 place, so it is a name given, not one of
# the table's), and the names a rule must leave as they are or only partly change
const _PL_KEEP = [
    "Coeur d'Alene" => "Coeur d'Alene",
    "Isle of Palms" => "Isle of Palms",
    "Cardiff-by-the-Sea" => "Cardiff-by-the-Sea",
    "Carmel-by-the-Sea" => "Carmel-by-the-Sea",
    "Lake in the Hills village" => "Lake in the Hills",
    "Village of Four Seasons village" => "Village of Four Seasons",
    "Avenue B and C CDP" => "Avenue B and C",
    "Echols County consolidated government" => "Echols County",          # a place named for its county alone
    "Webster County unified government" => "Webster County",
    "Greeley County unified government (balance)" => "Greeley County",
    "County Line" => "County Line",
    "County Center CDP" => "County Center",
    "Kansas City" => "Kansas City",                                      # a capitalized "City" is part of the name
    "Islamorada, Village of Islands village" => "Islamorada",
    "Hartsville/Trousdale County" => "Hartsville/Trousdale",
    "Anaconda-Deer Lodge County" => "Anaconda-Deer Lodge",
    "Butte-Silver Bow (balance)" => "Butte-Silver Bow",
    "Kearns metroship" => "Kearns",                                      # the Census's "metro township"
    "Ranson corporation" => "Ranson",
    "Juneau and borough" => "Juneau",                                    # the Census's "city and borough"
    "Sitka and borough" => "Sitka",
    "Wrangell and borough" => "Wrangell",
    " CDP" => " CDP"]                                                    # a rule that would leave nothing

# whether any rule of PL-2 or PL-3 applies to a name, stated apart from `_place_label`
_pl_applies(n) = any(d -> endswith(n, " " * d), _PL_DESIGNATIONS) || occursin(',', n) ||
                 (endswith(n, " County") && occursin(r"[-/]", chopsuffix(n, " County"))) ||
                 occursin(r"\S \([^()]+\)$", n)

@testset "[PL] _place_label: his PL-2 card, the 17 parenthetical names (PL-3), the small words and the edges" begin
    for (n, l) in _PL_CARD
        @test Logjam._place_label(n) == l
    end
    for (n, l) in _PL_PARENS
        @test Logjam._place_label(n) == l
    end
    for (n, l) in _PL_KEEP
        @test Logjam._place_label(n) == l
    end
    # a SubString is a name too, and the result is a String
    r = Logjam._place_label(SubString("Schaumburg village!", 1, 18))
    @test r isa String && r == "Schaumburg"
    # the rules applied, in order, for the counts the script prints
    a = String[]
    @test Logjam._place_label("Athens-Clarke County unified government (balance)"; applied = a) == "Athens-Clarke"
    @test a == ["(balance)", "unified government", "County"]
    a = String[]
    Logjam._place_label("Raleigh"; applied = a)
    @test isempty(a)
end

@testset "[PL] usplace(): LABEL appended, every other column the table at the start of PL" begin
    df = usplace()
    @test names(df) == [_PL_START_NAMES; "LABEL"]
    @test eltype(df.LABEL) == String && df.LABEL isa Vector{String}
    # the columns before LABEL: 1236fcc's names, element types, column types and values
    old = select(df, Not(:LABEL))
    @test eltype.(eachcol(old)) == _PL_START_TYPES
    @test all(n -> old[!, n] isa Vector, setdiff(names(old), ["LSAD", "FUNCSTAT"]))
    @test nameof(typeof(old.LSAD)) == nameof(typeof(old.FUNCSTAT)) == :PooledArray
    @test _pl_sha(_pl_csv(old)) == _PL_SHA_START
    # the committed CSV is the script's output byte for byte, and the .jls is that CSV read back
    csv = _pl_lf(joinpath(pkgdir(Logjam), "data", "usplace.csv"))
    @test _pl_sha(csv) == _PL_SHA_LABEL
    back = CSV.read(IOBuffer(csv), DataFrame; ntasks = 1, types = Dict(:NAME => String, :LABEL => String))
    back.ST = Symbol.(back.ST)
    @test isequal(back, df) && eltype.(eachcol(back)) == eltype.(eachcol(df))
    # each line of the CSV is 1236fcc's line with "," and the label after it (no label needs quoting)
    lines = split(String(copy(csv)), '\n')[1:end-1]
    oldlines = split(String(_pl_csv(old)), '\n')[1:end-1]
    @test lines[1] == oldlines[1] * ",LABEL"
    @test all(lines[i+1] == oldlines[i+1] * "," * df.LABEL[i] for i in 1:nrow(df))
end

@testset "[PL] usplace().LABEL: the rules on all 31,617 names" begin
    df = usplace()
    @test nrow(df) == 31_617
    @test Logjam._place_label.(df.NAME) == df.LABEL                     # the data is the function's output
    @test all(!isempty, df.LABEL) && all(l -> l == strip(l), df.LABEL)
    @test !any(l -> any(d -> endswith(l, " " * d), _PL_DESIGNATIONS), df.LABEL)
    @test !any(l -> occursin(r" (city|town|and|of|the)$", l), df.LABEL)    # no remnant of a designation ("Juneau and")
    @test count(l -> islowercase(first(last(split(l, ' ')))), df.LABEL) == 1 # "Coeur d'Alene" the only lowercase end
    @test !any(l -> occursin(',', l) || occursin('(', l), df.LABEL)
    # LABEL == NAME wherever no rule applies, shorter wherever one does, and the start of its NAME or the name in
    # its parentheses
    none = .!_pl_applies.(df.NAME)
    @test df.LABEL[none] == df.NAME[none]
    @test all(length.(df.LABEL[.!none]) .< length.(df.NAME[.!none]))
    @test (count(none), count(.!none)) == (14_532, 17_085)
    @test all(startswith(n, l) || occursin("(" * l * ")", n) for (n, l) in zip(df.NAME, df.LABEL))
    # the table's own examples
    lab(name, st) = only(df.LABEL[(df.NAME .== name) .& (df.ST .== st)])
    @test lab("Athens-Clarke County unified government (balance)", :GA) == "Athens-Clarke"
    @test lab("Raleigh", :NC) == "Raleigh" && lab("Durham", :NC) == "Durham"
    @test lab("San Buenaventura (Ventura)", :CA) == "Ventura"
    @test lab("Juneau and borough", :AK) == "Juneau"
    # the names each rule changed, as tools/data/make_usplace.jl printed them
    counts = Dict{String, Int}()
    for n in df.NAME
        a = String[]
        Logjam._place_label(n; applied = a)
        for r in unique(a)
            counts[r] = get(counts, r, 0) + 1
        end
    end
    @test counts == Dict("CDP" => 12_098, "village" => 3_732, "borough" => 1_216, "parentheses" => 17,
                         "(balance)" => 8, "County" => 8, "metroship" => 5, "unified government" => 5,
                         "municipality" => 4, "and borough" => 3, "comma" => 2, "consolidated government" => 2,
                         "metropolitan government" => 2, "corporation" => 1, "metro government" => 1,
                         "urban county" => 1)
    # PL-3: the 17, as listed; PL-4: the labels longer than 25 characters are left as the rules give them
    par = [n => l for (n, l) in zip(df.NAME, df.LABEL)
           if occursin(r"\S \([^()]+\)( (CDP|village))?$", n) && !occursin("(balance)", n)]
    @test sort(par) == sort(_PL_PARENS)
    long = df.LABEL[length.(df.LABEL) .> 25]
    @test length(long) == 46 && maximum(length, long) == 44
    @test "The University of Virginia's College at Wise" in long && "Rochester Institute of Technology" in long
end
