# prt_pin_cases.jl -- the seeded corpus of `prt` inputs whose output is pinned (PCV K4, principle 9).
#
# Every case is (name, argument, keywords). The shapes are the ones the ISE754 lectures, companions and
# keys pass today: Float64 and Int matrices (integer-valued, mixed, all |v| < 1, negative, NaN, Inf, 1e6
# and up), vectors, DataFrames (all-numeric, String plus numeric, all-String, string.(df)), and the
# rows / cols / row_title / title / fracdig / allfrac / str keywords.
#
# A name beginning with a ruled ID (CR2_, CR32_, N11_, N12_, S13_) is a case whose output the ruled item
# changes; every other case must stay byte-identical for the whole of v0.3.0. The fixture is
# test/fixtures/prt_pins.tsv, written by tools/v0_3_0/make_prt_pins.jl and read by test_prt_pins.jl.
#
# The corpus is seeded: a fixed linear congruential generator (not Random), so the values do not depend on
# the Julia version.

using DataFrames

function _pin_lcg(seed::Integer, n::Integer)
    x = UInt64(seed)
    out = Vector{Float64}(undef, n)
    for i in 1:n
        x = x * 6364136223846793005 + 1442695040888963407
        out[i] = Float64(x >> 11) / 2.0^53
    end
    return out
end

_pin_mat(seed, m, n, f) = reshape(f.(_pin_lcg(seed, m * n)), m, n)

function prt_pin_cases()
    C = Tuple{String,Any,NamedTuple}[]
    add(name, arg, kw = (;)) = push!(C, (name, arg, kw))

    # ---- Float64 matrices
    add("mat_intvalued", [1.0 2.0; 3.0 4000.0])
    add("mat_intvalued_neg_big", [1234567.0 89.0; 1000.0 -2500.0; 0.0 12.0])
    add("mat_mixed_commas", [1.5 2000.75; 3.0 4500.25])
    add("mat_all_lt1", [0.1234 0.5678; 0.9012 0.3456])
    add("mat_open_neg_unit", [-0.5 0.25; 0.75 -0.125])
    add("mat_neg_mixed", [-1.5 2.25; -1234.567 0.0; 3.0 -0.5])
    add("mat_nan", [1.0 NaN; 3.0 4.5])
    add("mat_nan_row", [1.0 2.5; 3.0 4.0; NaN NaN])
    add("mat_nan_col", [NaN 1.0; NaN 2.0])
    add("mat_inf", [1.0 Inf; -Inf 2.5; 3.0 4.0])
    add("mat_inf_only_col", [Inf 1.0; -Inf 2.0])
    add("mat_ge_1e6", [1e6 2.5; 3.5e6 1e9 + 0.5; 2e6 0.25])
    add("mat_1e15", [1e15 1.0; 2.0 2.0])
    add("mat_carry_996", [1.996 0.99996; 2.5 0.5], (;))
    add("mat_carry_996_fracdig3", [1.9996 0.5; 2.5 0.25], (; fracdig = 3))
    add("mat_neg_zero", [-0.001 0.5; 2.5 -0.4], (;))
    add("mat_neg_tiny_allfrac", [-0.00001 0.00002; 0.5 0.25], (;))
    add("mat_big_frac_digits", [123456.789 0.5; 2.25 0.125])
    add("mat_ties", [0.125 2.5; 0.375 3.5], (;))
    add("mat_zero_col", [0.0 0.0; 0.0 0.5])
    add("mat_single_cell", reshape([2.5], 1, 1))
    add("mat_single_cell_int", reshape([7.0], 1, 1))
    add("mat_one_row", [1.0 2.5 3000.0])

    # ---- Int and other eltypes
    add("int_mat", [1 2; 3 4])
    add("int_mat_big_neg", [1000000 -5; 7 12345; -1234567 0])
    add("f32_mat", Float32[1.5 2.25; 3.0 1000.125])

    # ---- seeded random matrices
    add("rand_mixed_6x4", _pin_mat(11, 6, 4, x -> round(1000 * x; digits = 3)))
    add("rand_lt1_5x3", _pin_mat(12, 5, 3, x -> round(x; digits = 5)))
    add("rand_intvalued_5x3", _pin_mat(13, 5, 3, x -> round(10000 * x)))
    add("rand_signed_4x4", _pin_mat(14, 4, 4, x -> round(200 * x - 100; digits = 4)))
    add("rand_wide_ranges_4x5", _pin_mat(15, 4, 5, x -> 10.0^(round(6 * x) - 2) * (1 + x)))
    add("rand_unrounded_5x2", _pin_mat(16, 5, 2, x -> 5000 * x))

    # ---- keywords as the course passes them
    add("kw_rows_cols_strings", [1.0 2.0; 3.0 4.0], (; rows = ["W1", "W2"], cols = ["C1", "C2"]))
    add("kw_row_title", [1 2; 3 4], (; rows = ["a", "b"], cols = ["X", "Y"], row_title = "ID"))
    add("kw_title", [1 2; 3 4], (; title = "Test Title"))
    add("kw_rows_range", [10.5 20.25; 30.0 40.0; 50.0 60.0], (; rows = 30:32, row_title = "qmax"))
    add("kw_rows_intvec_cols_string", [1.5 2.5 3.5; 4.5 5.5 6.5], (; rows = [1, 2], cols = string.(1:3)))
    add("kw_rows_collect_range_cols_vecP", [1.0 2.0; 3.0 4.0], (; rows = ["NF $i" for i in 1:2], cols = vec([10 20])))
    add("kw_fracdig4", [0.5 1.5; 0.25 2.25; NaN 3.125], (; fracdig = 4))
    add("kw_fracdig3_mixed", [1.5 2000.75; 3.0 4500.25], (; fracdig = 3))
    add("kw_fracdig0", [1.5 2.5; 3.25 0.75], (; fracdig = 0))
    add("kw_allfrac2", [0.1234 0.5678; 0.9012 0.3456], (; allfrac = 2))
    add("kw_allfrac6", [0.123456 0.5678; 0.9012 0.3456], (; allfrac = 6))
    add("kw_allfrac1", [0.15 0.25; 0.35 0.45], (; allfrac = 1))
    add("kw_title_rows_all", [1.5 2.5; 3.5 4.5], (; rows = ["a", "b"], cols = ["X", "Y"], title = "T", row_title = "r"))
    add("kw_c_nan_row", [[1.0, 2.0]' NaN; [1.0 2.0; 3.0 4.0] [5.0, 6.0]], (; rows = ["Cost"; string.(1:2)], cols = ["x", "y", "s"]))

    # ---- empty
    add("empty_matrix", Matrix{Float64}(undef, 0, 0))
    add("empty_matrix_0x3", Matrix{Float64}(undef, 0, 3))

    # ---- vectors
    add("vec_int", [1, 2, 3])
    add("vec_float_mixed", [1.5, 2000.25, 3.0])
    add("vec_float_lt1", [0.5, 0.25, 0.125])
    add("vec_rows_row_title", [10, 20, 30], (; rows = ["A", "B", "C"], row_title = "Item"))
    add("vec_title_nan", [1.5, NaN, 3.0], (; title = "v"))
    add("vec_range", 1:5)
    add("vec_empty", Float64[])

    # ---- DataFrames: all numeric (row numbers are printed)
    add("df_num", DataFrame(A = [1, 2], B = [3.14, 2.72]))
    add("df_num_commas", DataFrame(a = [1000, 2000000], b = [0.5, 0.25], c = [1234.5, 2.25]))
    add("df_num_nan", DataFrame(a = [1.0, NaN, 3.5], b = [1, 2, 3]))
    add("df_num_neg", DataFrame(a = [-1.5, 2.0], b = [-0.25, 0.5]))
    add("df_num_all_lt1", DataFrame(a = [0.5, 0.25], b = [0.125, 0.0625]))
    add("df_num_title", DataFrame(a = [1, 2], b = [3.5, 4.0]), (; title = "numeric frame"))
    add("df_num_zero_rows", DataFrame(a = Float64[], b = Float64[]))
    add("df_num_ints_big", DataFrame(a = [1234567, -7654321], b = [1, 2]))
    add("df_num_inf", DataFrame(a = [1.0, Inf], b = [-Inf, 2.5]))

    # ---- DataFrames: String plus numeric (no row numbers; fixed 2 and 4 digits)
    add("df_mixed_city_pop", DataFrame(City = ["Raleigh", "Charlotte"], Pop = [467665, 874579]))
    add("df_mixed_float", DataFrame(site = ["a", "b", "c"], TC = [1234.5, 20.25, 3.0], share = [0.25, 0.5, 0.125]))
    add("df_mixed_nan", DataFrame(site = ["a", "b"], v = [1.5, NaN], k = [1, 2]))
    add("df_mixed_neg_big", DataFrame(op = ["x", "y"], total = [-1234567.5, 2.5]))
    add("df_mixed_title", DataFrame(op = ["heat", "press"], n = [3, 4]), (; title = "ops"))
    add("df_mixed_inf", DataFrame(s = ["p", "q"], v = [Inf, 1.5]))
    add("df_mixed_small_frac", DataFrame(s = ["p", "q"], v = [0.001, 0.5]))
    add("df_mixed_two_text", DataFrame(a = ["p", "q"], b = ["r", "s"], v = [1.5, 22.25]))
    add("df_mixed_zero_rows", DataFrame(s = String[], v = Float64[]))

    # ---- DataFrames: all String, and the string.(df) idiom (4.2)
    add("df_string", DataFrame(a = ["x", "y"], b = ["long text", "z"]))
    add("df_string_title", DataFrame(a = ["x", "y"]), (; title = "strings"))
    add("df_stringdot_numeric", string.(DataFrame(A = [1.0, 2.5], B = [1, 2], C = [NaN, 1234.5])))
    add("df_stringdot_mixed", string.(DataFrame(name = ["a", "b"], x = [1.5, 2.0])))
    add("df_no_columns", DataFrame())

    # ---- changed by ruled items (output today is an error or the wrong value)
    add("CR2_mat_1e300", [1e300 1.0])
    add("CR2_mat_1e300_frac", [1e300 2.5])
    add("CR2_mat_1e300_fraccol", [1.5e300 2.5; 3.0 4.0])
    add("CR2_mat_1e19_int_col", [1e19 3.0; 2.0 4.0])
    add("CR2_int_mat_over_2p53", [9007199254740993 1; 2 3])    # prints ...992 today: the Int goes through Float64
    add("CR2_vec_1e300", [1e300, 1.0])
    add("CR2_df_mixed_1e300", DataFrame(s = ["a", "b"], v = [1e300, 1.5]))
    add("CR2_df_num_1e300", DataFrame(a = [1e300, 2.0], b = [1.5, 2.5]))
    add("CR32_df_num_missing", DataFrame(A = [1.0, missing, 3.5], B = [1, 2, 3]))
    add("CR32_df_mixed_missing", DataFrame(s = ["a", "b"], v = [1.5, missing]))
    add("CR32_df_missing_int", DataFrame(a = [1, missing, 3]))
    add("CR32_mat_missing", Union{Missing,Float64}[1.0 missing; 3.0 4.5])
    add("CR32_vec_missing", Union{Missing,Float64}[1.0, missing, 3.5])
    add("N11_mat_fracdig5", [1.000001 2.5; 3.0 4.0], (; fracdig = 5))
    add("N11_mat_fracdig6", [1.000001 2.5], (; fracdig = 6))
    add("N11_mat_fracdig5_12", [12.00001 2.5], (; fracdig = 5))
    add("N11_mat_allfrac5", [0.00001 0.5; 0.25 0.125], (; allfrac = 5))
    add("N11_mat_allfrac7", [0.0000123 0.5], (; allfrac = 7))
    add("N12_df_symbol", DataFrame(ST = [:NC, :VA], POP = [1, 2]))
    add("N12_df_union_missing_string", DataFrame(a = Union{Missing,String}["x", "y"], v = [1.5, 2.0]))
    add("N12_df_union_missing_string_missing", DataFrame(a = Union{Missing,String}["x", missing], v = [1.5, 2.0]))
    add("N12_df_symbol_only", DataFrame(ST = [:NC, :VA]))
    add("N12_mat_any_text", Any["a" 1.5; "b" 2.5])
    add("N12_vec_text", ["a", "b"])
    add("S13_df_bool_mixed", DataFrame(x = [1.5, 2.25], isLTL = [true, false]))
    add("S13_df_bool_only_mixed", DataFrame(s = ["a", "b"], f = [true, false]))
    add("S13_df_bool_num_all", DataFrame(x = [1.5, 2.25], isLTL = [true, false], n = [3, 4]))
    add("S13_mat_bool", [true false; false true])
    add("S13_vec_bool", [true, false, true])

    _prt_course_cases!(add)
    return C
end

# ---- the course's own calls with an all-fractional column (PCV K14, principle 9) ---------------------------
#
# Every `prt` call of the published lectures and of the released homework keys whose table has a column in
# which every value is below 1 in magnitude (the columns Matlog's fractional-column rule can change), with
# its inputs re-implemented here: from the lecture's own definitions where the input is a formula, and typed
# from what the lecture's page prints where it is a simulation, an optimum or a download (the value is then
# a stand-in to the digits the page shows). No companion script is run. The name says the source, "course_",
# the lecture or homework, the Code block, and what the call prints. A case the PR ruling moves is listed in
# PRT_PIN_MOVED with the ID of the commit that moves it; every other case must keep its output.
#
# The 27 cases PR moved (Matlog's fractional-column rule drops the digits that are zero in every value of a
# column of fractions): twelve course sites (2.5 Code blocks 13 and 14, 2.7 Code block 18, 3.3 Code block 13,
# 3.4 Code blocks 12 to 14 and 21 to 23, HW 3's key, HW 5's key; no information is lost, each value prints as
# itself) and fifteen cases of K4's own corpus, which no course call matches.
const PRT_PIN_MOVED = Dict{String,String}(
    "course_2_5_cb13_fit" => "PR", "course_2_5_cb14_fractions" => "PR", "course_2_7_cb18_capacity" => "PR",
    "course_3_3_cb13_second_product" => "PR", "course_3_4_cb12_shipments" => "PR",
    "course_3_4_cb13_with_distances" => "PR", "course_3_4_cb14_uncoordinated" => "PR",
    "course_3_4_cb21_direct_shipments" => "PR", "course_3_4_cb22_uncoordinated_dc" => "PR",
    "course_3_4_cb23_cross_dock" => "PR",
    "course_hw3_q3_materials" => "PR", "course_hw5_q3_trips" => "PR",
    "mat_open_neg_unit" => "PR", "mat_carry_996_fracdig3" => "PR", "mat_neg_zero" => "PR",
    "mat_big_frac_digits" => "PR", "mat_ties" => "PR", "mat_zero_col" => "PR", "kw_allfrac6" => "PR",
    "vec_float_lt1" => "PR", "df_num_commas" => "PR", "df_num_neg" => "PR", "df_num_all_lt1" => "PR",
    "df_mixed_float" => "PR", "df_mixed_small_frac" => "PR", "N11_mat_allfrac5" => "PR",
    "N11_mat_allfrac7" => "PR")

function _prt_course_cases!(add)
    # --- 2.3, Code blocks 14 and 16: where the multistart optimum sits (lonlat2loc's table)
    add("course_2_3_cb14_two_centers",
        DataFrame(idx = [8, 6], NAME = ["Charlotte", "Cary"], ST = [:NC, :NC], dist = [0.0, 0.7437],
                  bearing = [3.72, 2.21], dir = ["SW", "SE"], desc = ["in Charlotte, NC", "in Cary, NC"]))
    add("course_2_3_cb16_given_allocation",
        DataFrame(idx = [8, 6], NAME = ["Charlotte", "Cary"], ST = [:NC, :NC], dist = [0.0, 0.0629],
                  bearing = [0.0, 2.27], dir = ["N", "SE"], desc = ["in Charlotte, NC", "in Cary, NC"]))

    # --- 2.5, Code blocks 11, 13 and 14: the aggregate-distance fit (rmse to five digits, a stand-in)
    dd = collect(range(0, 1; length = 56))
    add("course_2_5_cb11_d_and_dagg",
        DataFrame(d = round.(dd[1:4], digits = 4), d_agg = [0.6662, 0.6664, 0.6670, 0.6678]))
    add("course_2_5_cb13_fit",
        DataFrame(linear = 0.0224, quadratic = 0.449, exterior_excess = 0.1328, rmse = 0.00188))
    add("course_2_5_cb14_fractions",
        DataFrame(coefficients = ["least squares", "as fractions"], linear = [0.0224, 1/48],
                  quadratic = [0.449, 9/20], excess = [0.1328, 3/23], rmse = [0.00188, 0.00194]))

    # --- 2.6, Code block 7: three checks (the last result a stand-in to six digits)
    add("course_2_6_cb7_checks",
        DataFrame(Check = ["Landmark: Cary re-priced equals what was spent",
                           "Triangulate: the optimum is the same site", "Units: r_nom is \$/ton-mi"],
                  Result = [0.0, 0.0, 0.226263]))

    # --- 2.7, Code block 18: capacity in the model (utilization is rounded to 3 digits in the call)
    add("course_2_7_cb18_capacity",
        DataFrame(ZIP = [270, 272, 275, 282, 283, 290, 294, 296],
                  tons = [12857.0, 11302.0, 12857.0, 12857.0, 10369.0, 11613.0, 9435.0, 8710.0],
                  util = [0.857, 0.753, 0.857, 0.857, 0.691, 0.774, 0.629, 0.581]))

    # --- 3.3, Code block 13: a second product (the shipment table, with its carrying rate h = 0.3)
    add("course_3_3_cb13_second_product",
        DataFrame(f = [20, 80], s = [4.44, 32.16], a = [1, 1], v = [85000, 5000], h = [0.3, 0.3], d = [532, 532],
                  qmax = [6.11, 25.0], qᵒ = [0.27, 8.51], TLCᵒ = [47801.01, 25523.6], isLTL = [true, false]))

    # --- 3.4, Code blocks 12 to 14: the shipments of Ex. 1 (a = 0.5, h = 0.3 are all-fractional columns)
    fS, sS, vS = [100, 380], [3.0, 30.0], [20000.0, 7500.0]
    pct = [96, 144, 240] ./ 480
    shS = DataFrame(f = fS, s = sS, v = vS)
    shC = DataFrame(f = sum(fS) * pct, s = sum(fS) ./ sum(fS ./ sS), v = sum(fS .* vS) / sum(fS))
    sh = vcat(shS, shC)
    sh.a = fill(0.5, 5)
    sh.h = fill(0.3, 5)
    add("course_3_4_cb12_shipments", select(sh, :f, :s, :v, :a, :h))
    shd = select(sh, :f, :s, :v, :a, :h)
    shd.d = [50, 150, 190, 270, 420]
    add("course_3_4_cb13_with_distances", shd)
    shUC = copy(shd)
    shUC.d = [100, 0, 40, 120, 270]
    shUC.qmax = [4.12, 25.0, 14.35, 14.35, 14.35]
    shUC.qᵒ = [2.58, 0.0, 2.25, 4.78, 9.25]
    shUC.TLCᵒ = [15491.93, 0.0, 6823.49, 14474.81, 28030.34]
    add("course_3_4_cb14_uncoordinated", shUC)

    # --- 3.4, Code blocks 21 to 23: the three ways to ship in Ex. 2 (stand-ins typed from the page; a = 0.5 and
    # the cross-docked a = 0, 0.5 are the columns of fractions)
    shD = DataFrame(f = [100, 15, 60, 175, 26.25, 105, 125, 18.75, 75, 100, 15, 60],
                    s = [32, 3, 12, 32, 3, 12, 32, 3, 12, 32, 3, 12], a = 0.5,
                    v = [50000, 25000, 10000, 50000, 25000, 10000, 50000, 25000, 10000, 50000, 25000, 10000],
                    d = [2641.83, 3043.26, 2057.81, 2346.59, 2136.29, 906.46, 1709.51, 1867.03, 957.05, 626.06,
                         1295.17, 1327.78],
                    qmax = [25.0, 4.12, 16.5, 25.0, 4.12, 16.5, 25.0, 4.12, 16.5, 25.0, 4.12, 16.5],
                    qᵒ = [1.98, 4.12, 14.49, 3.07, 4.12, 12.72, 2.05, 4.12, 11.05, 1.23, 3.64, 11.64],
                    TLCᵒ = [113184.33, 43700.48, 43472.98, 175659.33, 50150.07, 38168.95, 115915.66, 37118.84,
                            33146.61, 65794.53, 27265.89, 34920.43],
                    isLTL = [true, false, false, true, false, false, true, false, false, true, false, false],
                    t = [7.23, 100.44, 88.21, 6.41, 57.40, 44.26, 6.00, 80.36, 53.81, 4.48, 88.52, 70.86])
    add("course_3_4_cb21_direct_shipments", shD)
    fS2 = [500, 75, 300]
    sC = sum(fS2) ./ sum(fS2 ./ [32, 3, 12])
    vC = sum(fS2 .* [50000, 25000, 10000]) / sum(fS2)
    sh2 = DataFrame(f = [500, 75, 300, 175, 306.25, 218.75, 175], s = [32, 3, 12, sC, sC, sC, sC], a = 0.5,
                    v = [50000, 25000, 10000, vC, vC, vC, vC],
                    d = [1036.01, 827.46, 760.31, 2220.23, 1460.96, 1053.32, 671.89],
                    qmax = [25.0, 4.12, 16.5, 18.33, 18.33, 18.33, 18.33],
                    qᵒ = [13.27, 4.12, 16.5, 13.91, 14.93, 10.71, 7.65],
                    TLCᵒ = [199109.82, 53849.59, 60016.41, 142498.11, 152914.27, 109734.76, 78389.7],
                    isLTL = fill(false, 7), t = [9.70, 20.09, 20.09, 29.04, 17.80, 17.89, 15.97])
    add("course_3_4_cb22_uncoordinated_dc", sh2)
    shXD2 = select(sh2, :f, :s, :a, :v, :d, :qmax)
    shXD2.a = [0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5]
    shXD2.qXD = [25.0, 3.75, 15.0, 8.75, 15.31, 10.94, 8.75]
    shXD2.TLC_XD = [52859.63, 42218.93, 38793.05, 158094.01, 152963.49, 109758.3, 79093.93]
    add("course_3_4_cb23_cross_dock", shXD2)

    # --- 5.1, Code block 9: the space-filling curve's positions on a grid, rounded to 3 digits in the call
    Θ = [0.250 0.254 0.265 0.298 0.309 0.438 0.441 0.452 0.485 0.496 0.500;
         0.246 0.257 0.271 0.292 0.305 0.434 0.445 0.458 0.479 0.493 0.504;
         0.235 0.229 0.279 0.283 0.333 0.423 0.417 0.467 0.471 0.521 0.515;
         0.202 0.208 0.158 0.154 0.354 0.390 0.396 0.596 0.592 0.542 0.548;
         0.191 0.180 0.167 0.146 0.132 0.379 0.618 0.604 0.583 0.570 0.559;
         0.188 0.184 0.173 0.140 0.129 0.375 0.621 0.610 0.577 0.566 0.563;
         0.059 0.070 0.083 0.104 0.118 0.871 0.632 0.646 0.667 0.680 0.691;
         0.048 0.042 0.092 0.096 0.896 0.860 0.854 0.654 0.658 0.708 0.702;
         0.015 0.021 0.971 0.967 0.917 0.827 0.833 0.783 0.779 0.729 0.735;
         0.004 0.993 0.979 0.958 0.945 0.816 0.805 0.792 0.771 0.757 0.746;
         0.000 0.996 0.985 0.952 0.941 0.813 0.809 0.798 0.765 0.754 0.750]
    grid = (0:10) ./ 10
    add("course_5_1_cb9_sfc_grid", Θ,
        (; rows = string.(reverse(grid)), cols = string.(grid), row_title = "y", allfrac = 3))
    # --- 5.1, Code block 22: the average angle between two random points (a seeded simulation, stand-ins)
    add("course_5_1_cb22_angles",
        DataFrame(span = [360, 180], min = [0.000312, 0.0000214], max = [179.9996, 179.7513],
                  mean = [89.9512, 59.9783]))

    # --- 5.3: the shipments, a route's schedule and its day (stand-ins typed from the page, the residue
    # of the waiting time a few parts in 1e12 as floating point leaves it)
    add("course_5_3_cb6_first_five",
        DataFrame(b = fill(1, 5), e = 2:6, q = [0.2603, 0.6243, 0.8902, 0.5616, 0.7178],
                  s = [1.17, 5.46, 15.23, 5.71, 13.82]))
    add("course_5_3_cb33_route_schedule",
        DataFrame(Rte = [0, 16, 18, 21, 5, 1, 16, 18, 5, 1, 21, 0],
                  Loc = [1, 1, 1, 1, 1, 1, 17, 19, 6, 2, 22, 1],
                  Cost = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.83, 0.88, 1.0043, 0.90, 0.83, 0.64],
                  Arrive = [0.0, 12.17, 12.17, 12.17, 12.17, 12.17, 13.0, 14.09, 15.32, 16.57, 17.54, 18.39],
                  Wait = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4e-12, 0.0, 3.5e-13, 0.0, 0.0, 0.0],
                  TWmin = [-Inf, -Inf, -Inf, -Inf, -Inf, -Inf, 13.0, 13.0, 7.0, 7.0, 13.0, -Inf],
                  Start = [12.17, 12.17, 12.17, 12.17, 12.17, 12.17, 13.0, 14.09, 15.32, 16.57, 17.54, 18.39],
                  LU = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2090, 0.2246, 0.3589, 0.1301, 0.2146, 0.0],
                  Depart = [12.17, 12.17, 12.17, 12.17, 12.17, 12.17, 13.21, 14.32, 15.68, 16.70, 17.75, 18.39],
                  TWmax = [Inf, Inf, Inf, Inf, Inf, Inf, 23.0, 23.0, 17.0, 17.0, 23.0, Inf],
                  Total = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.04, 1.11, 1.36, 1.03, 1.05, 0.64]))
    add("course_5_3_cb34_route_days",
        DataFrame(Start = [12.17, 6.35, 5.67], Finish = [18.39, 23.18, 23.57], Drive = [5.08, 13.56, 13.45],
                  Unload = [1.14, 3.27, 4.46], Wait = [2.1e-12, 0.0, 6.0e-13], TT = [6.22, 16.83, 17.91]))
    qo = [0.026, 1.60875]
    add("course_5_3_cb41_split_load",
        DataFrame(b = [1, 1], e = [29, 29], q = qo, s = [1.17, 1.17], tU = 5/60 .+ 5qo / 60))
    cases = [7, 5, 10, 16, 6]
    add("course_5_3_cb50_windows",
        DataFrame(b = fill(1, 5), e = 2:6, q = cases, tU = 2cases / 60, temin = [12, 16, 10, 16, 12],
                  temax = [16, 20, 11, 17, 14]))

    # --- 6.2: the base-stock tables. pi0, qbar, TP and TPbo are the lecture's own definitions (Code blocks
    # 9 and 11); the simulated pi0 and qbar are stand-ins to the digits the page shows.
    function poissoncdf(j, μ)
        pℓ = exp(-μ)
        F = pℓ
        for ℓ in 1:j
            pℓ *= μ / ℓ
            F += pℓ
        end
        return F
    end
    ra, te, p, c, h, g = 6, 1/8, 6, 3, 0.3, 4
    μ = ra * te
    pi0(qmax, μ) = qmax == 0 ? 1.0 : 1 - poissoncdf(qmax - 1, μ)
    qbar(qmax, μ) = sum(poissoncdf(j, μ) for j in 0:qmax-1; init = 0.0)
    TP(qmax; h = h, ra = ra, μ = μ) = (p - c) * (1 - pi0(qmax, μ)) * ra - c * h * qbar(qmax, μ)
    maxTP(qmaxs; h = h, ra = ra, μ = μ) = maximum((TP(q; h, ra, μ), q) for q in qmaxs)
    TPbo(qmax; g = g, h = h, ra = ra, μ = μ) = (p - c) * (1 - pi0(qmax, μ) * g * te) * ra - c * h * qbar(qmax, μ)

    pi0sim, qbarsim, nonesim, pi0bo, qbarbo, nonebo = 0.03364, 2.2705, 0.03361, 0.04051, 2.2637, 0.04073
    add("course_6_2_cb5_simulation_q3",
        DataFrame(stockout = ["lost sale", "backorder"], pi0 = [pi0sim, pi0bo], none = [nonesim, nonebo],
                  qbar = [qbarsim, qbarbo],
                  TP = [(p - c) * (1 - pi0sim) * ra - c * h * qbarsim,
                        (p - c) * (1 - pi0bo * g * te) * ra - c * h * qbarbo]))
    j = 0:3
    pj = exp(-μ) .* μ .^ j ./ factorial.(j)
    add("course_6_2_cb10_pj_and_F", [pj poissoncdf.(j, μ)],
        (; rows = j, cols = ["pj", "F"], row_title = "j", fracdig = 5, allfrac = 5))
    qmax = 0:2round(Int, ra)
    add("course_6_2_cb14_profit_by_level",
        hcat(poissoncdf.(qmax, μ), pi0.(qmax, μ), qbar.(qmax, μ), TP.(qmax), TPbo.(qmax)),
        (; rows = qmax, cols = ["F", "pi0", "qbar", "TP", "TPbo"], row_title = "qmax", fracdig = 5, allfrac = 5))
    pi0r, qbarr, pi0rbo, qbarrbo = 0.00975, 4.2519, 0.00981, 4.2503
    rosim = (1 - pi0r) * ra / 5
    add("course_6_2_cb32_simulation_policy",
        DataFrame(stockout = ["lost sale", "backorder"], pi0 = [pi0r, pi0rbo], qbar = [qbarr, qbarrbo],
                  TP = [(p - c) * (1 - pi0r) * ra - c * h * qbarr - 2 * rosim,
                        (p - c) * (1 - pi0rbo * g * te) * ra - c * h * qbarrbo - 2 * ra / 5]))
    TPo, qmaxo = maxTP(0:2round(Int, ra))
    rapool = 9ra
    μpool = rapool * te
    TPpool, qmaxpool = maxTP(0:2round(Int, rapool); ra = rapool, μ = μpool)
    add("course_6_2_cb44_warehouses",
        DataFrame(warehouses = ["nine regional", "one central"], qmax = [qmaxo, qmaxpool],
                  pi0 = [pi0(qmaxo, μ), pi0(qmaxpool, μpool)],
                  qbar = [9qbar(qmaxo, μ), qbar(qmaxpool, μpool)], TP = [9TPo, TPpool]))
    add("course_6_2_cb48_demand_and_orders", [6.011 6.060 0.1677 1.003; 5.953 9.662 0.2727 4.962],
        (; rows = ["demanded", "ordered"], row_title = "units", cols = ["mean", "var", "scv", "scv_between"],
           fracdig = 3))

    # --- 6.3, Code block 14: the best number of machines as the yield falls (maxTPmto's results typed)
    rd, te3 = 10, 1/6
    ys = [1, 0.9, 0.8, 0.7]
    ras = rd ./ ys
    mmins = floor.(Int, ras * te3 .+ 1)
    u3 = ras * te3 / 3
    add("course_6_3_cb14_yield",
        [ras mmins u3 [3, 3, 3, 4] [59.44, 58.39, 56.40, 53.99]],
        (; rows = ys, row_title = "y", cols = ["ra", "m_min", "u, m = 3", "m*", "TP*"]))

    # --- the released homework keys (HW 1 to HW 5; HW 6 is not used)
    # HW 1 Q2: the workstation, analytic against simulated (sim values typed; the rest from the key's formulas)
    A = 15 / 17
    TE = 0.2 / A
    CE2 = 0 + (1 + 0) * A * (1 - A) * (2 / 0.2)
    RA = 10 / 0.85
    CTQ(m) = ((1 + CE2) / 2) * (((RA * TE / m)^(sqrt(2 * (m + 1)) - 1)) / (m * (1 - RA * TE / m))) * TE
    sim = [0.5352, 0.0549, 0.0119]
    add("course_hw1_q2d_sweep",
        DataFrame(m = [3, 4, 5], u = [RA * TE / m for m in 3:5], cq = CTQ.(3:5), sim = sim,
                  pct_cq = [100 * (sim[i] - CTQ(m)) / CTQ(m) for (i, m) in enumerate(3:5)],
                  pct_ct = [100 * (sim[i] - CTQ(m)) / (CTQ(m) + TE) for (i, m) in enumerate(3:5)]))
    ctq = [0.5857, 0.4861, 0.5248, 0.5363]
    add("course_hw1_q2c_run_length",
        DataFrame(jobs = [2_000, 20_000, 200_000, 2_000_000], ctq = ctq, pct = 100 .* (ctq .- CTQ(3)) ./ CTQ(3)))
    # HW 2 Q4(c): the cost of the 2-, 3- and 5-digit demand sets against the 5-digit set (TC values typed)
    TC5 = 30134788.57
    TCq = [30139844.89, 30079669.61, 30025871.76]
    add("course_hw2_q4c_levels",
        DataFrame(level = ["5-digit", "3-digit", "2-digit"], NFs = [8, 8, 8], TC = TCq,
                  pct = 100 .* (TCq .- TC5) ./ TC5))
    # HW 3 Q3: the three materials' shipments (a = 0.5 is an all-fractional column)
    wt, uc, sv, ud, cu = [16, 150, 40], [500, 200, 100], [50, 180, 80], [720, 120, 480], [2, 6, 12]
    xh = (uc .- sv) ./ uc
    add("course_hw3_q3_materials",
        DataFrame(f = ud .* wt / 2000, s = wt ./ cu, a = 0.5, v = 2000uc ./ wt, h = 0.05 .+ 0.06 .+ xh,
                  d = fill(1168.62, 3)))
    # HW 5 Q3: the shuttle's first three trips with their windows (tL and tU are 3/60 hour)
    add("course_hw5_q3_trips",
        DataFrame(b = [2, 28, 35], e = [8, 23, 15], q = 1, tL = 3/60, tU = 3/60,
                  tbmin = [10.48, 11.37, 11.81], temax = [12.75, 13.75, 14.0]))
    return nothing
end
