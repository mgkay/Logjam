# run_against.jl -- run test files against Logjam at a given revision (test spec Sec. 1 rule 3; PCV K2a).
#
#   julia +1.12.6 --startup-file=no tools/v0_3_0/run_against.jl <rev> <testfile>... [options]
#
#   <rev>        v0.2.8 (or any tag, branch or commit), HEAD (the committed head of this worktree), or
#                WORKTREE (the working tree as it stands, uncommitted edits included; for development)
#   <testfile>   one or more test files, e.g. test/test_transtools.jl (relative to the repository, or absolute)
#
#   --csv=PATH   the outcomes table (default: the environment variable LOGJAM_SC2_CSV; one of the two, or --no-csv, is required)
#   --no-csv     print only; do not write the table
#   --strict=auto|yes|no
#                yes: every `@test_broken` in the file is run as `@test`, so a test written as broken
#                (its fix not landed) FAILS where the code is wrong, instead of being counted Broken.
#                auto (default): yes for every revision except HEAD and WORKTREE, where a test that is
#                still broken is the expected, green state.
#   --julia=CMD  the julia launcher for the child processes (default: the julia running this script)
#   --online     allow the package manager the network (default: JULIA_PKG_OFFLINE=true)
#   --keep       keep the temporary directory and worktree (for debugging); prints their path
#
# WHAT IT DOES. (1) makes a temporary directory; (2) for a revision, adds a DETACHED `git worktree` of this
# repository at it under the temporary directory (never the shared checkout, never a branch change);
# (3) writes a scratch project there holding Logjam's dependencies, the packages the test files `using`,
# and Logjam itself developed from the worktree, seeded from this repository's own Manifest so the
# versions match; (4) runs each test file in a fresh child julia, with the temporary directory as the
# FIRST depot (so every compile cache and anything installed is thrown away with it) and the real depot
# after it (read only); (5) records each tagged testset's outcome; (6) removes the worktree with
# `git worktree remove` and deletes the temporary directory.
#
# THE TAG. A testset whose name begins `[ID]`, e.g. `@testset "[N3] charge_tl takes the TL minimum per
# shipment"`, is one row of the table. ID is N<n>, CR <n> or S<n>. Outcome of a row: error if any
# assertion in it errored, fail if any failed, broken if (no error, no fail) any is `@test_broken`,
# else pass. An un-tagged testset only counts toward the totals that are printed.
#
# THE TABLE. Columns: ID, test name, file, v0.2.8 result, v0.3.0 result. Revision v0.2.8 fills the
# fourth column; HEAD and WORKTREE fill the fifth (the branch). Rows already there are updated in
# place; other rows are untouched. The shared course environment is never read or written, and
# Pkg.update is never run.

using TOML

const REPO = dirname(dirname(@__DIR__))
const DEFAULT_CSV = get(ENV, "LOGJAM_SC2_CSV", "")   # no path is built in: the table lives outside this repository
const TAG_RE = r"^\[((?:N|CR |S)\d+[a-z]?)\]\s*(.*)$"s

# ----------------------------------------------------------------------------- arguments
function parse_args(args)
    opts = Dict{String,Any}("csv" => DEFAULT_CSV, "strict" => "auto", "julia" => nothing,
                            "online" => false, "keep" => false, "nocsv" => false)
    pos = String[]
    for a in args
        if startswith(a, "--csv=");        opts["csv"] = a[7:end]
        elseif startswith(a, "--strict="); opts["strict"] = a[10:end]
        elseif startswith(a, "--julia=");  opts["julia"] = a[9:end]
        elseif a == "--online";            opts["online"] = true
        elseif a == "--keep";              opts["keep"] = true
        elseif a == "--no-csv";            opts["nocsv"] = true
        elseif startswith(a, "--");        error("unknown option $a")
        else push!(pos, a) end
    end
    (opts["nocsv"] || !isempty(opts["csv"])) ||
        error("run_against.jl: name the outcomes table with --csv=PATH or the environment variable LOGJAM_SC2_CSV, or pass --no-csv")
    length(pos) >= 2 || error("usage: run_against.jl <rev> <testfile>... [--csv=PATH] [--no-csv] [--strict=auto|yes|no] [--julia=CMD] [--online] [--keep]")
    return opts, pos[1], pos[2:end]
end

# ----------------------------------------------------------------------------- csv (minimal, quote-all)
function csv_split(line)
    out, cur, inq, i = String[], IOBuffer(), false, 1
    while i <= lastindex(line)
        c = line[i]
        if inq
            if c == '"'
                if i < lastindex(line) && line[nextind(line, i)] == '"'
                    write(cur, '"'); i = nextind(line, i)
                else inq = false end
            else write(cur, c) end
        else
            if c == '"'; inq = true
            elseif c == ','; push!(out, String(take!(cur)))
            else write(cur, c) end
        end
        i = nextind(line, i)
    end
    push!(out, String(take!(cur)))
    return out
end
csv_join(fields) = join(("\"" * replace(string(f), "\"" => "\"\"") * "\"" for f in fields), ",")

const HEADER = ["ID", "test name", "file", "v0.2.8 result", "v0.3.0 result"]
function read_table(path)
    rows = Vector{Vector{String}}()
    isfile(path) || return rows
    lines = readlines(path)
    for l in lines[2:end]
        isempty(strip(l)) && continue
        f = csv_split(l)
        length(f) == 5 || continue
        push!(rows, f)
    end
    return rows
end
function id_key(id)
    m = match(r"^(N|CR |S)(\d+)", id)
    m === nothing && return (9, 0, id)
    return ((N = 0, CR = 1, S = 2)[Symbol(strip(m[1]))], parse(Int, m[2]), id)
end
function write_table(path, rows)
    mkpath(dirname(path))
    sort!(rows; by = r -> (id_key(r[1]), r[3], r[2]))
    open(path, "w") do io
        println(io, csv_join(HEADER))
        for r in rows
            println(io, csv_join(r))
        end
    end
end

# ----------------------------------------------------------------------------- helpers
sh(cmd) = (run(cmd); nothing)
function git(args...)
    return read(`git -C $REPO $(collect(args))`, String)
end
depot_sep() = Sys.iswindows() ? ";" : ":"

usings(file) = begin
    names = String[]
    for l in eachline(file)
        m = match(r"^\s*(?:using|import)\s+([A-Za-z0-9_.,\s]+?)(?::|$)", l)
        m === nothing && continue
        for n in split(m[1], ',')
            n = strip(n)
            isempty(n) || push!(names, first(split(n, '.')))
        end
    end
    return unique(names)
end

function write_scratch_project(envdir, testfiles)
    proj = TOML.parsefile(joinpath(REPO, "Project.toml"))
    deps = copy(get(proj, "deps", Dict{String,Any}()))
    extras = get(proj, "extras", Dict{String,Any}())
    for f in testfiles, n in usings(f)
        haskey(extras, n) && (deps[n] = extras[n])
    end
    # Logjam's own extension triggers are weak dependencies; load them only if the test file names them
    mkpath(envdir)
    open(joinpath(envdir, "Project.toml"), "w") do io
        TOML.print(io, Dict("deps" => deps))
    end
    ver = "Manifest-v$(VERSION.major).$(VERSION.minor).toml"
    seed = isfile(joinpath(REPO, ver)) ? joinpath(REPO, ver) : joinpath(REPO, "Manifest.toml")
    isfile(seed) && cp(seed, joinpath(envdir, "Manifest.toml"); force = true)
end

# ----------------------------------------------------------------------------- child: setup and test run
const SETUP_JL = raw"""
using Pkg
Pkg.activate(ARGS[1])
Pkg.develop(path = ARGS[2])
Pkg.resolve()
Pkg.instantiate()
Pkg.precompile()
println("scratch environment ready")
"""

const CHILD_JL = raw"""
using Test
using Logjam          # what test/runtests.jl loads before it includes a test file
const TESTFILE, OUT, STRICT = ARGS[1], ARGS[2], ARGS[3] == "1"
txt = read(TESTFILE, String)
STRICT && (txt = replace(txt, "@test_broken" => "@test"))
crash = ""
ROOT = Ref{Any}(nothing)
# The file runs inside one outer @testset, whose object is taken just before the block ends (when every
# nested testset has been recorded in it); the throw that a failing outer testset ends with is caught.
# (Test.push_testset, the older way to do this, does not exist in Julia 1.13.)
try
    @testset "root" begin
        try
            include_string(Main, txt, TESTFILE)
        catch e
            global crash = sprint(showerror, e, catch_backtrace())
        end
        ROOT[] = Test.get_testset()
    end
catch e
    e isa Test.TestSetException || rethrow()
end
root = ROOT[]
const TAG = r"^\[((?:N|CR |S)\d+[a-z]?)\]\s*(.*)$"s
np(c) = c.passes + c.cumulative_passes      # direct results plus those of nested testsets
nf(c) = c.fails + c.cumulative_fails
ne(c) = c.errors + c.cumulative_errors
nb(c) = c.broken + c.cumulative_broken
outcome(c) = ne(c) > 0 ? "error" : nf(c) > 0 ? "fail" : nb(c) > 0 ? "broken" : np(c) > 0 ? "pass" : "empty"
rows = String[]
function walk(ts)
    for r in ts.results
        r isa Test.DefaultTestSet || continue
        m = match(TAG, r.description)
        if m === nothing
            walk(r)
        else
            c = Test.get_test_counts(r)
            push!(rows, join([m[1], replace(m[2], '\t' => ' '), outcome(c), np(c), nf(c), ne(c), nb(c)], '\t'))
        end
    end
end
walk(root)
tot = Test.get_test_counts(root)
open(OUT, "w") do io
    println(io, "#totals\t", np(tot), "\t", nf(tot), "\t", ne(tot), "\t", nb(tot))
    println(io, "#crash\t", replace(crash, '\n' => " | ", '\t' => ' '))
    foreach(r -> println(io, r), rows)
end
"""

# ----------------------------------------------------------------------------- main
function main()
    opts, rev, files = parse_args(ARGS)
    testfiles = [abspath(isabspath(f) ? f : joinpath(REPO, f)) for f in files]
    foreach(f -> isfile(f) || error("no such test file: $f"), testfiles)
    strict = opts["strict"] == "yes" || (opts["strict"] == "auto" && !(rev in ("HEAD", "WORKTREE")))
    julia = opts["julia"] === nothing ? [Base.julia_cmd().exec[1]] : split(opts["julia"])
    jl(args...) = Cmd(vcat(julia, ["--startup-file=no", "--color=no"], collect(args)))

    tmp = mktempdir(; prefix = "tmpclaude_runagainst_")
    wt = joinpath(tmp, "Logjam")
    made_worktree = false
    results = Dict{String,Vector{Vector{String}}}()   # file => rows
    try
        if rev == "WORKTREE"
            wt = REPO
            logjam_sha = strip(git("rev-parse", "HEAD")) * "+worktree"
        else
            git("worktree", "add", "--detach", wt, rev)
            made_worktree = true
            logjam_sha = strip(git("rev-parse", rev * "^{commit}"))
        end
        println("run_against: rev=$rev ($(logjam_sha[1:min(end, 10)])) julia=$VERSION strict=$strict")
        envdir = joinpath(tmp, "env")
        write_scratch_project(envdir, testfiles)
        depot = joinpath(tmp, "depot")
        mkpath(depot)
        childenv = Dict("JULIA_DEPOT_PATH" => join(vcat([depot], DEPOT_PATH), depot_sep()),
                        "JULIA_PROJECT" => envdir)
        opts["online"] || (childenv["JULIA_PKG_OFFLINE"] = "true")
        rundir = joinpath(tmp, "run")
        mkpath(rundir)

        setup = joinpath(tmp, "setup.jl"); write(setup, SETUP_JL)
        child = joinpath(tmp, "child.jl"); write(child, CHILD_JL)
        run(Cmd(jl(setup, envdir, wt); env = childenv, dir = rundir))

        for (k, tf) in enumerate(testfiles)
            out = joinpath(tmp, "out$k.tsv")
            println("-- running ", relpath(tf, REPO))
            run(ignorestatus(Cmd(jl("--project=$envdir", child, tf, out, strict ? "1" : "0");
                                 env = childenv, dir = rundir)))
            isfile(out) || (println("   no result file (the child died before finishing)"); continue)
            lines = readlines(out)
            totals = split(lines[1], '\t')[2:end]
            crash = length(lines) >= 2 ? join(split(lines[2], '\t')[2:end], ' ') : ""
            println("   totals: pass=$(totals[1]) fail=$(totals[2]) error=$(totals[3]) broken=$(totals[4])")
            isempty(crash) || println("   TOP-LEVEL ERROR (tests after it did not run): ", first(crash, 600))
            rows = [split(l, '\t') for l in lines[3:end]]
            results[relpath(tf, joinpath(REPO, "test"))] = [String.(r) for r in rows]
            for r in rows
                println("   [", r[1], "] ", rpad(r[3], 6), " (pass ", r[4], ", fail ", r[5], ", error ", r[6], ", broken ", r[7], ")  ", first(r[2], 70))
            end
        end

        if !opts["nocsv"]
            col = rev == "v0.2.8" ? 4 : 5
            (rev == "v0.2.8" || rev in ("HEAD", "WORKTREE")) ||
                println("note: revision $rev is recorded in the fifth column (the branch's)")
            table = read_table(opts["csv"])
            for (file, rows) in results, r in rows
                id, name, res = String(r[1]), String(r[2]), String(r[3])
                i = findfirst(t -> t[1] == id && t[3] == file && t[2] == name, table)
                if i === nothing
                    push!(table, [id, name, file, "", ""])
                    i = length(table)
                end
                table[i][col] = res
            end
            write_table(opts["csv"], table)
            println("wrote ", opts["csv"], " (", length(table), " rows)")
        end
    finally
        if opts["keep"]
            println("kept: ", tmp)
        else
            if made_worktree
                # remove only our own worktree; `git worktree prune` is not run, it would touch other
                # worktrees' administrative entries in the shared repository
                try git("worktree", "remove", "--force", wt) catch e println("worktree remove failed: ", e) end
            end
            try rm(tmp; recursive = true, force = true) catch e println("could not delete $tmp: ", e) end
        end
    end
end

main()
