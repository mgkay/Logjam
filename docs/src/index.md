```@meta
CurrentModule = Logjam
```

# Logjam

Welcome to the documentation for Logjam.

This package provides tools for geographical mapping and handling U.S. geographical and statistical data.

## Optional GLMakie Support

Logjam uses CairoMakie by default. For interactive display with GLMakie, load it before using the `:GLMakie` backend:

```julia
using GLMakie  # Enables backend=:GLMakie
using Logjam

fig, ax = makemap(region=:US, backend=:GLMakie)
```

```@index
```

```@autodocs
Modules = [Logjam]
```