# What can be made from this host, for each target: `julia test/cross/matrix.jl [outdir]`.
# For each target it tries three things: the LLVM IR, an object file, and a linked executable (the program returns `argc + 41`: 42 when it is run with no arguments), and says what each came to.
# The table is printed, and written to `$GITHUB_STEP_SUMMARY` where there is one. With `outdir`, the executables are kept as `outdir/<host>/<triple>/<name>`, for `test/cross/run.jl` to run on a machine of their target.
# It makes an environment of its own, with the extensions of StaticCompiler that fetch the C libraries of the targets (`Glibc_jll`, `Mingw_jll`).
#
# What a host needs for a target: the code generator for it (Julia's LLVM has the host's architecture and WebAssembly; an `llc` of the same version of LLVM has others: `STATIC_COMPILER_LLC`), and for the link the
# libraries of the target: fetched for Linux and Windows, and for macOS an SDK (Xcode's on a Mac, else the directory in `SDKROOT`).

import Pkg
Pkg.activate(temp = true; io = devnull)
Pkg.develop(path = dirname(dirname(@__DIR__)); io = devnull)
Pkg.add(["Glibc_jll", "Mingw_jll", "LLVM", "Pkg"]; io = devnull)
using StaticCompiler, Glibc_jll, Mingw_jll, LLVM, Pkg
using Base.BinaryPlatforms

const SC = StaticCompiler
host = string(Sys.ARCH, "-", Sys.KERNEL === :NT ? "windows" : Sys.islinux() ? "linux" : Sys.isapple() ? "macos" : string(Sys.KERNEL))
outdir = length(ARGS) >= 1 ? abspath(ARGS[1]) : nothing

matrix_main(argc::Int, argv::Ptr{Ptr{UInt8}}) = (argc + 41) % Int

# the targets, and how each is linked (a function that makes the toolchain, which may say that a resource is missing by throwing)
const TARGETS = [
    ("aarch64-unknown-linux-gnu", () -> SC.LLDToolchain(:gnu; sysroot = SC.glibc_sysroot("aarch64-unknown-linux-gnu"))),
    ("x86_64-unknown-linux-gnu",  () -> SC.LLDToolchain(:gnu; sysroot = SC.glibc_sysroot("x86_64-unknown-linux-gnu"))),
    ("aarch64-apple-macosx11.0.0", () -> SC.LLDToolchain(:darwin)),
    ("x86_64-apple-macosx11.0.0",  () -> SC.LLDToolchain(:darwin)),
    ("x86_64-w64-mingw32",        () -> SC.LLDToolchain(:mingw; sysroot = SC.mingw_sysroot("x86_64-w64-mingw32"))),
    ("wasm64-unknown-unknown",    () -> SC.LLDToolchain(:wasm)),
]

short(e) = first(split(sprint(showerror, e), '\n'))
status(f) = try; f(); "ok"; catch e; "fails: " * first(short(e), 90); end

rows = NamedTuple[]
for (triple, make_toolchain) in TARGETS
    println("\n## ", triple)
    llc = get(ENV, "STATIC_COMPILER_LLC", nothing)
    target = try; SC.StaticTarget(triple; llc); catch e; nothing; end
    if target === nothing
        push!(rows, (; triple, ir = "fails", object = "-", link = "-")); continue
    end
    backend = SC.julia_llvm_has(triple)
    # the IR is made for any target (the host's code, retargeted)
    ir_target = SC.StaticTarget(triple; retarget = true)
    ir = status() do
        text = SC.generate_ir(matrix_main, Tuple{Int,Ptr{Ptr{UInt8}}}; target = ir_target, main_wrapper = "matrix_main")
        occursin("define i32 @main", text) || error("no `main` in the IR")
    end
    println("   IR:     ", ir)
    # the object: by Julia's LLVM if it has the code generator, or by `llc`
    object = !SC.can_emit_object(target) ? "no code generator (needs an `llc`)" : status() do
        dir = mktempdir()
        _, obj = SC.generate_obj(((matrix_main, Tuple{Int,Ptr{Ptr{UInt8}}}),), dir, "matrix_main"; target, main_wrapper = "matrix_main")
        filesize(obj) > 100 || error("the object is empty")
    end
    println("   object: ", object)
    # the executable
    link = if !SC.can_emit_object(target)
        "no code generator"
    else
        status() do
            linked = SC.StaticTarget(target; toolchain = make_toolchain()) # (a copy that is linked so, and not the target itself)
            dir = mktempdir()
            exe = compile_executable(matrix_main, (Int, Ptr{Ptr{UInt8}}), dir, "matrix_main"; target = linked)
            isfile(exe) || error("no executable")
            if outdir !== nothing
                kept = joinpath(outdir, host, triple)
                mkpath(kept)
                cp(exe, joinpath(kept, basename(exe)); force = true)
            end
        end
    end
    println("   link:   ", link)
    push!(rows, (; triple, ir, object, link))
end

table = string("| host `", host, "` makes for | IR | object | executable |\n|:--|:--|:--|:--|\n",
               join(("| `$(r.triple)` | $(r.ir) | $(r.object) | $(r.link) |" for r in rows), "\n"), "\n")
println("\n", table)
haskey(ENV, "GITHUB_STEP_SUMMARY") && open(io -> println(io, "\n### Compile matrix, host ", host, ", Julia ", VERSION, "\n\n", table), ENV["GITHUB_STEP_SUMMARY"], "a")
