# test_prt_columns.jl -- prt's decimals per column and Matlog's fractional-column rule (PCV K14, ruling PR).
# The oracle is test/oracles/mdisp_digits.csv, written by tools/v0_3_0/make_mdisp_oracle.m (MATLAB R2025a,
# Matlog V18's mdisp, one column per case, the decimals it printed). The moved pins are in test_prt_pins.jl.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "oracle_helpers.jl"))   # _readoracle, _sc, _fvec

# the decimals prt printed for the numbers of a one-column table (rows after the header line); -1 for none
function _printed_decimals(s::AbstractString)
    dig = -1
    for l in split(strip(s, '\n'), '\n')[2:end]
        t = match(r"\s(\S+)$", strip(l))
        t === nothing && continue
        tok = t.captures[1]
        any(isletter, tok) && continue
        p = findfirst('.', tok)
        dk = p === nothing ? 0 : length(tok) - p
        dig == -1 ? (dig = dk) : @test dig == dk
    end
    return dig
end

@testset "prt: Matlog's fractional-column rule equals mdisp (PR)" begin
    d = _readoracle("mdisp_digits")
    n = Int(_sc(d, "n"))
    @test n == 77
    for i in 1:n
        X = _fvec(d, "X_$i")
        fd, af = Int.(vec(d["par_$i"]))
        dig = Int(_sc(d, "dig_$i"))
        s = Logjam.prt(reshape(X, :, 1); fracdig = fd, allfrac = af, str = true)
        @test _printed_decimals(s) == dig
        dig >= 0 && @test Logjam._coldigits(X, fd, af) == dig
    end
end

@testset "prt: a column of fractions drops the digits that are zero in every value (PR)" begin
    # Matlog's examples of the rule, and the course's columns it changes (the sources are in the pins)
    @test Logjam.prt([0.45, 0.449]; str = true) == "        \n1  0.450\n2  0.449\n"
    @test Logjam.prt([0.5, 0.25]; str = true) == "       \n1  0.50\n2  0.25\n"
    @test Logjam.prt([0.5, 0.5, 0.5]; str = true) == "      \n1  0.5\n2  0.5\n3  0.5\n"
    # 2.7 Code block 18's utilization, rounded to three places in the call, prints as the three places it has
    @test Logjam.prt(DataFrame(ZIP = [270, 272], util = [0.857, 0.753]); str = true) ==
          "   ZIP   util\n1  270  0.857\n2  272  0.753\n"
    # a value with all four places keeps them; so does a value with more
    @test Logjam.prt([0.0336, 0.0405]; str = true) == "         \n1  0.0336\n2  0.0405\n"
    @test Logjam.prt([0.123456, 0.5]; str = true) == "         \n1  0.1235\n2  0.5000\n"
    # the digits are tested on the values, not on the text: 0.07 * 10^k is not an integer for k = 1 or 2
    @test Logjam._coldigits([0.07, 0.07], 2, 4) == 3
    # a NaN or missing leaves the column at `allfrac` places, as mdisp does; an Inf takes no part
    @test Logjam.prt([0.5, NaN]; str = true) == "         \n1  0.5000\n2        \n"
    @test Logjam.prt(DataFrame(v = Union{Missing,Float64}[0.5, missing]); str = true) ==
          "        v\n1  0.5000\n2        \n"
    @test Logjam._coldigits([0.5, Inf], 2, 4) == 1
    # mixed columns keep a fixed `fracdig`: money keeps its trailing zeros (S12)
    @test Logjam.prt(DataFrame(TC = [1357.2, 20.0]); str = true) == "         TC\n1  1,357.20\n2     20.00\n"
    @test Logjam.prt([0.5, 1.5]; str = true) == "       \n1  0.50\n2  1.50\n"
    # allfrac as the largest number of places, from 0 up
    @test Logjam.prt([0.15, 0.25]; allfrac = 1, str = true) == "      \n1  0.2\n2  0.2\n"
    @test Logjam._coldigits([0.5, 0.25], 2, 0) == 0
    @test Logjam._coldigits([0.5, 0.25], 2, 6) == 2
    # an integer column and an all-NaN column are unchanged
    @test Logjam._coldigits([1.0, 2.0], 2, 4) == 0
    @test Logjam._coldigits([NaN, NaN], 2, 4) == 2
end

@testset "prt: decimals per column (PR)" begin
    df = DataFrame(Radius = [11.8, 12.0], rmse = [0.00188, 0.0021], share = [0.5, 0.25])
    # the defaults, then a specification that names some columns
    @test Logjam.prt(df; str = true) == "   Radius    rmse  share\n1   11.80  0.0019   0.50\n2   12.00  0.0021   0.25\n"
    s = Logjam.prt(df; fracdig = (Radius = 1, rmse = 5), str = true)
    @test s == "   Radius     rmse  share\n1    11.8  0.00188   0.50\n2    12.0  0.00210   0.25\n"
    # a Dict, with Symbol or String keys, is the same specification
    @test Logjam.prt(df; fracdig = Dict(:Radius => 1, :rmse => 5), str = true) == s
    @test Logjam.prt(df; fracdig = Dict("Radius" => 1, "rmse" => 5), str = true) == s
    # `allfrac` names columns of fractions, and wins over a `fracdig` entry for the same column
    @test Logjam.prt(df; allfrac = (rmse = 5,), str = true) ==
          "   Radius     rmse  share\n1   11.80  0.00188   0.50\n2   12.00  0.00210   0.25\n"
    @test Logjam.prt(df; fracdig = (rmse = 5,), allfrac = (rmse = 3,), str = true) ==
          "   Radius   rmse  share\n1   11.80  0.002   0.50\n2   12.00  0.002   0.25\n"
    # `fracdig` for a column that is mixed, and an `allfrac` for a column that is not a column of fractions
    @test Logjam.prt(DataFrame(a = [1.5, 22.25]); fracdig = (a = 1,), allfrac = (a = 6,), str = true) ==
          "      a\n1   1.5\n2  22.2\n"
    # a scalar keeps today's meaning
    @test Logjam.prt(df; fracdig = 3, str = true) == "   Radius    rmse  share\n1  11.800  0.0019   0.50\n2  12.000  0.0021   0.25\n"
    # a matrix takes a vector, one entry per column
    X = [11.8 0.00188; 12.0 0.0021]
    @test Logjam.prt(X; fracdig = [1, 5], str = true) == "      1        2\n1  11.8  0.00188\n2  12.0  0.00210\n"
    @test Logjam.prt(X; fracdig = [1, 5], allfrac = [4, 5], str = true) == Logjam.prt(X; fracdig = [1, 5], str = true)
    # and a vector (one column) a vector of one entry
    @test Logjam.prt([0.00188, 0.0021]; fracdig = [5], str = true) == "          \n1  0.00188\n2  0.00210\n"
    # a specification that does not fit is an error that names what is wrong
    @test_throws ArgumentError Logjam.prt(X; fracdig = [1, 2, 3], str = true)
    @test_throws ArgumentError Logjam.prt(df; fracdig = (Radius = 1, rms = 5), str = true)
    @test_throws ArgumentError Logjam.prt(df; allfrac = Dict(:nope => 1), str = true)
    @test_throws ArgumentError Logjam.prt([0.5, 0.25]; fracdig = (a = 1,), str = true)
    err = try Logjam.prt(df; fracdig = (rms = 5,), str = true) catch e e end
    @test occursin("\"rms\"", err.msg) && occursin("\"rmse\"", err.msg)
    # a text column is unaffected by a specification that names it
    @test Logjam.prt(DataFrame(s = ["a", "b"], v = [0.5, 0.25]); fracdig = (s = 3,), str = true) ==
          "  s     v\n  a  0.50\n  b  0.25\n"
    # the DataFrame method takes any AbstractDataFrame
    @test Logjam.prt(view(df, 1:1, :); str = true) == Logjam.prt(df[1:1, :]; str = true)
    @test Logjam.prt(first(df, 1); fracdig = (rmse = 5,), str = true) isa String
end
