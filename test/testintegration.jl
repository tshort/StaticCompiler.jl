# Setup
testpath = pwd()
scratch = tempdir()
cd(scratch)

if VERSION >= v"1.9"
    # Bumper uses PackageExtensions to work with StaticCompiler, so let's just skip this test on 1.8
    function bumper_test(N::Int)
        buf = AllocBuffer(MallocVector, sizeof(Float64) * N)
        s = 0.0
        for i in 1:N
            # some excuse to reuse the same memory a bunch of times
            @no_escape buf begin
                v = @alloc(Float64, N)
                v .= i
                s += sum(v)
            end
        end
        free(buf)
        return s
    end

    @testset "Bumper.jl integration" begin
        target = StaticTarget()
        StaticCompiler.set_runtime!(target, true)
        path = compile_shlib(bumper_test, (Int,), "./"; target = target)
        ptr = Libdl.dlopen(path, Libdl.RTLD_LOCAL)

        fptr = Libdl.dlsym(ptr, "bumper_test")

        @test bumper_test(8) == @ccall($fptr(8::Int)::Float64)
    end
end

@testset "Standalone Executable Integration" begin

    jlpath = joinpath(Sys.BINDIR, Base.julia_exename()) # Get path to julia executable

    ## --- Times table, file IO, mallocarray
    let
        # Attempt to compile
        # We have to start a new Julia process to get around the fact that Pkg.test
        # disables `@inbounds`, but ironically we can use `--compile=min` to make that
        # faster.
        status = -1
        try
            isfile("times_table") && rm("times_table")
            isfile("table.b") && rm("table.b")
            isfile("table.tsv") && rm("table.tsv")
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/times_table.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/times_table.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        compile_ok = isa(status, Base.Process) && status.exitcode == 0
        if compile_ok
            @test status.exitcode == 0
        else
            @test_broken compile_ok
        end

        # Attempt to run
        println("5x5 times table:")
        status = -1
        try
            status = run(`./times_table 5 5`)
        catch e
            @warn "Could not run $(scratch)/times_table"
            println(e)
        end
        run_ok = isa(status, Base.Process) && status.exitcode == 0
        if run_ok
            @test status.exitcode == 0
            # Test ascii output
            # @test parsedlm(Int, c"table.tsv", '\t') == (1:5)*(1:5)' broken=Sys.isapple()
            # Test binary output
            @test fread!(szeros(Int, 5, 5), c"table.b") == (1:5) * (1:5)'
        else
            @test_broken run_ok
        end
    end

    ## --- "withmallocarray"-type do-block pattern
    let
        # Compile...
        status = -1
        try
            isfile("withmallocarray") && rm("withmallocarray")
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/withmallocarray.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/withmallocarray.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        compile_ok = isa(status, Base.Process) && status.exitcode == 0
        if compile_ok
            @test status.exitcode == 0
        else
            @test_broken compile_ok
        end

        # Run...
        println("3x3 malloc arrays via do-block syntax:")
        status = -1
        try
            status = run(`./withmallocarray 3 3`)
        catch e
            @warn "Could not run $(scratch)/withmallocarray"
            println(e)
        end
        @test isa(status, Base.Process)
        run_ok = isa(status, Base.Process) && status.exitcode == 0
        if run_ok
            @test run_ok
        else
            @test_broken run_ok
        end
    end

    ## --- Random number generation
    let
        # Compile...
        status = -1
        try
            isfile("rand_matrix") && rm("rand_matrix")
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/rand_matrix.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/rand_matrix.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        println("5x5 uniform random matrix:")
        status = -1
        try
            status = run(`./rand_matrix 5 5`)
        catch e
            @warn "Could not run $(scratch)/rand_matrix"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
    end

    let
        # Compile...
        status = -1
        try
            isfile("randn_matrix") && rm("randn_matrix")
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/randn_matrix.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/randn_matrix.jl"
            println(e)
        end
        if Sys.isbsd()
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0
        end

        # Run...
        println("5x5 Normal random matrix:")
        status = -1
        try
            status = run(`./randn_matrix 5 5`)
        catch e
            @warn "Could not run $(scratch)/randn_matrix"
            println(e)
        end
        if Sys.isbsd()
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0
        end
    end

    ## --- Test LoopVectorization integration
    if Bool(LoopVectorization.VectorizationBase.has_feature(Val{:x86_64_avx2}))
        let
            # Compile...
            status = -1
            try
                isfile("loopvec_product") && rm("loopvec_product")
                status = run(`$jlpath --startup=no --compile=min $testpath/scripts/loopvec_product.jl`)
            catch e
                @warn "Could not compile $testpath/scripts/loopvec_product.jl"
                println(e)
            end
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0

            # Run...
            println("10x10 table sum:")
            status = -1
            try
                status = run(`./loopvec_product 10 10`)
            catch e
                @warn "Could not run $(scratch)/loopvec_product"
                println(e)
            end
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0
            # @test parsedlm(c"product.tsv",'\t')[] == 3025
        end
    end

    let
        # Compile...
        status = -1
        try
            isfile("loopvec_matrix") && rm("loopvec_matrix")
            status = run(`$jlpath --startup=no $testpath/scripts/loopvec_matrix.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/loopvec_matrix.jl"
            println(e)
        end
        compile_ok = isa(status, Base.Process) && status.exitcode == 0
        compile_ok || @test_broken compile_ok
        compile_ok && @test status.exitcode == 0

        # Run...
        println("10x5 matrix product:")
        status = -1
        try
            status = run(`./loopvec_matrix 10 5`)
        catch e
            @warn "Could not run $(scratch)/loopvec_matrix"
            println(e)
        end
        run_ok = isa(status, Base.Process) && status.exitcode == 0
        if run_ok
            @test status.exitcode == 0
            A = (1:10) * (1:5)'
            # Check ascii output
            # @test parsedlm(c"table.tsv",'\t') == A' * A broken=Sys.isapple()
            # Check binary output
            @test fread!(szeros(5, 5), c"table.b") == A' * A
        else
            @test_broken run_ok
        end
    end

    let
        # Compile...
        status = -1
        try
            isfile("loopvec_matrix_stack") && rm("loopvec_matrix_stack")
            status = run(`$jlpath --startup=no  $testpath/scripts/loopvec_matrix_stack.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/loopvec_matrix_stack.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        println("10x5 matrix product:")
        status = try
            run(`./loopvec_matrix_stack`)
        catch e
            @warn "Could not run $(scratch)/loopvec_matrix_stack"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        A = (1:10) * (1:5)'
        # @test parsedlm(c"table.tsv",'\t') == A' * A broken=Sys.isapple()
        @test fread!(szeros(5, 5), c"table.b") == A' * A
    end


    ## --- Test string handling

    let
        # Compile...
        status = -1
        try
            isfile("print_args") && rm("print_args")
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/print_args.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/print_args.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        println("String indexing and handling:")
        status = -1
        try
            status = run(`./print_args foo bar`)
        catch e
            @warn "Could not run $(scratch)/print_args"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
    end

    ## --- Test error throwing

    let
        # Compile...
        status = -1
        try
            isfile("maybe_throw") && rm("maybe_throw")
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/throw_errors.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/throw_errors.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        println("Error handling:")
        status = -1
        try
            status = run(`./maybe_throw 10`)
        catch e
            @warn "Could not run $(scratch)/maybe_throw"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        status = -1
        try
            status = run(`./maybe_throw -10`)
        catch e
            @info "maybe_throw: task failed sucessfully!"
        end
        if Sys.iswindows()
            @info "maybe_throw: task doesn't fail on Windows."
            @test status.exitcode == 0
        else
            @test status === -1
        end
    end

    ## --- Test interop

    if Sys.isbsd()
        let
            # Compile...
            status = -1
            try
                isfile("interop") && rm("interop")
                status = run(`$jlpath --startup=no --compile=min $testpath/scripts/interop.jl`)
            catch e
                @warn "Could not compile $testpath/scripts/interop.jl"
                println(e)
            end
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0

            # Run...
            println("Interop:")
            status = -1
            try
                status = run(`./interop`)
            catch e
                @warn "Could not run $(scratch)/interop"
                println(e)
            end
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0
        end
    end

end

## --- Clean up

cd(testpath)
