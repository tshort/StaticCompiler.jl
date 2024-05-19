# Currently, `StaticTools.stderrp()` used in `test/scripts` doesn't work on Windows.
# This temporary file deletes `stderrp()` and run tests.

mkpath("scripts_windows")

for file in readdir("scripts")
    script = read("scripts/$file", String)
    script = replace(script, "printf(stderrp(), " => "printf(")
    write("scripts_windows/$file", script)
end

script = read("testintegration.jl", String)
script = replace(script, "testpath/scripts/" => "testpath/scripts_windows/")

include_string(Main, script)

rm("scripts_windows"; recursive=true)