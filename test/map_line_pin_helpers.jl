# map_line_pin_helpers.jl -- top-level helpers of test/test_map_line_pins.jl,
# moved here verbatim in PCV WP8 (Logjam v0.3.1): the tests that share them now sit in more than one file, one
# per source file, and each includes this file once, guarded by a name it defines, so that every helper is
# defined once.

# case name => ruled ID that moves it. N4 (CR 19): the road layer of a map spanning more than 20 and at most 30 degrees of
# latitude is drawn at opacity 0.3, not 0.35 (S23: every stroke below 0.35); its width, 0.3, stays. Pinned again in
# test_map_tiers.jl (T5.6).
# N4b (RN26): the regional tier's road layer is labeled "Major Roads", not "Interstate Roads"; the regional frames and the
# spans of 9 and 10 degrees move under that alone (the national tier keeps its label). Pinned again in test_map_tiers.jl.
# N4b (RN24): the Interstate's opacity and width at each step, measured against v0.3.0's picture: 0.32 and 0.7 up to 10
# degrees, 0.32 and 0.85 up to 20, 0.3 and 0.8 up to 30; every road row moves under it.
const MLPIN_MOVED = Dict{String, String}("layers_CUS_map" => "N4, N4b (RN24)", "road_tier_20.5" => "N4, N4b (RN24)",
                                         "road_tier_29.99" => "N4, N4b (RN24)", "road_tier_30.0" => "N4, N4b (RN24)",
                                         "layers_NC_frame" => "N4b (RN26), N4b (RN24)",
                                         "layers_Hawaii_frame" => "N4b (RN26), N4b (RN24)",
                                         "layers_Europe_frame" => "N4b (RN26), N4b (RN24)",
                                         "road_tier_9.0" => "N4b (RN26), N4b (RN24)", "road_tier_10.0" => "N4b (RN26), N4b (RN24)",
                                         "road_tier_10.5" => "N4b (RN24)", "road_tier_20.0" => "N4b (RN24)")

_mlpin_moved(name) = haskey(MLPIN_MOVED, name) && (@info("line pin $name moved under $(MLPIN_MOVED[name])"); true)
