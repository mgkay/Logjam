# make_poissarr_streams.jl -- the recorded random streams of the poissarr oracle (Logjam v0.3.1, PCV WP1, E1).
#
#   julia --startup-file=no tools/v0_3_1/make_poissarr_streams.jl
#
# Writes test/oracles/poissarr_streams.csv: for each case, a column of standard exponentials (`randexp`) and a
# column of uniforms on [0, 1) (`rand`), each drawn from its own seeded Xoshiro and written at %.17g, so the
# values read back are the values drawn. Two consumers read the same file:
#   - tools/v0_3_1/make_oracles_v031.m runs a scratch copy of MATLAB's poissarr.m whose `exprnd` and `rand`
#     return these values in order, and writes test/oracles/poissarr_matlab.csv;
#   - test/test_invtools.jl feeds them to Logjam.poissarr through a test-only AbstractRNG whose `randexp` and
#     `rand` return them in order, and compares the arrival times with MATLAB's.
# Each column is longer than its case uses (the initial draw, four extensions and 20 more); a side that ran out
# would stop with an error rather than draw elsewhere.
# Needs only Julia's standard library (Random, Printf); run it with no project.

using Random, Printf

const OUT = joinpath(@__DIR__, "..", "..", "test", "oracles", "poissarr_streams.csv")

# name, rates, periods, seed of the exponentials (the uniforms' seed is one more)
const CASES = [
    ("barbershop", [5, 7, 20, 32, 6, 15, 45, 12], 1, 20261126),   # Lecture 6.3's Code block 7, the day's rates
    ("smallday",   [5, 7, 20, 30, 4, 10, 15, 5],  1, 20261128),   # Lecture 6.3's Code block 6, the small day
    ("scalar2n3",  [2],                           3, 20261130),   # one rate for three periods
    ("scalar1",    [1],                           1, 20261132),   # one rate, one period
    ("vecslow",    [1, 2, 0.5],                   1, 20261134),   # low rates: the first draw often falls short
]

ndraw(lmb, n) = (lmax = maximum(lmb); ceil(Int, n*1.25*length(lmb)*lmax) + 4*ceil(Int, n*0.25*length(lmb)*lmax) + 20)

function main()
    open(OUT, "w") do io
        println(io, "# case: poissarr_streams")
        println(io, "# The recorded random streams of the poissarr oracle, written by tools/v0_3_1/make_poissarr_streams.jl")
        println(io, "# (Julia $(VERSION), Random.Xoshiro). For each case <c>: <c>_lmb (the rates, 1 x k), <c>_n (periods),")
        println(io, "# <c>_E (standard exponentials, randexp(Xoshiro(seed), N)) and <c>_U (uniforms, rand(Xoshiro(seed + 1), N)),")
        println(io, "# each N x 1 at %.17g. Read by tools/v0_3_1/make_oracles_v031.m and test/test_invtools.jl.")
        println(io, "# blocks: @name,nrows,ncols then nrows rows")
        for (c, lmb, n, seed) in CASES
            N = ndraw(lmb, n)
            E = randexp(Xoshiro(seed), N)
            U = rand(Xoshiro(seed + 1), N)
            println(io, "@$(c)_lmb,1,$(length(lmb))")
            println(io, join((@sprintf("%.17g", x) for x in lmb), ","))
            println(io, "@$(c)_n,1,1")
            println(io, n)
            println(io, "@$(c)_E,$N,1")
            foreach(x -> println(io, @sprintf("%.17g", x)), E)
            println(io, "@$(c)_U,$N,1")
            foreach(x -> println(io, @sprintf("%.17g", x)), U)
            # whether the initial draw reaches the end of the last period (else poissarr extends it)
            k0 = ceil(Int, n*1.25*length(lmb)*maximum(lmb))
            short = cumsum(E[1:k0]/maximum(lmb))[end] <= n*length(lmb)
            println("$c: N = $N, initial draw $k0, extended: $short")
        end
    end
    println("wrote ", normpath(OUT))
end

main()
