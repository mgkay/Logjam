# make_faf5net.jl -- derive Logjam's road network from FAF5 (CR 19, PCV N2) and write it as three CSV files.
#
#   julia +1.12.6 --project=<repo> tools/v0_3_2/make_faf5net.jl <output directory>
#
# Reads faf5nodes() and faf5links() (copies, so the tables Logjam ships are never changed), runs the derivation
# (Logjam._faf5net, src/faf5net.jl: ramps and junctions, each route's two directions paired from stop to stop and
# judged by rule C, the junctions collapsed, the node map and the attributes) and writes faf5net_nodes.csv,
# faf5net_links.csv and faf5net_nodemap.csv to the output directory. The directory lies outside the repository: the
# files ship as a lazy artifact (D7), never in git. The output is the same byte for byte from run to run and on Julia
# 1.12 and 1.13: each table sorted by its keys, DIST and the times written with 4 decimals, a coordinate in the shortest
# form that reads back as FAF5's own value, a missing value as an empty field, LF line endings, no time stamps. Prints
# each file's SHA-256 and size, and the size of the three as one gzip-compressed tar.

using Logjam, DataFrames, Printf, SHA, Tar

const FILES = ("faf5net_nodes.csv", "faf5net_links.csv", "faf5net_nodemap.csv")
const FOUR = Set(["DIST", "AB_TIME", "BA_TIME"])            # written with 4 decimals

# One field as text: a missing value empty, DIST or a time with 4 decimals, a coordinate in its shortest exact form,
# text quoted when it holds a comma, a quote or a line break.
function field(col, x)
    ismissing(x) && return ""
    x isa Bool && return x ? "true" : "false"
    x isa Integer && return string(x)
    x isa AbstractFloat && return col in FOUR ? @sprintf("%.4f", x) : string(Float64(x))
    s = string(x)
    return occursin(r"[,\"\r\n]", s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s
end

function writetable(path, df)
    cols = names(df)
    open(path, "w") do io
        write(io, join(cols, ','), '\n')
        for r in 1:nrow(df)
            write(io, join((field(c, df[r, c]) for c in cols), ','), '\n')
        end
    end
end

gzipsize(cz, buf) = length(cz.transcode(cz.GzipCompressor, buf))

function main(out)
    repo = lowercase(rstrip(normpath(pkgdir(Logjam)), ['\\', '/'])); o = lowercase(rstrip(normpath(abspath(out)), ['\\', '/']))
    (o == repo || startswith(o, repo * "/") || startswith(o, repo * "\\")) &&
        error("the output directory must lie outside the repository (the data ship as an artifact): $out")
    isdir(out) || mkpath(out)
    t0 = time()
    R = Logjam._faf5net(faf5nodes(), faf5links())
    println("derived ", nrow(R.nodes), " nodes, ", nrow(R.links), " links, ", nrow(R.nodemap), " node map rows in ",
            round(time() - t0, digits = 1), " s")
    for (f, df) in zip(FILES, (R.nodes, R.links, R.nodemap))
        writetable(joinpath(out, f), df)
    end
    for f in FILES
        p = joinpath(out, f)
        println(bytes2hex(open(sha256, p)), "  ", lpad(filesize(p), 10), "  ", f)
    end
    # the three files as one tar, gzip-compressed (CodecZlib is in Logjam's manifest, through its dependencies)
    buf = mktempdir() do d
        for f in FILES
            cp(joinpath(out, f), joinpath(d, f))
        end
        io = IOBuffer(); Tar.create(d, io); take!(io)
    end
    cz = Base.require(Base.PkgId(Base.UUID("944b1d66-785c-5afd-91f1-9de20f533193"), "CodecZlib"))
    println("tar ", length(buf), " bytes; gzip-compressed ", Base.invokelatest(gzipsize, cz, buf), " bytes")
end

length(ARGS) == 1 || error("usage: julia --project=<repo> tools/v0_3_2/make_faf5net.jl <output directory>")
main(ARGS[1])
