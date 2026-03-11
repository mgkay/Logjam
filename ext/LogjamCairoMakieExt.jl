module LogjamCairoMakieExt

using Logjam
using CairoMakie

function __init__()
    Logjam._cairomakie_available[] = true
    Logjam._cairomakie_activate[] = CairoMakie.activate!
    Logjam._dcf_impl[] = _dcf_impl
end

# H7: dcf - display current figure
function _dcf_impl()
    display(current_figure())
    return nothing
end

end # module
