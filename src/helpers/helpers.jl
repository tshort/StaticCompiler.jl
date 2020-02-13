"""
Returns shellcmd string for different OS. Optionally, checks for gcc installation.
"""
function _shellcmd(checkInstallation::Bool = false)

    if Sys.isunix()
        shellcmd = "gcc"
    elseif Sys.iswindows()
        shellcmd = ["cmd", "/c", "gcc"]
    else
        error("run command not defined")
    end

    if checkInstallation
        # Checking gcc installation
        try
            run(`$shellcmd -v`)
        catch
            @warn "Make sure gcc compiler is installed: https://gcc.gnu.org/install/binaries.html and is on the path, othetwise some of the functions will return errors"
            return nothing
        end
    end

    return shellcmd
end

shellcmd = _shellcmd(true) # is used in @jlrun and exegen()


export @jlrun
include("jlrun.jl")

export ldflags, ldlibs, cflags # are used in exegen
include("juliaconfig.jl")

export exegen
include("standalone-exe.jl")
