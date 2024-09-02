module Logjam

# Include the MapTools and DataTools modules
include("MapTools.jl")
include("DataTools.jl")

# Bring the modules into the Logjam namespace
using .MapTools
using .DataTools
using Serialization

end # module Logjam
