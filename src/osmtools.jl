# =============================================================================
# OSM Tools — OpenStreetMap integration for Logjam
# Requires LightOSM + NearestNeighbors (loaded via LogjamOSMExt extension)
# =============================================================================

# --- Speed defaults by OSM highway class (mph) ---
# Each OSM highway class has a through-route and a "_link" variant.
# Through-routes are the mainline road; links are the ramps/slip roads
# connecting to them (tighter geometry, lower posted speed).
# Speeds are typical US defaults used when OSM maxspeed tags are missing
# (~70% of US roads lack maxspeed in OSM).
const OSM_SPEED_DEFAULTS = Dict{String,Int}(
    "motorway" => 65, "motorway_link" => 45,
    "trunk" => 55,    "trunk_link" => 35,
    "primary" => 45,  "primary_link" => 30,
    "secondary" => 35, "secondary_link" => 25,
    "tertiary" => 30,  "tertiary_link" => 20,
    "residential" => 25,
    "living_street" => 15,
    "unclassified" => 25,
    "road" => 25,
)

# --- FHWA functional classification mapping ---
# Maps OSM highway tags to FHWA codes for compatibility with FAF5 FCLASS column.
#
# | OSM highway tag    | FHWA Code | FHWA Description            |
# |--------------------|-----------|----------------------------|
# | motorway(_link)    | 1         | Interstate                  |
# | trunk(_link)       | 2         | Other Freeways/Expressways  |
# | primary(_link)     | 3         | Other Principal Arterial    |
# | secondary(_link)   | 4         | Minor Arterial              |
# | tertiary(_link)    | 5         | Major Collector             |
# | unclassified       | 6         | Minor Collector             |
# | residential        | 7         | Local                       |
# | living_street      | 7         | Local                       |
# | road               | 6         | Minor Collector (fallback)  |
const OSM_FCLASS = Dict{String,Int}(
    "motorway" => 1, "motorway_link" => 1,
    "trunk" => 2,    "trunk_link" => 2,
    "primary" => 3,  "primary_link" => 3,
    "secondary" => 4, "secondary_link" => 4,
    "tertiary" => 5,  "tertiary_link" => 5,
    "unclassified" => 6,
    "residential" => 7,
    "living_street" => 7,
    "road" => 6,
)

# Approximate area threshold for large-region warning (degrees² ≈ 200 sq mi at mid-latitudes)
const _OSM_AREA_WARN_DEG2 = 0.075

"""
    osm_roads(bbox; cache_dir=".", force_download=false) → (dfN, dfL)

Download OpenStreetMap drivable roads for a bounding box and return Logjam-compatible
DataFrames. Requires `LightOSM` and `NearestNeighbors` to be loaded
(`using LightOSM, NearestNeighbors`).

# Arguments
- `bbox`: Tuple `(xmin, xmax, ymin, ymax)` where x = longitude, y = latitude,
  as returned by `mapbbox`.

# Keywords
- `cache_dir::String="."`: Directory for CSV cache files.
- `force_download::Bool=false`: If `true`, bypass cache and re-download from Overpass.

# Returns
- `dfN::DataFrame`: Nodes with columns IDX (Int), LON (Float64), LAT (Float64),
  SOURCE (String).
- `dfL::DataFrame`: Links with columns SRC (Int), DST (Int), DIST (Float64, miles),
  SPEED (Int, mph), FCLASS (Int), DIR (Int), NAME (String), SOURCE (String).

# Speed defaults by OSM highway class (mph)
Speeds are typical US defaults used when OSM `maxspeed` tags are missing
(~70% of US roads lack maxspeed in OSM):

| OSM highway tag    | Speed (mph) | FHWA Code | FHWA Description            |
|--------------------|-------------|-----------|----------------------------|
| motorway           | 65          | 1         | Interstate                  |
| motorway_link      | 45          | 1         | Interstate ramp             |
| trunk              | 55          | 2         | Freeway/Expressway          |
| trunk_link         | 35          | 2         | Freeway ramp                |
| primary            | 45          | 3         | Principal Arterial          |
| primary_link       | 30          | 3         | Principal Arterial slip     |
| secondary          | 35          | 4         | Minor Arterial              |
| secondary_link     | 25          | 4         | Minor Arterial connector    |
| tertiary           | 30          | 5         | Major Collector             |
| tertiary_link      | 20          | 5         | Major Collector connector   |
| residential        | 25          | 7         | Local                       |
| living_street      | 15          | 7         | Local (shared space)        |
| unclassified       | 25          | 6         | Minor Collector             |
| road               | 25          | 6         | Minor Collector (fallback)  |

# Notes
- Results are cached as CSV files in `cache_dir`. Subsequent calls with the same
  bounding box skip the Overpass download.
- Large bounding boxes (>~200 sq mi) emit a warning; the Overpass API may be slow
  or fail for very large regions.
- Coordinates are stored as (LON, LAT) per Logjam convention.
"""
function osm_roads(bbox::Tuple{Real,Real,Real,Real};
                   cache_dir::String=".", force_download::Bool=false)
    if !_osm_available[]
        error("OSM functions require LightOSM and NearestNeighbors. " *
              "Run: using LightOSM, NearestNeighbors, Logjam")
    end
    return _osm_download[](bbox; cache_dir=cache_dir, force_download=force_download)
end

"""
    stitchnetworks(dfN_base, dfL_base, dfN_osm, dfL_osm; tolerance_m=500, fclass_max=3) → (dfN, dfL)

Stitch an OSM regional network to an existing combined network (FAF5 or
FAF5 + prior OSM regions) by creating connector edges between nearby nodes.

# Arguments
- `dfN_base::DataFrame`: Nodes of the existing (base) network.
- `dfL_base::DataFrame`: Links of the existing (base) network.
- `dfN_osm::DataFrame`: Nodes of the OSM region to attach.
- `dfL_osm::DataFrame`: Links of the OSM region to attach.

# Keywords
- `tolerance_m::Real=500`: Maximum connection distance in meters.
- `fclass_max::Int=3`: Maximum FCLASS on base-network links for eligible
  connection nodes (default 3 = Principal Arterial and above).

# Returns
- `dfN::DataFrame`: Combined nodes (base + OSM + reindexed).
- `dfL::DataFrame`: Combined links (base + OSM + connector edges).

# Details
The function:
1. Identifies eligible base-network nodes (on links with FCLASS ≤ `fclass_max`).
2. Identifies candidate OSM nodes near the region boundary.
3. Builds a KDTree over eligible base nodes and finds matches within `tolerance_m`.
4. Filters for grade separation (OSM `layer` tags) and respects directionality.
5. Creates connector edges (SOURCE="CONNECTOR") with distance via great-circle
   calculation and speed set to the lower of the two connected roads.
6. Combines all DataFrames and runs `prune_reindex` for sequential node IDs.
7. Validates topology (warns if no cross-boundary path exists).

Requires `LightOSM` and `NearestNeighbors` to be loaded.
"""
function stitchnetworks(dfN_base::DataFrame, dfL_base::DataFrame,
                        dfN_osm::DataFrame, dfL_osm::DataFrame;
                        tolerance_m::Real=500, fclass_max::Int=3)
    if !_osm_available[]
        error("OSM functions require LightOSM and NearestNeighbors. " *
              "Run: using LightOSM, NearestNeighbors, Logjam")
    end
    return _osm_stitch[](dfN_base, dfL_base, dfN_osm, dfL_osm;
                         tolerance_m=tolerance_m, fclass_max=fclass_max)
end

"""
    _osm_cache_path(bbox, cache_dir) → (nodes_path, links_path)

Compute deterministic cache file paths from a bounding box.
Filenames encode rounded bbox coordinates for human readability.
"""
function _osm_cache_path(bbox::Tuple{Real,Real,Real,Real}, cache_dir::String)
    xmin, xmax, ymin, ymax = bbox
    r(x) = round(x; digits=2)
    tag = "osm_w$(r(xmin))_e$(r(xmax))_s$(r(ymin))_n$(r(ymax))"
    nodes_path = joinpath(cache_dir, tag * "_nodes.csv")
    links_path = joinpath(cache_dir, tag * "_links.csv")
    return nodes_path, links_path
end
