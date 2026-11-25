# dist_geo_pin_cases.jl -- the distance and geocoding calls the course makes today, as pin cases
# (PCV K5, plan principle 9). Every case is a (name, thunk) pair; the thunk returns one line of
# text, the value encoded to 12 significant digits (see dist_geo_pin_helpers.jl). The calls and arguments
# come from the course's own lectures and homeworks (read only): loc2lonlat's city and
# state lists (3.4, 4.1, 5.2, 5.3, HW 2, HW 3, HW 1's Roanoke Rapids, 4.2's six queries), d1/d2/dgc/
# dgca/dists/lonlat2loc call shapes (2.2 to 2.6, 3.4, HW 1 to HW 5, the projects).
#
# A name beginning with a ruled ID is a case whose value the ruled item moves; the fixture row is
# rewritten in the commit that moves it, and that commit names the ID. The IDs: N1, N5, N7, N8, N19,
# CR26, S3, S14, S15 (D7 and N27 move no pinned value). Any other case must keep its value.
#
# The scalar loc2lonlat result is encoded by LON, LAT, source and status only, and the field names
# are read by either spelling (`source`/`GC_SOURCE`), so S14's rename moves no pin; the uncertainty
# is pinned apart, in the S3_ cases, so that S3 moves exactly those. No case touches the network:
# the address tier is absent or a stub, and a stub that must not be reached throws an IOError.

using Logjam
using DataFrames

const DGPIN_CACHE = joinpath(@__DIR__, "fixtures", "geocode_cache_4net2.csv")

# A case a ruled item moves, other than by its name's prefix, is listed here with the ID of the commit that
# moves it (K14): GC sends a plain name that is not found, with a state, down the ladder to the state tier,
# where it was FAIL. No course call is among them: every plain name the course geocodes is a real place.
const DGPIN_MOVED = Dict{String,String}("loc_scalar_unknown_city" => "GC")

# ---- encoding ------------------------------------------------------------------------------
_e(x::Missing) = "missing"
_e(x::Bool) = string(x)
_e(x::Integer) = string(x)
_e(x::AbstractFloat) = isfinite(x) ? repr(round(Float64(x); sigdigits = 12)) : repr(Float64(x))   # 12 digits: the sums of the state tier differ in the last place under --check-bounds=yes
_e(x::Symbol) = ":" * String(x)
_e(x::AbstractString) = repr(String(x))
_e(x::Nothing) = "nothing"
_e(x::Type) = string(x)
_e(x::Tuple) = "(" * join((_e(v) for v in x), ",") * ")"
_e(x::NamedTuple) = "(" * join((string(k) * "=" * _e(v) for (k, v) in pairs(x)), ",") * ")"
_e(x::AbstractArray) = string(size(x)) * "[" * join((_e(v) for v in x), ",") * "]"
_e(df::DataFrame) = "df" * string(size(df)) * join(("|" * n * "=" * _e(df[!, n]) for n in names(df)), "")

_gf(r, a::Symbol, b::Symbol) = hasproperty(r, a) ? getproperty(r, a) : getproperty(r, b)
_gcsrc(r) = _gf(r, :GC_SOURCE, :source)
_gcst(r) = _gf(r, :GC_STATUS, :status)
_gcunc(r) = _gf(r, :GC_UNCERT, :uncert)

# one scalar result: position, tier and status (the uncertainty is the S3_ cases')
enc_gc(r) = string(_e(r.LON), "|", _e(r.LAT), "|", _e(_gcsrc(r)), "|", _e(_gcst(r)))
# a table result: the same four columns, row by row
enc_gcdf(df) = string(nrow(df), ":", join((string(_e(df.LON[i]), "|", _e(df.LAT[i]), "|",
                                                  _e(df.GC_SOURCE[i]), "|", _e(df.GC_STATUS[i]))
                                           for i in 1:nrow(df)), ";"))
enc_unc(df) = join((_e(u) for u in df.GC_UNCERT), ";")

# run `f` with the address tier absent (hook = nothing) or replaced by `hook`, logging discarded
function _with_nom(f, hook)
    saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
    try
        Logjam._nominatim_available[] = hook !== nothing
        hook === nothing || (Logjam._nominatim_geocode[] = hook)
        return Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
    finally
        Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
    end
end
_no_network = (args...; kwargs...) -> throw(Base.IOError("pin: the address tier was reached", 0))

# a call in a fresh working directory leaves it empty (K0's cache rule, N14)
function _no_file_written()
    mktempdir() do d
        cd(d) do
            loc2lonlat(["Raleigh, NC", "123 Main St, Raleigh, NC"])
            return _e(isempty(readdir(d)))
        end
    end
end

_place(name, st) = (p = usplace(); r = p[(p.NAME .== name) .& (p.ST .== st), :]; [r.LON[1], r.LAT[1]])
_ncp() = (p = usplace(); nc = p[p.ST .== :NC, :];
          nc = nc[sortperm(nc.POP; rev = true)[1:8], :]; (nc, [nc.LON nc.LAT]))

# ---- the cases -----------------------------------------------------------------------------
function dgpin_cases()
    cases = Tuple{String,Function}[]
    add(name, f) = push!(cases, (name, f))
    err(f) = try
        r = f()
        r isa String ? r : _e(r)
    catch e
        "ERR:" * string(nameof(typeof(e)))
    end

    # ================= d1, d2 =================
    add("d1d2_vec_int_2_1", () -> _e((d1([0, 0], [4, 3]), d2([0, 0], [4, 3]))))           # 2.2 Code block 18
    add("d1d2_vec_int_3d", () -> _e((d1([1, 2, 3], [4, 6, 2]), d2([1, 2, 3], [4, 6, 2]))))
    add("d1d2_vec_float", () -> _e((d1([0.5, -1.25], [2.0, 3.5]), d2([0.5, -1.25], [2.0, 3.5]))))
    add("d1d2_tuple", () -> _e((d1((1, 2), (4, 6)), d2((0, 0), (3, 4)))))
    add("d1d2_rowview_vs_vec", () -> (P = [1.0 2.0; 4.0 6.0; -3.0 0.5];     # hw1: d2(X, P[i, :])
                                      _e([d2([0.5, 0.5], P[i, :]) for i in axes(P, 1)])))
    add("d1d2_matrix_view_row", () -> (P = [1.0 2.0; 4.0 6.0];
                                       _e((d1(view(P, 1, :), view(P, 2, :)), d2(view(P, 1, :), view(P, 2, :))))))
    add("d1d2_row_vs_row", () -> _e((d1([0 0], [4 3]), d2([0 0], [4 3]))))             # same shape, both 1x2
    add("d1d2_adjoint_vs_adjoint", () -> _e((d1([0, 0]', [4, 3]'), d2([0, 0]', [4, 3]'))))
    add("d1d2_hw1_p3_sum", () -> (P3 = [0.0 0.0; 4.0 1.0; 2.0 5.0]; w3 = [1.0, 2.0, 3.0];
                                  _e(sum(w3[i] * d1([1.0, 2.0], P3[i, :]) for i in axes(P3, 1)))))
    add("N5_d1_vec_vs_row", () -> err(() -> _e(d1([0, 0], [3 4]))))
    add("N5_d2_vec_vs_row", () -> err(() -> _e(d2([0, 0], [3 4]))))
    add("N5_d1_vec_vs_row_value", () -> _e(d1([0, 0], [3 4])))                           # v0.2.8: 14.0, not 7.0
    add("N5_d2_vec_vs_row_value", () -> _e(d2([0, 0], [3 4])))                           # v0.2.8: 7.07, not 5.0

    # ================= dgc =================
    add("dgc_ral_clt", () -> _e(dgc((-78.6382, 35.7796), (-80.8431, 35.2271))))          # the docstring example
    add("dgc_units", () -> (a = (-78.6382, 35.7796); b = (-80.8431, 35.2271);
                            _e((dgc(a, b; unit = :mi), dgc(a, b; unit = :km), dgc(a, b; unit = :rad)))))
    add("dgc_vector_inputs", () -> _e(dgc([-78.659, 35.8219], [-80.8431, 35.2271])))     # 2.2 Code block 20
    add("dgc_tuple_vs_vector", () -> _e(dgc((-78.6, 35.8), [-80.8, 35.2])))
    add("dgc_miles_per_degree", () -> _e(dgc((0, 0), (0, 1))))                           # 4.2: mpd = dgc((0, 0), (0, 1))
    add("dgc_int_inputs", () -> _e(dgc([0, 0], [0, 1])))
    add("dgc_antipodal", () -> _e(dgc((0.0, 0.0), (180.0, 0.0))))
    add("dgc_same_point", () -> _e(dgc((10.0, 20.0), (10.0, 20.0))))
    add("dgc_rowview_of_matrix", () -> (P = [-78.6382 35.7796; -80.8431 35.2271; -82.5 35.6];   # hw1: dgc(x, p) for p in eachrow(P)
                                        _e([dgc([-79.0, 35.9], p) for p in eachrow(P)])))
    add("dgc_cities_2_2", () -> (D = _place("Detroit", :MI); G = _place("Gainesville", :FL); M = _place("Memphis", :TN);
                                 _e([dgc(D, G), dgc(D, M), dgc(G, M)])))              # 2.2/2.3 Code block: three cities
    add("dgc_c0_block_groups", () -> (c0 = (-78.6390995, 35.7803975);                   # 4.2: dgc(c0, (r.LON, r.LAT)) <= 3
                                      bg = uscenblkgrp(); bg = bg[bg.STFIP .== 37, :][1:200, :];
                                      _e([dgc(c0, (r.LON, r.LAT)) for r in eachrow(bg)])))
    add("dgc_err_length3", () -> err(() -> dgc([1, 2, 3], [1, 2, 3])))
    add("dgc_err_unit", () -> err(() -> dgc([1, 2], [1, 3]; unit = :ft)))

    # ================= dists =================
    add("dists_p_1_2_inf", () -> _e([dists([0 0], [4 3], p)[1] for p in (1, 2, Inf)]))   # 2.2 Code block 19
    add("dists_default_p2", () -> _e(dists([0.0 0.0; 10.0 0.0], [5.0 0.0; 5.0 5.0])))
    add("dists_p3_real", () -> _e(dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], 3.0)))
    add("dists_p_inf", () -> _e(dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], Inf)))
    add("dists_p_half_err", () -> err(() -> dists([0.0 0.0], [1.0 1.0], 0.5)))
    add("dists_int_matrix_p1", () -> (P = [1 2; 3 5; 8 1]; _e(dists(P, P, 1))))          # 2.4: w * dists(P, P, 1)
    add("dists_column_matrices", () -> (P = reshape([1.0, 3.0, 8.0], :, 1);              # 2.3: dists(reshape(X, :, 1), P, 1)
                                        _e(dists(reshape([2.0, 5.0], :, 1), P, 1))))
    add("dists_adjoint_point", () -> (XY = [-80.0 35.0; -82.0 36.0];                     # 3.4: dists(xy', XY2, :mi)[:]
                                      _e(dists([-79.0, 35.5]', XY, :mi)[:])))
    add("dists_mi_km_rad", () -> (P = _ncp()[2]; _e((dists(P, P, :mi), dists(P, P, :km), dists(P, P, :rad)))))
    add("dists_rad_row_vs_matrix", () -> (P = _ncp()[2]; Raleigh = [-78.659 35.8219];    # 2.2 Code block 20
                                          _e((vec(dists(Raleigh, P, :rad)), vec(dists(Raleigh, P, :mi))))))
    add("dists_row_slice_hw5", () -> (P = _ncp()[2]; _e(maximum(dists(P[1:1, :], P, :mi)))))
    add("dists_p_1_2_inf_nc", () -> (P = _ncp()[2]; _e((dists(P, P, 1), dists(P, P, 2), dists(P, P, Inf)))))
    add("dists_err_symbol", () -> err(() -> dists([0.0 0.0], [1.0 1.0], :ft)))
    add("S15_dists_vec_vs_matrix_p2", () -> err(() -> _e(dists([0.0, 0.0], [3.0 4.0; 6.0 8.0], 2))))
    add("S15_dists_vec_vs_matrix_mi", () -> (P = _ncp()[2]; err(() -> _e(dists([-79.0, 35.5], P, :mi)))))
    add("S15_dists_unit_keyword", () -> (P = _ncp()[2]; err(() -> _e(dists(P, P; unit = :mi)))))
    add("N19_dists_integer_p3", () -> err(() -> _e(dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], 3))))
    add("N19_dists_integer_p5", () -> err(() -> _e(dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], 5))))

    # ================= dgca =================
    add("dgca_docstring", () -> (X = [-78.64 35.78; -80.84 35.23]; Xa = [-79.79 36.07; -77.94 34.23];
                                 _e(dgca(X, Xa, [0.0, 500.0]))))
    add("dgca_nc_places", () -> (nc = _ncp()[1]; P = _ncp()[2]; _e(dgca(P, P, nc.ALAND))))             # 2.5: dgca(P, P, z.ALAND)
    add("dgca_one_by_one", () -> (nc = _ncp()[1]; P = _ncp()[2]; _e(dgca(P[1:1, :], P[2:2, :], [nc.ALAND[2]])[1])))   # 2.6
    add("dgca_unit_km", () -> (nc = _ncp()[1]; P = _ncp()[2]; _e(dgca(P, P, nc.ALAND; unit = :km))))
    add("dgca_floor_binds", () -> (X = [-78.64 35.78]; Xa = [-78.65 35.79]; _e(dgca(X, Xa, [4000.0]))))
    add("dgca_zero_area", () -> (X = [-78.64 35.78]; Xa = [-79.79 36.07]; _e(dgca(X, Xa, [0.0]))))
    add("dgca_err_negative", () -> err(() -> dgca([-78.64 35.78], [-79.79 36.07], [-1.0])))
    add("dgca_err_length", () -> err(() -> dgca([-78.64 35.78], [-79.79 36.07], [1.0, 2.0])))

    # ================= lonlat2loc (it calls dists) =================
    add("lonlat2loc_vec_desc", () -> _e(lonlat2loc([-78.6382, 35.7796], usplace()).desc))     # 2.2: lonlat2loc(xᵒ, usplace()).desc
    add("lonlat2loc_row_matrix", () -> (X = [-78.6 35.8; -80.8 35.2; -82.5 35.6];
                                        r = lonlat2loc(X, usplace());
                                        _e((r.NAME, r.ST, r.dist, r.dir, r.desc))))          # 2.3: lonlat2loc(Xᵒ, df)
    add("lonlat2loc_big_cities", () -> (c = usplace(); big = c[c.POP .> 100000, :];
                                        _e(lonlat2loc([-90.0 35.1], big).desc)))              # 3.4: lonlat2loc(DC, big).desc

    # ================= loc2lonlat: scalar, a city and its state (course lists) =================
    for (c, st) in [("Rochester", :NY), ("Orlando", :FL), ("San Antonio", :TX), ("Portland", :OR),   # 3.4 Code block 18
                    ("Tucson", :AZ), ("Denver", :CO), ("Milwaukee", :WI), ("Memphis", :TN),
                    ("Raleigh", :NC), ("Dallas", :TX), ("Greensboro", :NC), ("High Point", :NC),      # 4.1
                    ("Goldsboro", :NC), ("Chicago", :IL), ("Austin", :TX), ("Durham", :NC),            # HW 3
                    ("Knoxville", :TN), ("Athens", :GA), ("Asheville", :NC), ("Jacksonville", :FL),    # Proj 3, 5.2, 5.3
                    ("Savannah", :GA), ("Gainesville", :FL),
                    ("Pueblo", :CO), ("Colonia", :NJ), ("Lubbock", :TX), ("Niles", :OH),               # HW 2 plants
                    ("Livermore", :CA), ("Vancouver", :WA), ("Palestine", :TX), ("Diamond Bar", :CA),
                    ("Doctor Phillips", :FL), ("Stillwater", :OK), ("Gainesville", :GA), ("Elkhorn", :WI)]
        add("loc_scalar_$(c)_$(st)", () -> _with_nom(() -> enc_gc(loc2lonlat(c; state = st)), nothing))
    end
    add("loc_scalar_state_as_string", () -> _with_nom(() -> enc_gc(loc2lonlat("Durham"; state = "NC")), nothing))
    add("loc_scalar_symbol_of_string", () -> _with_nom(() -> enc_gc(loc2lonlat("Austin"; state = Symbol("TX"))), nothing))
    add("loc_scalar_city_no_state", () -> _with_nom(() -> enc_gc(loc2lonlat("Raleigh")), nothing))
    add("loc_scalar_comma_state", () -> _with_nom(() -> enc_gc(loc2lonlat("Raleigh, NC")), nothing))
    add("loc_scalar_roanoke_rapids", () -> _with_nom(() -> enc_gc(loc2lonlat("Roanoke Rapids, NC")), nothing))   # HW 1 Q6
    add("loc_scalar_misspelled_city", () -> _with_nom(() -> enc_gc(loc2lonlat("Raliegh, NC")), nothing))        # 4.2: state tier
    add("loc_scalar_zip", () -> _with_nom(() -> enc_gc(loc2lonlat("27695")), nothing))                          # 4.2
    add("loc_scalar_zip_27601", () -> _with_nom(() -> enc_gc(loc2lonlat("27601")), nothing))
    add("loc_scalar_zip_unknown", () -> _with_nom(() -> enc_gc(loc2lonlat("00000")), nothing))
    add("loc_scalar_empty", () -> _with_nom(() -> enc_gc(loc2lonlat("")), nothing))
    add("loc_scalar_unknown_city", () -> _with_nom(() -> enc_gc(loc2lonlat("Zzyzx"; state = :CA)), nothing))
    add("loc_scalar_bad_state_throws", () -> _with_nom(() -> err(() -> loc2lonlat("Raleigh"; state = "XX")), nothing))
    add("loc_scalar_address_no_nominatim", () -> _with_nom(() -> enc_gc(loc2lonlat("1 E Edenton St, Raleigh, NC 27601")), nothing))
    add("loc_scalar_address_raleigh_street", () -> _with_nom(() -> enc_gc(loc2lonlat("123 Main St, Raleigh, NC")), nothing))
    add("loc_scalar_address_pobox", () -> _with_nom(() -> enc_gc(loc2lonlat("PO Box 5, Raleigh, NC 27601")), nothing))
    add("loc_scalar_address_with_unit", () -> _with_nom(() -> enc_gc(loc2lonlat("100 Main St Apt 4, Durham, NC 27701")), nothing))
    add("loc_scalar_address_cache_hit", () -> _with_nom(() -> enc_gc(loc2lonlat("1 E Edenton St, Raleigh, NC 27601"; cache = DGPIN_CACHE)), _no_network))

    # ================= loc2lonlat: vector =================
    add("loc_vec_4net2_queries_cached", () -> _with_nom(() -> enc_gcdf(          # 4.2 Code block 1, with the saved cache
        loc2lonlat(["915 Partners Way, Raleigh, NC 27606", "2 Broughton Dr, Raleigh, NC 27695",
                    "Raleigh, NC", "27695", "Raliegh, NC", "Raleigh"]; cache = DGPIN_CACHE)), _no_network))
    add("loc_vec_capitol_cached", () -> _with_nom(() -> enc_gcdf(                 # 4.2 Code block 30
        loc2lonlat(["1 E Edenton St, Raleigh, NC 27601"]; cache = DGPIN_CACHE)), _no_network))
    add("loc_vec_cities_state", () -> _with_nom(() -> enc_gcdf(loc2lonlat(["Raleigh", "Durham", "Chapel Hill"]; state = :NC)), nothing))
    add("loc_vec_zips", () -> _with_nom(() -> enc_gcdf(loc2lonlat(["27601", "27708", "27514"])), nothing))
    add("loc_vec_mixed", () -> _with_nom(() -> enc_gcdf(loc2lonlat(["Raleigh, NC", "27695", "Zzyzx", ""])), nothing))
    add("loc_vec_columns", () -> _with_nom(() -> _e(names(loc2lonlat(["Raleigh, NC", "27695"]))), nothing))
    add("loc_vec_types", () -> _with_nom(() -> (d = loc2lonlat(["Raleigh, NC", "27695"]); _e((eltype(d.LON), eltype(d.GC_UNCERT)))), nothing))
    add("loc_vec_with_failure_types", () -> _with_nom(() -> (d = loc2lonlat(["Raleigh, NC", "Zzyzx"]); _e((eltype(d.LON), eltype(d.GC_UNCERT)))), nothing))
    add("loc_vec_no_cache_file_written", () -> _with_nom(_no_file_written, nothing))

    # ================= loc2lonlat: DataFrame =================
    add("loc_df_city_state", () -> _with_nom(() -> enc_gcdf(loc2lonlat(DataFrame(CITY = ["Raleigh", "Durham"], STATE = [:NC, :NC]))), nothing))
    add("loc_df_street_city_state", () -> _with_nom(() -> enc_gcdf(
        loc2lonlat(DataFrame(addr = ["123 Main St"], town = ["Raleigh"], st = ["NC"]); street = :addr, city = :town, state = :st)), nothing))
    add("loc_df_zip_string", () -> _with_nom(() -> enc_gcdf(loc2lonlat(DataFrame(POSTALCODE = ["27601", "27695"]))), nothing))
    add("loc_df_county", () -> _with_nom(() -> enc_gcdf(loc2lonlat(DataFrame(COUNTY = ["Wake"], STATE = [:NC]))), nothing))
    add("loc_df_state_only", () -> _with_nom(() -> enc_gcdf(loc2lonlat(DataFrame(STATE = [:NC, :VA]))), nothing))
    add("loc_df_keeps_columns", () -> _with_nom(() -> (r = loc2lonlat(DataFrame(CITY = ["Raleigh"], STATE = [:NC], X = [7]));
                                                       _e(names(r))), nothing))
    add("loc_df_missing_cells", () -> _with_nom(() -> enc_gcdf(
        loc2lonlat(DataFrame(CITY = ["Raleigh", missing], STATE = [:NC, :NC]))), nothing))
    add("loc_df_cache_hit", () -> _with_nom(() -> enc_gcdf(
        loc2lonlat(DataFrame(STREET = ["1 E Edenton St"], CITY = ["Raleigh"], STATE = ["NC"], POSTALCODE = ["27601"]);
                   cache = DGPIN_CACHE)), _no_network))

    # ================= S36: the census tables keep integer ZIP codes =================
    add("S36_zcta_eltypes", () -> _e((eltype(uszcta5().ZCTA5) <: Integer, eltype(uszcta3().ZCTA3) <: Integer)))
    add("S36_zcta5_integer_filter", () -> _e(nrow(uszcta5()[uszcta5().ZCTA5 .== 27601, :])))
    add("S36_zcta5_integer_division", () -> _e(sum(uszcta5().ZCTA5 .÷ 100)))
    add("S36_zcta5_leftjoin", () -> (c = DataFrame(ZCTA5 = [27601, 27695, 90210]);          # HW 2 Q3: leftjoin on uszcta5
                                     j = leftjoin(c, uszcta5()[!, [:ZCTA5, :LON, :LAT, :ALAND]]; on = :ZCTA5);
                                     _e((j.LON, j.LAT, j.ALAND))))

    # ================= ruled cases: the value moves under the named ID =================
    # N1: v0.2.8 reads a state out of the last two letters of the last word
    for (city, name) in [("Sacramento", "California"), ("Atlanta", "Georgia"), ("Pittsburgh", "Pennsylvania"),
                         ("Richmond", "Virginia"), ("Charleston", "West Virginia"), ("Houston", "Texas"),
                         ("Wichita", "Kansas"), ("Little Rock", "Arkansas"), ("Birmingham", "Alabama"),
                         ("Tulsa", "Oklahoma"), ("Baltimore", "Maryland"), ("Providence", "Rhode Island"),
                         ("Milwaukee", "Wisconsin"), ("Albuquerque", "New Mexico"), ("Columbia", "Missouri"),
                         ("Portland", "Maine")]
        add("N1_spelled_$(replace(city, " " => "_"))_$(replace(name, " " => "_"))",
            () -> _with_nom(() -> enc_gc(loc2lonlat("$city, $name")), nothing))
    end
    add("N1_explicit_state_overridden", () -> _with_nom(() -> enc_gc(loc2lonlat("123 Main St, Richmond"; state = :VA)), nothing))
    add("N1_five_digit_street_number", () -> _with_nom(() -> enc_gc(loc2lonlat("10420 Falls of Neuse Rd, Raleigh, NC 27614")), nothing))
    add("N1_city_ending_in_state_code", () -> _with_nom(() -> enc_gc(loc2lonlat("Raleigh, Miami")), nothing))
    add("N1_parse_string_five_digit", () -> _e(Logjam._parse_address_string("10420 Falls of Neuse Rd, Raleigh, NC 27614")))
    add("N1_parse_string_georgia", () -> _e(Logjam._parse_address_string("Atlanta, Georgia")))
    # N7, N8: a leading-zero ZIP never geocodes; a numeric ZIP column throws
    add("N7_zip_leading_zero_string", () -> _with_nom(() -> enc_gc(loc2lonlat("02139")), nothing))
    add("N7_zip_leading_zero_vector", () -> _with_nom(() -> enc_gcdf(loc2lonlat(["02139", "27601"])), nothing))
    add("N7_zip_leading_zero_in_address", () -> _with_nom(() -> enc_gc(loc2lonlat("1 Main St, Cambridge, MA 02139")), nothing))
    add("N8_numeric_zip_column", () -> _with_nom(() -> err(() -> enc_gcdf(loc2lonlat(DataFrame(POSTALCODE = [27601, 27695])))), nothing))
    add("N8_numeric_zip_leading_zero", () -> _with_nom(() -> err(() -> enc_gcdf(loc2lonlat(DataFrame(POSTALCODE = [2139])))), nothing))
    # S3: the uncertainty column, 0.45 sqrt(a) at every area tier
    add("S3_uncert_place", () -> _with_nom(() -> enc_unc(loc2lonlat(["Raleigh, NC", "Durham, NC"])), nothing))
    add("S3_uncert_zip", () -> _with_nom(() -> enc_unc(loc2lonlat(["27601", "27695"])), nothing))
    add("S3_uncert_county", () -> _with_nom(() -> enc_unc(loc2lonlat(DataFrame(COUNTY = ["Wake"], STATE = [:NC]))), nothing))
    add("S3_uncert_state", () -> _with_nom(() -> enc_unc(loc2lonlat(DataFrame(STATE = [:NC]))), nothing))
    add("S3_uncert_scalar_place", () -> _with_nom(() -> _e(_gcunc(loc2lonlat("Raleigh"; state = :NC))), nothing))
    add("S3_uncert_address_fallback", () -> _with_nom(() -> _e(_gcunc(loc2lonlat("1 E Edenton St, Raleigh, NC 27601"))), nothing))
    # S14: `state` as a vector matching the addresses
    add("S14_state_vector", () -> _with_nom(() -> err(() -> enc_gcdf(loc2lonlat(["Raleigh", "Athens"]; state = [:NC, :GA]))), nothing))
    # CR 26: the address tier's fallback, its failures, and a street-only match
    add("CR26_fallback_status", () -> _with_nom(() -> enc_gc(loc2lonlat("NC State Bell Tower, Raleigh, NC")),
                                                (args...; kwargs...) -> missing))
    add("CR26_failed_lookup_calls", () -> (n = Ref(0);
        _with_nom(() -> loc2lonlat(["NC State Bell Tower, Raleigh, NC", "NC State Bell Tower, Raleigh, NC"]),
                  (args...; kwargs...) -> (n[] += 1; missing)); _e(n[])))
    add("CR26_street_only_match", () -> _with_nom(() -> enc_gc(loc2lonlat("9999 Hillsborough St, Raleigh, NC 27607")),
        (args...; kwargs...) -> (lon = -78.6997617, lat = 35.7957255,
                                 display_name = "Hillsborough Street, Raleigh, Wake County, North Carolina, 27607",
                                 importance = 0.4)))
    add("CR26_exact_match_stays_ok", () -> _with_nom(() -> enc_gc(loc2lonlat("915 Partners Way, Raleigh, NC 27606")),
        (args...; kwargs...) -> (lon = -78.6758457, lat = 35.7706306,
                                 display_name = "915, Partners Way, Raleigh, Wake County, North Carolina, 27606",
                                 importance = 0.4)))
    add("CR26_bad_state_in_batch", () -> _with_nom(() -> err(() -> enc_gcdf(
        loc2lonlat(DataFrame(CITY = ["Raleigh", "Durham"], STATE = ["NC", "XX"])))), nothing))
    add("CR26_bad_state_in_vector_kw", () -> _with_nom(() -> err(() -> enc_gcdf(loc2lonlat(["Raleigh", "Durham"]; state = "XX"))), nothing))
    return cases
end
