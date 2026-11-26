# =============================================================================
# Inventory measures (E1): the Poisson measures of Lecture 6.2's base-stock and reorder-point models and
# Lecture 6.3's arrival process. Each body is the lecture's definition in the lecture's operation order, so a
# call returns exactly (`==`) what the lecture's inline definition returns. Declared `public`, not exported
# (D10): each is a port whose body is a lecture's lesson, so a lecture's own definition of the name, made after
# `using Logjam`, does not collide with it.
# =============================================================================

"""
    Logjam.poissoncdf(j, μ) -> Float64

``F(j; μ) = \\Pr(D_L ≤ j)``, the probability of `j` or fewer demands during a lead time when the demand
during a lead time, ``D_L``, is Poisson with mean `μ` (Lecture 6.2's `@eq-poisson-lt`; `μ` = ``r_a t_e``,
the arrival rate times the lead time).

The terms are summed one at a time, each probability from the one before it,
``\\Pr(D_L = ℓ) = \\Pr(D_L = ℓ - 1) \\, μ/ℓ``, starting from ``\\Pr(D_L = 0) = e^{-μ}``, as is done by hand, so no
factorial is ever formed.

# Arguments
- `j`: the number of demands, `0, 1, 2, ...`.
- `μ`: the mean demand during a lead time.

# Example
Lecture 6.2's Ex. 2, six demands a period and a lead time of 1/8 period, so `μ = 0.75`:

```jldoctest
julia> round(Logjam.poissoncdf(3, 0.75); digits = 5)
0.99271
```

# Notes
- Reproduces `POISSON.DIST(j, μ, TRUE)` of the ISE 453 F25 spreadsheet `Inventory.xlsx`, sheets [BS Pois]
  and [RP Pois], column B.
- Lecture 6.2 defines it (Code block 9) and Lecture 6.3 repeats it (Code block 16); this is that definition.
"""
function poissoncdf(j, μ)
    pℓ = exp(-μ)                  # Pr(D_L = 0)
    F = pℓ                        # F(0; μ)
    for ℓ in 1:j
        pℓ *= μ/ℓ                 # Pr(D_L = ℓ), from Pr(D_L = ℓ - 1)
        F += pℓ                   # F(ℓ; μ), from F(ℓ - 1; μ)
    end
    return F
end

"""
    Logjam.pi0(qmax, μ) -> Float64

``π_0(q_{\\max}) = \\Pr(D_L ≥ q_{\\max}) = 1 - F(q_{\\max} - 1; μ)``, the fraction of demand out of stock in a
base-stock system with a maximum of `qmax` units, Poisson demand and a constant lead time (Lecture 6.2's
`@eq-bs-pi0`): the probability that a demand finds no unit on hand, by PASTA the fraction of the time with
none on hand. With `qmax = 0` nothing is ever on hand, so ``π_0 = 1``, set directly.

# Arguments
- `qmax`: the maximum inventory level ``q_{\\max}``, `0, 1, 2, ...`.
- `μ`: the mean demand during a lead time (``r_a t_e``).

# Example
Lecture 6.2's Ex. 3(a), `μ = 0.75` and a maximum of 3 units:

```jldoctest
julia> round(Logjam.pi0(3, 0.75); digits = 5)
0.04051
```

# Notes
- Reproduces column C of [BS Pois] in the ISE 453 F25 spreadsheet `Inventory.xlsx`, one minus column B.
- Lecture 6.2 defines it in the implementation of its base-stock model for Poisson demand, and Lecture 6.3
  repeats it in its make-to-stock model; this is that definition, with `Logjam.poissoncdf` as ``F(j; μ)``.
- Where ``F(q_{\\max} - 1; μ)`` rounds to one or a unit in the last place above it, far in the tail, the result
  is 0 or `-2.2e-16`, as the lectures' definition gives.
- `Logjam.pi0(qo, qmin, μ)` is the reorder-point measure.
"""
pi0(qmax, μ) = qmax == 0 ? 1.0 : 1 - poissoncdf(qmax - 1, μ)

"""
    Logjam.qbar(qmax, μ) -> Float64

``\\bar q(q_{\\max}) = \\mathbb{E}[(q_{\\max} - D_L)^+] = \\sum_{j = 0}^{q_{\\max} - 1} F(j; μ)``, the average
inventory on hand in a base-stock system with a maximum of `qmax` units, Poisson demand and a constant lead time
(Lecture 6.2's `@eq-bs-qbar`): the expected units of ``q_{\\max}`` left after the demand during a lead time.
`qbar(0, μ)` is `0.0`.

# Arguments
- `qmax`: the maximum inventory level ``q_{\\max}``, `0, 1, 2, ...`.
- `μ`: the mean demand during a lead time (``r_a t_e``).

# Example
Lecture 6.2's Ex. 3(a), `μ = 0.75` and a maximum of 3 units:

```jldoctest
julia> round(Logjam.qbar(3, 0.75); digits = 5)
2.2585
```

# Notes
- Reproduces column D of [BS Pois] in the ISE 453 F25 spreadsheet `Inventory.xlsx`, the running sum of
  column B, and column D of [RP Pois], the safety stock at an order point of `qmax`.
- Lecture 6.2 defines it in the implementation of its base-stock model for Poisson demand, and Lecture 6.3
  repeats it in its make-to-stock model; this is that definition, with `Logjam.poissoncdf` as ``F(j; μ)``.
- `Logjam.qbar(qo, qmin, μ)` is the reorder-point measure.
"""
qbar(qmax, μ) = sum(poissoncdf(j, μ) for j in 0:qmax-1; init = 0.0)

"""
    Logjam.pi0(qo, qmin, μ) -> Float64

``π_0(q_o, q_{\\min}) = \\frac{1}{q_o} \\sum_{ℓ = 1}^{q_o} π_0(q_{\\min} + ℓ)``, the fraction of demand out of stock
in a reorder-point system that orders `qo` units when the inventory position falls to `qmin`, Poisson demand and a
constant lead time (Lecture 6.2's `@eq-rp-pi0`): base stock's ``π_0`` averaged over the levels ``q_{\\min} + 1`` to
``q_{\\min} + q_o`` the inventory position passes through.

At `qo = 1` it is base stock's at ``q_{\\max} = q_{\\min} + 1``, `Logjam.pi0(qmin + 1, μ)`.

# Arguments
- `qo`: the order quantity ``q_o``, `1, 2, ...`.
- `qmin`: the order point ``q_{\\min}``, `0, 1, 2, ...`.
- `μ`: the mean demand during a lead time (``r_a t_e``).

# Example
Lecture 6.2's Ex. 7, `μ = 0.75`, ordering 5 units at an order point of 2:

```jldoctest
julia> round(Logjam.pi0(5, 2, 0.75); digits = 5)
0.0098

julia> Logjam.pi0(1, 2, 0.75) == Logjam.pi0(3, 0.75)
true
```

# Notes
- [RP Pois] in the ISE 453 F25 spreadsheet `Inventory.xlsx` tabulates the cycle form ``1 - F(q_{\\min}; μ)``
  (Lecture 6.2's `@eq-rp-cycle`), which is the first term of this average and equals it at `qo = 1` (its
  column C). Lecture 6.2 explains why its model averages over the levels instead: the cycle form overstates the
  sales lost, and the average at `qo = 1` is base stock's.
- Lecture 6.2 defines it as `pi0rp` in the implementation of its reorder-point model for Poisson demand; this is
  that definition, a method of `pi0` taking three arguments.
"""
pi0(qo, qmin, μ) = sum(pi0(qmin + ℓ, μ) for ℓ in 1:qo)/qo

"""
    Logjam.qbar(qo, qmin, μ) -> Float64

``\\bar q(q_o, q_{\\min}) = \\frac{1}{q_o} \\sum_{ℓ = 1}^{q_o} \\bar q(q_{\\min} + ℓ)``, the average inventory on hand
in a reorder-point system that orders `qo` units when the inventory position falls to `qmin`, Poisson demand and a
constant lead time (Lecture 6.2's `@eq-rp-qbar`): base stock's ``\\bar q`` averaged over the levels
``q_{\\min} + 1`` to ``q_{\\min} + q_o`` the inventory position passes through.

At `qo = 1` it is base stock's at ``q_{\\max} = q_{\\min} + 1``, `Logjam.qbar(qmin + 1, μ)`.

# Arguments
- `qo`: the order quantity ``q_o``, `1, 2, ...`.
- `qmin`: the order point ``q_{\\min}``, `0, 1, 2, ...`.
- `μ`: the mean demand during a lead time (``r_a t_e``).

# Example
Lecture 6.2's Ex. 7, `μ = 0.75`, ordering 5 units at an order point of 2:

```jldoctest
julia> round(Logjam.qbar(5, 2, 0.75); digits = 5)
4.25198

julia> Logjam.qbar(1, 2, 0.75) == Logjam.qbar(3, 0.75)
true
```

# Notes
- [RP Pois] in the ISE 453 F25 spreadsheet `Inventory.xlsx` tabulates the cycle form, safety stock plus half an
  order, ``\\bar q(q_{\\min}) + q_o/2`` (Lecture 6.2's `@eq-rp-safety` and `@eq-rp-qbar-cycle`; the safety stock
  is its column D, `Logjam.qbar(qmin, μ)`). Lecture 6.2 explains why its model averages over the levels instead:
  at `qo = 1` the cycle form does not give base stock's average on hand, and the average does.
- Lecture 6.2 defines it as `qbarrp` in the implementation of its reorder-point model for Poisson demand; this is
  that definition, a method of `qbar` taking three arguments.
"""
qbar(qo, qmin, μ) = sum(qbar(qmin + ℓ, μ) for ℓ in 1:qo)/qo

"""
    Logjam.poissarr(lmb, n = 1; rng = Random.default_rng()) -> Vector{Float64}

The arrival times of a Poisson process, nonhomogeneous when its rate differs from period to period (Lecture
6.3's arrival process): arrivals are generated at the peak rate, `maximum(lmb)`, by summing exponential
interarrival times, and each arrival in period `i` is kept with probability `lmb[i]/maximum(lmb)`, so the
arrivals kept are a Poisson process at each period's own rate.

A quarter more interarrival times are drawn than the expected number of arrivals at the peak rate, and a
quarter more again whenever they do not reach the end of the last period.

# Arguments
- `lmb`: the arrival rate of each period, ``r_a(t)``; `lmb[i]` is the rate of period `i`, the interval
  `[i - 1, i)`. A scalar is one rate for all `n` periods.
- `n`: the number of periods, for a scalar `lmb` only (`n > 1` with a vector `lmb` is an error).
- `rng`: the random-number generator (any `AbstractRNG`) the exponential and uniform draws are taken from, as in
  `rng = Xoshiro(1)`. The default, the global stream, makes a call after `Random.seed!(s)` return what Lecture
  6.3's definition returns after the same seed.

# Returns
- The arrival times, sorted, in `[0, n*length(lmb))`; those in `[i - 1, i)` are period `i`'s.

# Example
Lecture 6.3's barbershop, eight hours open at its arrival rates per hour:

```jldoctest
julia> using Random

julia> ra = [5, 7, 20, 32, 6, 15, 45, 12];

julia> t = Logjam.poissarr(ra; rng = Xoshiro(1));

julia> issorted(t) && all(0 .<= t .< 8)
true

julia> t == Logjam.poissarr(ra; rng = Xoshiro(1))
true
```

# Notes
- Lecture 6.3 defines it (Code block 3) to simulate a day's queue; this is that definition, every draw taken
  from `rng`.
- Source: the MATLAB `poissarr.m` of ISE 453's nonstationary cycle-time material, which Lecture 6.3 ports in
  its shape; its `exprnd` and `rand` draws are `randexp` and `rand` here, and its echo of the extension counter
  is dropped. On the same exponential and uniform draws the two keep the same arrivals, at times that agree to a
  few units in the last place: Julia's `cumsum` adds pairwise, MATLAB's in order.
"""
function poissarr(lmb, n = 1; rng::AbstractRNG = default_rng())
    # lmb = n-element vector of arrival rates, where lmb[i] is the rate
    #       for time period i
    #   n = number of periods, if scalar lmb
    #   t = vector of variates, where t[j] between [(i-1), i) correspond
    #       to period i arrivals
    if n > 1 && length(lmb) > 1
        error("\"n\" > 1 only for scalar \"lmb\".")
    end
    lmax = maximum(lmb)             # the peak rate
    t = cumsum(randexp(rng, ceil(Int, n*1.25*length(lmb)*lmax))/lmax)
    done = false
    while !done
        if t[end] > n*length(lmb)
            done = true
            t = t[t .< n*length(lmb)]
        else                        # extend by a quarter as many
            more = ceil(Int, n*0.25*length(lmb)*lmax)
            t = [t; t[end] .+ cumsum(randexp(rng, more)/lmax)]
        end
    end
    if !isempty(t) && length(lmb) > 1   # Thin if nonhomogeneous
        rnd = rand(rng, length(t))
        for i in 1:length(lmb)
            t[(i - 1 .<= t .< i) .& (rnd .> lmb[i]/lmax)] .= NaN
        end
        t = t[.!isnan.(t)]
    end
    return t
end
