# DisplayTools - printing tables and numbers: prt, thousands and snapvals (split from datatools.jl in v0.3.1, A10)

# =============================================================================
# Helper Functions (H1–H4)
# =============================================================================

# The decimal places of `prt`'s `fracdig` and `allfrac`: one integer, or one entry for each column.
const _DigitSpec = Union{Integer, AbstractVector{<:Integer}, NamedTuple, AbstractDict}

"""
    prt(X; rows, cols, title, fracdig, allfrac, row_title, str)

Pretty-print a matrix, vector, or DataFrame with smart formatting.

Formatted display with right-aligned columns. Each column is formatted from its own values,
by the per-column digit rule of MATLOG's `mdisp`: integer columns show 0 decimal places, mixed
columns show `fracdig` decimal places (trailing zeros kept, so money keeps its cents), and a
column of fractions, all values below 1 in magnitude, shows at most `allfrac` decimal places:
the digits that are zero in every value of the column are dropped ("Ignore all 0 digits in
column of fractions", `mdisp.m`), so `0.45` and `0.449` print as `0.450` and `0.449`, and `0.5`
and `0.25` as `0.50` and `0.25`. Exactly: the column prints with the smallest `k` from 1 to
`allfrac` for which `abs(v) * 10.0^k` equals an integer in floating point for every finite
value `v` of the column, and with `allfrac` places when there is no such `k`. A `NaN` or `missing`
in the column leaves it at `allfrac` places, as in `mdisp`, and an `Inf` takes no part. Whole
parts of 1,000 or more get comma separators, and
a value of any magnitude prints its own digits (never scientific notation). `NaN` and `missing`
display as blank, `Inf` and `-Inf` as `Inf` and `-Inf`, a `Bool` as `true` or `false`, and any
other non-numeric value (a `String`, a `Symbol`) as its text. The `row_title` keyword places a
header in the upper-left corner of the table (the row-label column header).

# Decimal places per column
`fracdig` and `allfrac` are one integer for every column, or a specification for each:
- a vector with one entry per column, for the matrix and vector methods (a vector has one column);
- a `NamedTuple` or a `Dict` keyed by column name, for a DataFrame; a column it does not name
  keeps the default (2 and 4), and a name that is no column is an `ArgumentError`.

A column named in a `fracdig` specification shows that many places at most, whatever its values:
for a column of fractions too, unless `allfrac` names it as well, so `fracdig = (rmse = 5,)`
gives a column of small values five places. `allfrac` names only the columns of fractions.

# Matrix method
    prt(X::AbstractMatrix; rows=1:size(X,1), cols=1:size(X,2), title="", fracdig=2, allfrac=4, row_title="", str=false)

# Vector method
    prt(v::AbstractVector; rows=1:length(v), title="", fracdig=2, allfrac=4, row_title="", str=false)

# DataFrame method
    prt(df::AbstractDataFrame; rows=nothing, title="", fracdig=2, allfrac=4, row_title="", str=false)

A DataFrame column is text when its element type (ignoring `missing`) is a `String`, a `Symbol`,
a `Char` or any other non-numeric type, and numeric otherwise (`Bool` columns are numeric columns
that print `true` and `false`). A frame with only numeric columns prints with row numbers `1:nrow(df)`
as row labels, as a matrix does; a frame with any text column prints without row labels. `rows`
overrides either default.

With `str=true`, returns the formatted table as a string (separator lines stripped)
instead of printing. Default behavior prints to stdout and returns `nothing`.

# Examples
```jldoctest
prt([1000 0.1234; 2000 0.5678])

# output

       1       2
────────────────
1  1,000  0.1234
2  2,000  0.5678
```

```jldoctest
prt([1 2; 3 4]; rows=["a", "b"], cols=["X", "Y"], row_title="ID")

# output

ID  X  Y
────────
 a  1  2
 b  3  4
```

```jldoctest
using DataFrames
prt(DataFrame(site = ["a", "b"], cost = [1234.5, missing], open = [true, false]))

# output

  site      cost   open
───────────────────────
     a  1,234.50   true
     b            false
```

A column of fractions shows only the places its values have. These are the utilizations of
Lecture 2.7's Code block 18, each rounded to three places in the call:

```jldoctest
using DataFrames
prt(DataFrame(ZIP = [270, 272, 283], util = [0.857, 0.753, 0.691]))

# output

   ZIP   util
─────────────
1  270  0.857
2  272  0.753
3  283  0.691
```

A specification for each column names the places a column shows. This is Lecture 2.5's Code
block 13, whose `rmse` column of fractions needs five places to show its fifth digit (without the
specification it prints `0.0019`):

```jldoctest
using DataFrames
prt(DataFrame(linear = 0.0224, quadratic = 0.449, rmse = 0.00188); fracdig = (rmse = 5,))

# output

   linear  quadratic     rmse
─────────────────────────────
1  0.0224      0.449  0.00188
```
"""
function prt(X::AbstractMatrix; rows=1:size(X, 1), cols=1:size(X, 2),
             title::AbstractString="", fracdig::_DigitSpec=2, allfrac::_DigitSpec=4,
             row_title::AbstractString="", str::Bool=false)
    m, n = size(X)
    if m == 0 || n == 0
        str && return ""
        println("Empty matrix")
        return nothing
    end
    return _prt_table([view(X, :, j) for j in 1:n], string.(cols), string.(rows),
                      title, row_title, fracdig, allfrac, str)
end

function prt(v::AbstractVector; rows=1:length(v), title::AbstractString="",
             fracdig::_DigitSpec=2, allfrac::_DigitSpec=4,
             row_title::AbstractString="", str::Bool=false)
    prt(reshape(v, :, 1); rows=rows, cols=[""], title=title, fracdig=fracdig, allfrac=allfrac,
        row_title=row_title, str=str)
end

function prt(df::AbstractDataFrame; rows=nothing, title::AbstractString="",
             fracdig::_DigitSpec=2, allfrac::_DigitSpec=4,
             row_title::AbstractString="", str::Bool=false)
    nms = names(df)
    columns = [df[!, c] for c in nms]
    istext = [_istextcol(eltype(c)) for c in columns]
    allnumeric = !isempty(columns) && !any(istext)
    if allnumeric && nrow(df) == 0
        str && return ""
        println("Empty matrix")
        return nothing
    end
    # an all-numeric frame is numbered like a matrix; a frame with text columns is not
    rowlabels = rows === nothing ? (allnumeric ? string.(1:nrow(df)) : String[]) : string.(rows)
    return _prt_table(columns, string.(nms), rowlabels, title, row_title, fracdig, allfrac, str;
                      textcols = istext)
end

# Internal: the one pass behind every `prt` method. `columns` are the data columns; each is formatted
# from its own values (a text column as its text), then the table is laid out and printed or returned.
function _prt_table(columns, col_labels::Vector{String}, row_labels::Vector{String},
                    title::AbstractString, row_title::AbstractString,
                    fracdig::_DigitSpec, allfrac::_DigitSpec, str::Bool;
                    textcols = falses(length(columns)))
    n = length(columns)
    m = n == 0 ? 0 : length(columns[1])
    cells = Matrix{String}(undef, m, n)
    fd, fdnamed = _digitspec(fracdig, col_labels, 2, "fracdig")
    af, afnamed = _digitspec(allfrac, col_labels, 4, "allfrac")
    for j in 1:n
        # a column of fractions takes its `allfrac`; where `fracdig` names the column and `allfrac`
        # does not, the digits asked for in `fracdig` stand for it as well
        afj = afnamed[j] ? af[j] : fdnamed[j] ? fd[j] : af[j]
        nd = textcols[j] ? 0 : _coldigits(columns[j], fd[j], afj)
        for i in 1:m
            cells[i, j] = _fmtcell(columns[j][i], nd)
        end
    end
    if str
        buf = IOBuffer()
        io = IOContext(buf, :displaysize => (typemax(Int), typemax(Int)))
        _print_table(io, cells; column_labels=col_labels, row_labels=row_labels,
                     title=String(title), stubhead_label=String(row_title))
        raw = String(take!(buf))
        lines = split(raw, '\n')
        filtered = [l for l in lines if !isempty(l) && !all(c -> c == '─', l)]
        return join(filtered, '\n') * '\n'
    else
        io = IOContext(stdout, :displaysize => (typemax(Int), typemax(Int)))
        _print_table(io, cells; column_labels=col_labels, row_labels=row_labels,
                     title=String(title), stubhead_label=String(row_title))
        return nothing
    end
end

# Internal: a DataFrame column is text when its element type, ignoring `missing`, is not numeric
# (`Any` is left to the per-value rule, as a numeric-looking column).
function _istextcol(T::Type)
    S = nonmissingtype(T)
    return !(S <: Real) && S !== Any
end

# Internal: does a value take part in digit detection and numeric formatting? (`Bool` does not.)
_isnumcell(v) = v isa Real && !(v isa Bool)

# Internal: decimal places of a column, from the finite real values it holds, by Matlog's `mdisp`: none
# when they are all integers; `fracdig` when some value is 1 or more in magnitude; and for a column of
# fractions (all below 1) the smallest k from 1 to `allfrac` at which every value times 10^k is an
# integer in floating point ("Ignore all 0 digits in column of fractions"), `allfrac` when there is none.
# As in `mdisp`, a NaN (here also `missing`) in the column makes that test fail: `Xj == round(Xj)` is false
# for it, so the column keeps `allfrac` places; an Inf passes the test and takes no part.
function _coldigits(col, fracdig::Integer, allfrac::Integer)
    nreal = 0
    allint = true
    alllt1 = true
    blank = false
    for v in col
        if ismissing(v) || (_isnumcell(v) && isnan(v))
            blank = true
            continue
        end
        _isnumcell(v) && isfinite(v) || continue
        nreal += 1
        allint &= v == round(v)
        alllt1 &= abs(v) < 1
    end
    nreal == 0 && return Int(fracdig)
    allint && return 0
    alllt1 || return Int(fracdig)
    blank && return Int(allfrac)
    for k in 1:Int(allfrac)
        p = 10.0^k
        all(v -> (x = abs(v) * p; x == round(x)), (v for v in col if _isnumcell(v) && isfinite(v))) && return k
    end
    return Int(allfrac)
end

# Internal: the decimal places of each column from a `fracdig` or `allfrac` argument, and which columns it
# names. An integer is every column's and names none; a vector has one entry for each of the columns; a
# NamedTuple or Dict names some columns (by `Symbol` or `String`) and leaves the rest at `default`.
function _digitspec(spec, labels::Vector{String}, default::Integer, what::AbstractString)
    n = length(labels)
    if spec isa Integer
        return fill(Int(spec), n), falses(n)
    elseif spec isa AbstractVector
        length(spec) == n || throw(ArgumentError(
            "prt: `$what` has $(length(spec)) entries for $n columns; pass one integer, or one per column."))
        return Int.(spec), trues(n)
    end
    vals = fill(Int(default), n)
    named = falses(n)
    for (k, d) in pairs(spec)
        j = findfirst(==(String(k)), labels)
        j === nothing && throw(ArgumentError(
            "prt: `$what` names \"$k\", which is not a column (the columns are $(join(repr.(labels), ", ")))."))
        vals[j] = Int(d)
        named[j] = true
    end
    return vals, named
end

# Internal: one table cell. `nd` is the column's decimal places.
function _fmtcell(v, nd::Int)
    v isa Bool && return v ? "true" : "false"
    if v isa Real
        isnan(v) && return ""
        isinf(v) && return string(v)
        return _formatfixed(v, nd)
    end
    ismissing(v) && return ""
    return string(v)
end

# Internal: lightweight table printer replacing PrettyTables. `cells` holds the formatted text.
function _print_table(io::IO, cells::AbstractMatrix{String};
                      column_labels::Vector{String}=String[],
                      row_labels::Vector{String}=String[],
                      title::String="",
                      stubhead_label::String="")
    m, n = size(cells)

    # Column widths from data and headers
    col_widths = [maximum(length(cells[i, j]) for i in 1:m; init=0) for j in 1:n]
    if !isempty(column_labels)
        for j in 1:n
            col_widths[j] = max(col_widths[j], length(column_labels[j]))
        end
    end

    # Row label width
    has_rows = !isempty(row_labels)
    rl_width = 0
    if has_rows
        rl_width = maximum(length(l) for l in row_labels; init=0)
        if !isempty(stubhead_label)
            rl_width = max(rl_width, length(stubhead_label))
        end
    end

    # Title
    if !isempty(title)
        println(io, title)
    end

    # Header row
    if !isempty(column_labels)
        if has_rows
            print(io, lpad(stubhead_label, rl_width))
        end
        for j in 1:n
            print(io, "  ", lpad(column_labels[j], col_widths[j]))
        end
        println(io)
        # Separator
        total_w = sum(col_widths) + 2 * n + (has_rows ? rl_width : 0)
        println(io, '─'^total_w)
    end

    # Data rows
    for i in 1:m
        if has_rows
            print(io, lpad(row_labels[i], rl_width))
        end
        for j in 1:n
            print(io, "  ", lpad(cells[i, j], col_widths[j]))
        end
        println(io)
    end
end

# Internal: insert `sep` between groups of three digits of a string of digits
function _groupdigits(s::AbstractString, sep::AbstractString)
    n = length(s)
    n <= 3 && return String(s)
    head = n % 3 == 0 ? 3 : n % 3
    io = IOBuffer()
    write(io, SubString(s, 1, head))
    i = head + 1
    while i <= n
        write(io, sep, SubString(s, i, i + 2))
        i += 3
    end
    return String(take!(io))
end

# Internal: comma-separate an integer of any size
function _commasep(n::Integer; sep::AbstractString=",")
    s = string(n)
    neg = startswith(s, "-")
    return (neg ? "-" : "") * _groupdigits(neg ? SubString(s, 2) : s, sep)
end

# Internal: format a real with `ndig` decimal places (trailing zeros kept) and `sep` between the groups
# of three digits of the whole part. The one formatting core of `prt` and `thousands`. No value is
# converted to a fixed-width integer, so the value's own digits print at any magnitude; the fraction is
# digits, never `string(float)`, so no scientific notation can appear; the value is rounded first so a
# carry (1.996 at 2 places) reaches the whole part; and a value that rounds to zero prints unsigned.
function _formatfixed(v::Real, ndig::Integer; sep::AbstractString=",")
    nd = max(Int(ndig), 0)
    if v isa Integer
        return _commasep(v; sep=sep) * (nd == 0 ? "" : "." * "0"^nd)
    end
    x = v isa AbstractFloat ? v : float(v)
    isfinite(x) || return string(x)
    # `round(x, digits)` is trusted while x * 10^nd stays well inside the 53-bit significand (2^50); past
    # that it would round a product that is itself inexact, so the digits are taken from x exactly instead
    trusted = nd == 0 || abs(x) * 10.0^nd < 2.0^50
    r = nd == 0 ? round(x) : trusted ? round(x, digits=nd) : x
    neg = r < 0
    a = abs(r)
    w = floor(a)
    whole = a < 2.0^62 ? Int64(w) : BigInt(w)
    fracstr = ""
    if nd > 0
        f = a - w
        if trusted && nd <= 15
            k = round(Int64, f * 10.0^nd)
            lim = Int64(10)^nd
        else
            k = round(BigInt, BigFloat(f) * big(10)^nd)
            lim = big(10)^nd
        end
        if k >= lim                                   # a carry out of the fraction
            k -= lim
            whole += 1
        end
        fracstr = "." * lpad(string(k), nd, '0')
    end
    return (neg ? "-" : "") * _groupdigits(string(whole), sep) * fracstr
end

"""
    thousands(x::Real; digits = 0, sep = ",") -> String

Format a number with thousands separators and a fixed number of decimal places.

`x` is rounded to `digits` decimal places (as `round(x; digits)` rounds) and printed with exactly
`digits` of them, trailing zeros kept. The whole part has `sep` between each group of three digits
and the decimal places have none. A negative amount has a leading `-`; an amount that rounds to zero
prints without one. A rounding carry reaches the whole part (`999.996` at 2 places is `"1,000.00"`),
and an integer or a float of any magnitude prints its own digits, never scientific notation. `NaN`
and `Inf` print as `"NaN"` and `"Inf"`.

This is the formatter `prt` uses for the numbers in its tables. It returns a `String` of the number
only: a currency symbol is written beside the call, in the text around it.

# Keywords
- `digits = 0`: decimal places. `0` gives a whole number (`commafmt(round(Int, x))` in Lecture 1.1,
  the `usd` helpers of Lectures 2.4 and 2.7, `com` of Lecture 2.5); `1` and `2` replace
  `commas(round(x, digits = 1))` (Lectures 4.1 to 6.3) and `usd(x)` (Lectures 3.2 to 3.4, 4.4).
- `sep = ","`: the group separator. `"{,}"` is Lecture 1.1's `mnum`, the thousands comma for math
  mode.

# Examples
The three values the course formats by hand: Lecture 1.1's `commafmt` comment, `300000000 -> "300,000,000"`;
Lecture 3.2's `usd`, whose comment is `1357 -> "1,357"` (here with its two decimals); and the one-decimal negative
of the form `commas(round(x, digits = 1))` that Lectures 4.1 to 6.3 print.

```jldoctest
thousands(300000000)
# output

"300,000,000"
```

```jldoctest
thousands(1357.2; digits = 2)

# output

"1,357.20"
```

```jldoctest
thousands(-64580.949; digits = 1)

# output

"-64,580.9"
```

```jldoctest
thousands(1234567; sep = "{,}")

# output

"1{,}234{,}567"
```
"""
function thousands(x::Real; digits::Integer=0, sep::AbstractString=",")
    digits >= 0 || throw(ArgumentError("digits must be nonnegative, got $digits"))
    return _formatfixed(x, digits; sep=sep)
end

"""
    snapvals(x; atol=1e-8) -> Array

Snap near-integer and near-zero floating-point values in an array.

Designed for post-processing mathematical programming solutions where solvers
introduce small numerical artifacts (e.g., 2.9999999997 instead of 3, or
1.2e-12 instead of 0). Each element is rounded to the nearest integer if within
`atol`, and values that round to zero are set to exactly `0.0`.

**Caveat:** Snapping may cause constraint violations in some models. When snapped
values are used in further computation, verify feasibility — particularly for
models with big-M constraints where rounding a near-zero binary variable to 0
can violate the associated constraint by a large amount.

# Arguments
- `x`: Array of numeric values (typically from `value.(x)` after JuMP solve).
- `atol`: Tolerance for snapping (default: `1e-8`).

# Example
```jldoctest
snapvals([2.9999999997, 1e-12, 0.5])

# output

3-element Vector{Float64}:
 3.0
 0.0
 0.5
```
"""
function snapvals(x; atol::Real=1e-8)
    arr = Array(x)
    return map(arr) do v
        r = round(v)
        y = isapprox(v, r; atol=atol) ? r : v
        iszero(y) ? 0.0 : Float64(y)
    end
end
