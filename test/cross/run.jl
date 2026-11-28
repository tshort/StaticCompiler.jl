# Runs the executables that `test/cross/matrix.jl` kept, where they can run: `julia test/cross/run.jl dir`.
# `dir/<host>/<triple>/<name>` was made on `<host>` for `<triple>`. The ones that this machine can run (its system and its architecture) are run, and each has to return 42 (the program returns `argc + 41`).
# Exits with a status that is not 0 if one that could be run did not do that.

host_arch = Sys.ARCH === :x86_64 ? "x86_64" : Sys.ARCH === :aarch64 ? "aarch64" : string(Sys.ARCH)
host_system = Sys.iswindows() ? "windows" : Sys.islinux() ? "linux" : Sys.isapple() ? "macos" : string(Sys.KERNEL)

# whether a program for the triple runs here: the system, and the architecture (an Apple Silicon Mac runs x86-64 programs of macOS with Rosetta, if it has it)
function runs_here(triple)
    arch = first(split(triple, '-'))
    arch == "x86_64" || arch == "aarch64" || return false
    system = occursin("apple", triple) ? "macos" : occursin("linux", triple) ? "linux" : occursin("mingw", triple) || occursin("windows", triple) ? "windows" : "?"
    system == host_system || return false
    arch == host_arch && return true
    return system == "macos" && host_arch == "aarch64" && arch == "x86_64" && success(pipeline(`arch -x86_64 /usr/bin/true`; stderr = devnull))
end

dir = abspath(ARGS[1])
rows = NamedTuple[]
for made_on in sort(readdir(dir)), triple in sort(readdir(joinpath(dir, made_on)))
    runs_here(triple) || continue
    for file in readdir(joinpath(dir, made_on, triple))
        exe = joinpath(dir, made_on, triple, file)
        Sys.iswindows() || chmod(exe, 0o755)
        command = host_system == "macos" && !startswith(triple, host_arch) ? `arch -x86_64 $exe` : `$exe`
        p = run(pipeline(ignorestatus(command); stdout = devnull, stderr = devnull))
        push!(rows, (; made_on, triple, result = p.exitcode == 42 ? "ok" : "exit status $(p.exitcode) (42 wanted)"))
    end
end

host = string(host_arch, "-", host_system)
table = string("| made on | for | run on `", host, "` |\n|:--|:--|:--|\n", join(("| $(r.made_on) | `$(r.triple)` | $(r.result) |" for r in rows), "\n"), "\n")
println(table)
haskey(ENV, "GITHUB_STEP_SUMMARY") && open(io -> println(io, "\n### Executables run on ", host, "\n\n", isempty(rows) ? "none of those that were made are for this machine" : table), ENV["GITHUB_STEP_SUMMARY"], "a")
all(r -> r.result == "ok", rows) || exit(1)
