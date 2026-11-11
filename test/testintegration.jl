# Setup
testpath = pwd()
scratch = tempdir()
cd(scratch)

function bumper_test(N::Int)
    buf = AllocBuffer(MallocVector, sizeof(Float64) * N)
    s = 0.0
    for i ∈ 1:N
        # some excuse to reuse the same memory a bunch of times
        @no_escape buf begin
            v = @alloc(Float64, N)
            v .= i
            s += sum(v)
        end
    end
    free(buf)
    s
end

@testset "Bumper.jl integration" begin
    path = compile_shlib(bumper_test, (Int,), "./")
    ptr = Libdl.dlopen(path, Libdl.RTLD_LOCAL)

    fptr = Libdl.dlsym(ptr, "bumper_test")

    @test bumper_test(8) == @ccall($fptr(8::Int)::Float64)
end

# To remove output files
cleanup(files...) = foreach(f -> isfile(f) && rm(f), files)

@testset "Standalone Executable Integration" begin

    jlpath = joinpath(Sys.BINDIR, Base.julia_exename()) # Get path to julia executable

    ## --- Times table, file IO, mallocarray
    let
        # Attempt to compile
        # We have to start a new Julia process to get around the fact that Pkg.test
        # disables `@inbounds`, but ironically we can use `--compile=min` to make that
        # faster.
        cleanup("times_table")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/times_table.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/times_table.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Attempt to run
        cleanup("table.tsv", "table.b")
        println("4x4 times table (MallocArray):")
        status = -1
        try
            status = run(`./times_table 4 4`)
        catch e
            @warn "Could not run $(scratch)/times_table"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        # Test ascii output
        @test parsedlm(Int, c"table.tsv", '\t') == (1:4)*(1:4)'
        # Test binary output
        @test fread!(szeros(Int, 4,4), c"table.b") == (1:4)*(1:4)'
    end

    ## --- As above but with staticarray

    let
        # Compile...
        cleanup("stack_times_table")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/stack_times_table.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/stack_times_table.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run..
        cleanup("table.tsv", "table.b")
        println("5x5 times table (StackArray):")
        status = -1
        try
            status = run(`./stack_times_table`)
        catch e
            @warn "Could not run $(scratch)/stack_times_table"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        # Test ascii output
        @test parsedlm(Int, c"table.tsv", '\t') == (1:5)*(1:5)'
        # Test binary output
        @test fread!(szeros(Int, 5,5), c"table.b") == (1:5)*(1:5)'
    end


    ## --- Reading from written files

    let
        # Compile...
        cleanup("readwrite")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/readwrite.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/readwrite.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        cleanup("table.tsv", "table.b", "tableb.tsv", "tables.tsv", "tablets.tsv")
        println("5x5 times table, read from file:")
        status = -1
        try
            status = run(`./readwrite 5 5`)
        catch e
            @warn "Could not run $(scratch)/readwrite"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        # Test binary output
        @test fread!(szeros(Int, 5,5), c"table.b") == (1:5)*(1:5)'
        # Test ascii output
        @test parsedlm(Int, c"table.tsv", '\t') == (1:5)*(1:5)'
        @test parsedlm(Int, c"tableb.tsv", '\t') == (1:5)*(1:5)'
        @test parsedlm(Int, c"tables.tsv", '\t') == (1:5)*(1:5)'
        @test parsedlm(Int, c"tablets.tsv", '\t') == (1:5)*(1:5)'

    end


    ## --- "withmallocarray"-type do-block pattern
    let
        # Compile...
        cleanup("withmallocarray")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/withmallocarray.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/withmallocarray.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

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
        @test isa(status, Base.Process) && status.exitcode == 0
    end

    ## --- Random number generation
    let
        # Compile...
        cleanup("rand_matrix")
        status = -1
        try
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
        cleanup("randn_matrix")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/randn_matrix.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/randn_matrix.jl"
            println(e)
        end
        @static if Sys.isbsd()
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
        @static if Sys.isbsd()
            @test isa(status, Base.Process)
            @test isa(status, Base.Process) && status.exitcode == 0
        end
    end

    ## --- Test matrix multiplication by plain @inbounds loops
    let
        # Compile...
        cleanup("inbounds_product")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/inbounds_product.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/inbounds_product.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        cleanup("product.tsv")
        println("10x10 table sum:")
        status = -1
        try
            status = run(`./inbounds_product 10 10`)
        catch e
            @warn "Could not run $(scratch)/inbounds_product"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        @test parsedlm(c"product.tsv",'\t')[] == 3025
    end

    let
        # Compile...
        cleanup("inbounds_matrix")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/inbounds_matrix.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/inbounds_matrix.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        cleanup("table.tsv", "table.b")
        println("10x5 MallocMatrix product, manual inbounds:")
        status = -1
        try
            status = run(`./inbounds_matrix 10 5`)
        catch e
            @warn "Could not run $(scratch)/inbounds_matrix"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        A = (1:10) * (1:5)'
        # Check ascii output
        @test parsedlm(c"table.tsv",'\t') == A' * A
        # Check binary output
        @test fread!(szeros(5,5), c"table.b") == A' * A
    end

    let
        # Compile...
        cleanup("inbounds_matrix_stack")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/inbounds_matrix_stack.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/inbounds_matrix_stack.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        cleanup("table.tsv")
        println("10x5 StackMatrix product, manual inbounds:")
        status = -1
        try
            status = run(`./inbounds_matrix_stack`)
        catch e
            @warn "Could not run $(scratch)/inbounds_matrix_stack"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        A = (1:10) * (1:5)'
        @test parsedlm(c"table.tsv",'\t') == A' * A
    end

    ## --- Test built-in matrix multiplication
    let
        # Compile...
        cleanup("matmul")
        status = -1
        try
            status = run(`$jlpath --startup=no --compile=min $testpath/scripts/matmul.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/matmul.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        cleanup("table.tsv", "table.b")
        println("10x5 MallocMatrix product:")
        status = -1
        try
            status = run(`./matmul 10 5`)
        catch e
            @warn "Could not run $(scratch)/matmul"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        A = (1:10) * (1:5)'
        # Check ascii output
        @test parsedlm(c"table.tsv",'\t') == A' * A
        # Check binary output
        @test fread!(szeros(5,5), c"table.b") == A' * A
    end

    let
        # Compile...
        cleanup("matmul_stack")
        status = -1
        try
            status = run(`$jlpath --compile=min $testpath/scripts/matmul_stack.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/matmul_stack.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        cleanup("table.tsv", "table.b")
        println("10x5 StackMatrix product:")
        status = -1
        try
            status = run(`./matmul_stack`)
        catch e
            @warn "Could not run $(scratch)/matmul_stack"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
        A = (1:10) * (1:5)'
        # Check ascii output
        @test parsedlm(c"table.tsv",'\t') == A' * A
        # Check binary output
        @test fread!(szeros(5,5), c"table.b") == A' * A
    end

    ## --- Test string handling

    let
        # Compile...
        cleanup("print_args")
        status = -1
        try
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

    ## --- Test string iteration

    let
        # Compile...
        cleanup("iterate")
        status = -1
        try
            status = run(`$jlpath --startup=no $testpath/scripts/iterate.jl`)
        catch e
            @warn "Could not compile $testpath/scripts/iterate.jl"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0

        # Run...
        println("Iteration:")
        status = -1
        try
            status = run(`./iterate`)
        catch e
            @warn "Could not run $(scratch)/iterate"
            println(e)
        end
        @test isa(status, Base.Process)
        @test isa(status, Base.Process) && status.exitcode == 0
    end

    ## --- Test error throwing

    let
        # Compile...
        cleanup("maybe_throw") 
        status = -1
        try
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
        @test status === -1
    end

    ## --- Test interop
    
    # (dlopen/dlsym are not available on Windows)
    @static if !Sys.iswindows() let
        # Compile...
        cleanup("interop")
        status = -1
        try
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
    end end

end

## --- Clean up

cd(testpath)
