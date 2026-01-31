module LogjamGLMakieExt

using Logjam
using GLMakie

# Register GLMakie as available backend
function __init__()
    Logjam._glmakie_available[] = true
    Logjam._glmakie_activate[] = GLMakie.activate!
end

end
