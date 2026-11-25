# make_faf5net.jl -- derive Logjam's road network from FAF5 (CR 19, PCV N2), write it as three CSV files, and pack them
# as the `faf5net` artifact (PCV N3, D7).
#
#   julia +1.12.6 --project=<repo> tools/v0_3_1/make_faf5net.jl <output directory>
#
# Reads faf5nodes() and faf5links() (copies, so the tables Logjam ships are never changed), runs the derivation
# (Logjam._faf5net, src/faf5net.jl: ramps and junctions, each route's two directions paired from stop to stop and
# judged by rule C, the junctions collapsed, the node map and the attributes) and writes faf5net_nodes.csv,
# faf5net_links.csv and faf5net_nodemap.csv to the output directory, with Logjam._faf5net_csv, the writer the tests
# use. The directory lies outside the repository: the files ship as a lazy artifact (D7), never in git. The output is
# the same byte for byte from run to run and on Julia 1.12 and 1.13: each table sorted by its keys, DIST and the times
# written with 4 decimals, a coordinate in the shortest form that reads back as FAF5's own value, a missing value as an
# empty field, LF line endings, no time stamps.
#
# Then packs the three files as faf5net.tar.gz in the same directory, the artifact's release asset: a tar whose root
# holds the three files, each recorded as a plain file (mode 644, as faf5's), with no time stamps (Tar.create), gzip-
# compressed at level 9 with zlib, whose header carries no time stamp, and its operating-system byte set to 255
# ("unknown", RFC 1952) so the bytes do not depend on the machine that packs them. Prints each file's SHA-256 and size,
# the tarball's SHA-256 and size, and its git-tree-sha1: the two hashes Artifacts.toml's [faf5net] entry holds.

using Logjam, DataFrames, SHA, Tar

const FILES = ("faf5net_nodes.csv", "faf5net_links.csv", "faf5net_nodemap.csv")

gzip9(cz, buf) = cz.transcode(cz.GzipCompressor(level = 9), buf)

# The three files as faf5net.tar.gz in `out`; returns the tarball's path, its SHA-256 and its git-tree-sha1.
function pack(out)
    tarball = mktempdir() do d
        for f in FILES
            p = joinpath(d, f)
            cp(joinpath(out, f), p)
            chmod(p, 0o644)                 # a plain file, not an executable, on every platform
        end
        io = IOBuffer(); Tar.create(d, io); take!(io)
    end
    tree = Tar.tree_hash(IOBuffer(tarball))
    # CodecZlib is in Logjam's manifest, through its dependencies
    cz = Base.require(Base.PkgId(Base.UUID("944b1d66-785c-5afd-91f1-9de20f533193"), "CodecZlib"))
    gz = Base.invokelatest(gzip9, cz, tarball)
    gz[10] = 0xff                           # the gzip header's operating-system byte: unknown
    path = joinpath(out, "faf5net.tar.gz")
    write(path, gz)
    return path, bytes2hex(sha256(gz)), tree
end

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
        Logjam._faf5net_csv(joinpath(out, f), df)
    end
    for f in FILES
        p = joinpath(out, f)
        println(bytes2hex(open(sha256, p)), "  ", lpad(filesize(p), 10), "  ", f)
    end
    path, sha, tree = pack(out)
    println(sha, "  ", lpad(filesize(path), 10), "  ", basename(path), " (sha256)")
    println("git-tree-sha1 = \"", tree, "\"")
end

length(ARGS) == 1 || error("usage: julia --project=<repo> tools/v0_3_1/make_faf5net.jl <output directory>")
main(ARGS[1])
