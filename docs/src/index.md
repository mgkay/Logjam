```@meta
CurrentModule = Logjam
```

# Logjam

Welcome to the documentation for Logjam.

This package provides tools for geographical mapping and handling U.S. geographical and statistical data.

## GLMakie Extension

Logjam uses CairoMakie by default. GLMakie support is provided via a package extension that is automatically loaded when GLMakie is available. For interactive display, load GLMakie before Logjam:

```julia
using GLMakie  # Triggers LogjamGLMakieExt extension
using Logjam

fig, ax = makemap(region=:US, backend=:GLMakie)
```

```@index
```

## Map Functions

Functions for creating geographical maps using the Makie ecosystem.

### Constants

```@docs
WORLD_LIMITS
US_LIMITS
CUS_LIMITS
```

### Functions

```@docs
makemap
mapbbox
aligntext
bestfit
isptinbbox
```

## Data Functions

Functions for working with U.S. geographical and statistical data.

### Geographic Data

```@docs
usplace
uscounty
uscentract
uscenblkgrp
uszcta5
uszcta3
uscbsa
uscsa
```

### FIPS Conversion

```@docs
st2fips
fips2st
```