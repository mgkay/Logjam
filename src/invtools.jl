# =============================================================================
# Inventory measures (E1): the Poisson measures of Lecture 6.2's base-stock and reorder-point models. Each body
# is the lecture's definition in the lecture's operation order, so a call returns exactly (`==`) what the
# lecture's inline definition returns. Declared `public`, not exported (D10): each is a port whose body is a
# lecture's lesson, so a lecture's own definition of the name, made after `using Logjam`, does not collide with
# it.
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
