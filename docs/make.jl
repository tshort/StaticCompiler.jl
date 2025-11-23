using StaticCompiler
using Documenter

makedocs(;
    modules = [StaticCompiler],
    authors = "Tom Short",
    repo = "https://github.com/tshort/StaticCompiler.jl/blob/{commit}{path}#L{line}",
    sitename = "StaticCompiler.jl",
    format = Documenter.HTML(;
        prettyurls = prettyurls = get(ENV, "CI", nothing) == "true",
        # canonical="https://tshort.github.io/StaticCompiler.jl",
        # assets=String[],
    ),
    pages = [
        "Home" => "index.md",
        "Backend Syntax Reference" => "backend.md",
        "Helpers Syntax Reference" => "helpers.md",
    ],
)

deploydocs(;
    repo = "github.com/tshort/StaticCompiler.jl",
)
