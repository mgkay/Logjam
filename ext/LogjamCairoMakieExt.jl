module LogjamCairoMakieExt

using Logjam
using CairoMakie

function __init__()
    Logjam._cairomakie_available[] = true
    Logjam._cairomakie_activate[] = CairoMakie.activate!
    Logjam._dcf_impl[] = _dcf_impl
    Logjam._plotnetwork_impl[] = _plotnetwork_impl
end

# H7: dcf - display current figure
function _dcf_impl()
    display(current_figure())
    return nothing
end

# H8: plotnetwork
function _plotnetwork_impl(C::AbstractMatrix; xy=nothing, weights=true, labels=1:size(C,1))
    n = size(C, 1)
    if n == 0
        fig = Figure()
        Axis(fig[1,1])
        return fig, Matrix{Float64}(undef, 0, 2)
    end

    # Compute layout if not provided
    if xy === nothing
        θ = range(0, 2π, length=n+1)[1:n]
        xy = hcat(cos.(θ), sin.(θ))
    end

    fig = Figure()
    ax = Axis(fig[1,1], aspect=DataAspect())
    hidedecorations!(ax)

    # Draw edges
    for i in 1:n
        for j in 1:n
            if C[i,j] != 0
                linesegments!(ax, [Point2f(xy[i,1], xy[i,2]), Point2f(xy[j,1], xy[j,2])];
                             color=:gray60, linewidth=1.5)
                if weights
                    mx = (xy[i,1] + xy[j,1]) / 2
                    my = (xy[i,2] + xy[j,2]) / 2
                    text!(ax, mx, my; text=string(C[i,j]), fontsize=10, align=(:center, :center))
                end
            end
        end
    end

    # Draw nodes
    scatter!(ax, xy[:,1], xy[:,2]; markersize=20, color=:white, strokewidth=2, strokecolor=:black)

    # Labels
    for i in 1:n
        text!(ax, xy[i,1], xy[i,2]; text=string(labels[i]), fontsize=12, align=(:center, :center))
    end

    return fig, xy
end

end # module
