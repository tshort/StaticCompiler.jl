function add_dllexport(funcs, ir_path; demangle=true)
    ir = read(ir_path, String)

    for (f, _) in funcs
        name_f = (demangle ? "" : "julia_") * fix_name(f)
        pattern = Regex("^define(.*?@$name_f\\()", "m")
        ir = replace(ir, pattern => s"define dllexport\1")
    end

    write(ir_path, ir)
end