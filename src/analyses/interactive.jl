# Interactive Analysis REPL
# Provides an interactive shell for exploring compiler analysis

"""
    AnalysisSession

Tracks state for an interactive analysis session.
"""
mutable struct AnalysisSession
    history::Vector{Tuple{Symbol, Tuple, CompilationReadinessReport}}
    current_function::Union{Nothing, Function}
    current_types::Union{Nothing, Tuple}
    last_report::Union{Nothing, CompilationReadinessReport}
    bookmarks::Dict{String, Tuple{Function, Tuple}}
end

AnalysisSession() = AnalysisSession([], nothing, nothing, nothing, Dict())

# Global session
const SESSION = Ref{Union{Nothing, AnalysisSession}}(nothing)

"""
    start_interactive()

Start an interactive compiler analysis session.

Provides quick commands for exploring code compilation readiness.

# Commands
- `analyze function_name(types...)` - Analyze a function
- `suggest` - Get optimization suggestions for last analyzed function
- `compare name1 name2` - Compare two functions
- `history` - Show analysis history
- `bookmark name` - Bookmark current function
- `list` - List bookmarked functions
- `help` - Show this help
- `quit` or `exit` - Exit interactive mode

# Example
```julia
julia> start_interactive()

Compiler Analysis Interactive Mode
Type 'help' for commands, 'quit' to exit

analysis> analyze my_func(Int, Int)
Score: 95/100
Status: READY

analysis> suggest
[Shows suggestions...]

analysis> quit
```
"""
function start_interactive()
    println()
    println("="^70)
    println("Compiler Analysis Interactive Mode")
    println("="^70)
    println()
    println("Type 'help' for commands, 'quit' to exit")
    println()

    # Initialize session
    SESSION[] = AnalysisSession()

    while true
        print("analysis> ")
        input = readline()
        input = strip(input)

        if isempty(input)
            continue
        end

        # Parse command
        parts = split(input)
        cmd = parts[1]

        try
            if cmd == "quit" || cmd == "exit"
                println("Exiting interactive mode")
                break

            elseif cmd == "help"
                show_help()

            elseif cmd == "analyze"
                if length(parts) < 2
                    println("Usage: analyze function_name(types...)")
                    continue
                end

                # This is a simple command parser
                # In real use, users would need to have functions in scope
                println("Note: To analyze, the function must be in scope")
                println("Example: analyze my_func (for a function you've already defined)")

            elseif cmd == "suggest"
                if SESSION[].last_report === nothing
                    println("No function analyzed yet. Use 'analyze' first.")
                else
                    fname = SESSION[].last_report.function_name
                    ftypes = SESSION[].current_types
                    println("Getting suggestions for $fname...")
                    # Would call suggest_optimizations here
                    println("(Function must be in scope)")
                end

            elseif cmd == "history"
                show_history()

            elseif cmd == "bookmark"
                if length(parts) < 2
                    println("Usage: bookmark name")
                    continue
                end

                if SESSION[].current_function === nothing
                    println("No function analyzed yet")
                else
                    bookmark_name = parts[2]
                    SESSION[].bookmarks[bookmark_name] = (SESSION[].current_function, SESSION[].current_types)
                    println("Bookmarked as '$bookmark_name'")
                end

            elseif cmd == "list"
                list_bookmarks()

            elseif cmd == "clear"
                SESSION[] = AnalysisSession()
                println("Session cleared")

            else
                println("Unknown command: $cmd")
                println("Type 'help' for available commands")
            end

        catch e
            println("Error: $e")
        end

        println()
    end

    println()
end

function show_help()
    println("""
    Available Commands:
    ──────────────────────────────────────────────────────────────────

    analyze <function>(types)  Analyze a function with given types
    suggest                    Get optimization suggestions
    compare <f1> <f2>         Compare two functions
    history                    Show analysis history
    bookmark <name>           Bookmark current function
    list                      List bookmarked functions
    clear                     Clear session
    help                      Show this help
    quit/exit                 Exit interactive mode

    Examples:
    ──────────────────────────────────────────────────────────────────

    analysis> analyze my_func(Int, Int)
    analysis> suggest
    analysis> bookmark critical_func
    analysis> history
    analysis> quit
    """)
end

function show_history()
    if isempty(SESSION[].history)
        println("No analysis history")
        return
    end

    println("Analysis History:")
    println()

    for (i, (fname, types, report)) in enumerate(SESSION[].history)
        status = report.ready_for_compilation ? "" : ""
        println("$i. $status $fname$types - $(report.score)/100")
    end
end

function list_bookmarks()
    if isempty(SESSION[].bookmarks)
        println("No bookmarks")
        return
    end

    println("Bookmarked Functions:")
    println()

    for (name, (func, types)) in SESSION[].bookmarks
        println("  $name: $(nameof(func))$types")
    end
end

"""
    interactive_analyze(f::Function, types::Tuple)

Analyze a function in interactive mode.

This is a helper for the interactive REPL.

# Example
```julia
julia> interactive_analyze(my_func, (Int,))
```
"""
function interactive_analyze(f::Function, types::Tuple)
    if SESSION[] === nothing
        SESSION[] = AnalysisSession()
    end

    fname = nameof(f)

    println("Analyzing $fname$types...")
    println()

    report = quick_check(f, types)

    # Store in session
    push!(SESSION[].history, (fname, types, report))
    SESSION[].current_function = f
    SESSION[].current_types = types
    SESSION[].last_report = report

    # Print brief summary
    print_readiness_report(report)

    return report
end

"""
    interactive_suggest()

Get suggestions for the last analyzed function in interactive mode.

# Example
```julia
julia> interactive_analyze(my_func, (Int,))
julia> interactive_suggest()
```
"""
function interactive_suggest()
    if SESSION[] === nothing || SESSION[].last_report === nothing
        println("No function analyzed yet. Call interactive_analyze() first.")
        return
    end

    f = SESSION[].current_function
    types = SESSION[].current_types

    suggest_optimizations(f, types)
end

"""
    interactive_compare(f1::Function, t1::Tuple, f2::Function, t2::Tuple)

Compare two functions in interactive mode.

# Example
```julia
julia> interactive_compare(old_func, (Int,), new_func, (Int,))
```
"""
function interactive_compare(f1::Function, t1::Tuple, f2::Function, t2::Tuple)
    println("Analyzing both functions...")
    println()

    r1 = quick_check(f1, t1)
    r2 = quick_check(f2, t2)

    compare_reports(r1, r2)
end

export start_interactive, interactive_analyze, interactive_suggest, interactive_compare
export AnalysisSession
