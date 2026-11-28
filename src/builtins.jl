## Builtins: the LLVM functions that the code generator may calls and that a C runtime library would have supplied

# When an object is linked by `lld` alone, nothing supplies the functions that codegen calls that the CPU has no instruction for.
# For example, `__udivti3` for the division of `i128`, `__extendhfsf2` for `Float16`. 
# They are defined here in IR, `linkonce_odr` and `hidden`: 
# a definition of the program's own, or of a library that is linked, wins, and the module has only those that it uses. 
# A toolchain asks for them with `builtins = true` (`LLDToolchain` does by default; a `CCToolchain` does not, as the compiler driver links its runtime library).

# 128-bit division (`__udivti3` and the others of libgcc and compiler-rt, which a Linux program is not linked with): by shifting and subtracting, with instructions of `i128` that are not calls
# (a division of `i128` in them would be a call of themselves).
const LINUX_INT128_BUILTINS = """
define linkonce_odr hidden i128 @__static_udivmod(i128 %a, i128 %b, i1 %rem) {
entry:
  ; (operands of 64 bits, the usual: the instruction of the CPU; a divisor of zero is left to the loop, which does not trap)
  %ah = lshr i128 %a, 64
  %bh = lshr i128 %b, 64
  %hi = or i128 %ah, %bh
  %nohi = icmp eq i128 %hi, 0
  %bnz = icmp ne i128 %b, 0
  %small = and i1 %nohi, %bnz
  br i1 %small, label %fast, label %loop
fast:
  %a64 = trunc i128 %a to i64
  %b64 = trunc i128 %b to i64
  %fq = udiv i64 %a64, %b64
  %fr = urem i64 %a64, %b64
  %fqx = zext i64 %fq to i128
  %frx = zext i64 %fr to i128
  %fres = select i1 %rem, i128 %frx, i128 %fqx
  ret i128 %fres
loop:
  %i = phi i32 [ 127, %entry ], [ %i1, %loop ]
  %q = phi i128 [ 0, %entry ], [ %q2, %loop ]
  %r = phi i128 [ 0, %entry ], [ %r3, %loop ]
  %i128 = zext i32 %i to i128
  %sh = lshr i128 %a, %i128
  %bit = and i128 %sh, 1
  %r1 = shl i128 %r, 1
  %r2 = or i128 %r1, %bit
  %ge = icmp uge i128 %r2, %b
  %rs = sub i128 %r2, %b
  %r3 = select i1 %ge, i128 %rs, i128 %r2
  %one = shl i128 1, %i128
  %qo = or i128 %q, %one
  %q2 = select i1 %ge, i128 %qo, i128 %q
  %i1 = sub i32 %i, 1
  %done = icmp slt i32 %i1, 0
  br i1 %done, label %exit, label %loop
exit:
  %res = select i1 %rem, i128 %r3, i128 %q2
  ret i128 %res
}
define linkonce_odr hidden i128 @__udivti3(i128 %a, i128 %b) {
  %r = call i128 @__static_udivmod(i128 %a, i128 %b, i1 false)
  ret i128 %r
}
define linkonce_odr hidden i128 @__umodti3(i128 %a, i128 %b) {
  %r = call i128 @__static_udivmod(i128 %a, i128 %b, i1 true)
  ret i128 %r
}
define linkonce_odr hidden i128 @__divti3(i128 %a, i128 %b) {
  %sa = icmp slt i128 %a, 0
  %sb = icmp slt i128 %b, 0
  %na = sub i128 0, %a
  %nb = sub i128 0, %b
  %ua = select i1 %sa, i128 %na, i128 %a
  %ub = select i1 %sb, i128 %nb, i128 %b
  %q = call i128 @__static_udivmod(i128 %ua, i128 %ub, i1 false)
  %neg = xor i1 %sa, %sb
  %nq = sub i128 0, %q
  %r = select i1 %neg, i128 %nq, i128 %q
  ret i128 %r
}
define linkonce_odr hidden i128 @__modti3(i128 %a, i128 %b) {
  %sa = icmp slt i128 %a, 0
  %sb = icmp slt i128 %b, 0
  %na = sub i128 0, %a
  %nb = sub i128 0, %b
  %ua = select i1 %sa, i128 %na, i128 %a
  %ub = select i1 %sb, i128 %nb, i128 %b
  %m = call i128 @__static_udivmod(i128 %ua, i128 %ub, i1 true)
  %nm = sub i128 0, %m
  %r = select i1 %sa, i128 %nm, i128 %m
  ret i128 %r
}
"""

# The same, for the convention of x86-64 Windows: the code generator calls `__udivti3` and the others with the addresses of the two operands (in `rcx` and `rdx`, as the C convention of Windows passes what is larger than a
# register), and reads the result from `xmm0`, as a vector of two integers of 64 bits (as libgcc, which has them, returns what `__int128` is). (Checked with `llc` of LLVM 23.)
function windows_int128_builtins(text::AbstractString)
    for name in ("__udivti3", "__umodti3", "__divti3", "__modti3")
        from = "define linkonce_odr hidden i128 @$name(i128 %a, i128 %b) {\n"
        occursin(from, text) || error("the text of the division of 128 bits has changed: `$from` is not in it")
        text = replace(text, from => "define linkonce_odr hidden <2 x i64> @$name(ptr %pa, ptr %pb) {\n  %a = load i128, ptr %pa, align 8\n  %b = load i128, ptr %pb, align 8\n")
    end
    returned = "  ret i128 %r\n"
    count(returned, text) == 4 || error("the text of the division of 128 bits has changed: it has not four functions that return `%r`")
    return replace(text, returned => "  %v = bitcast i128 %r to <2 x i64>\n  ret <2 x i64> %v\n")
end
const WINDOWS_INT128_BUILTINS = windows_int128_builtins(LINUX_INT128_BUILTINS)

# Conversions between `Float16`, `Float32`, and `Float64` that the code generator calls where the CPU has no instruction for them.
# For example: WebAssembly has none, nor has generic/older x86-64 (F16C is from 2012 on, and Rosetta before macOS 15 does not have it)
# Instead, we make the conversion by integer arithmetic, as compiler-rt definitions
# Rounding is to nearest, ties to even
# These are called with the convention of the *library calls* that the code generator makes, which varies by target. 
# (Checked with `llc` of LLVM 23: the caller reads the result of `__truncsfhf2` from `xmm0`, and passes the argument of `__extendhfsf2` there.)
const HALF_BUILTINS = """
define linkonce_odr hidden float @__extendhfsf2(half %a) {
  %h = bitcast half %a to i16
  %hi = zext i16 %h to i32
  %s1 = lshr i32 %hi, 15
  %s2 = shl i32 %s1, 31
  %e1 = lshr i32 %hi, 10
  %e = and i32 %e1, 31
  %m = and i32 %hi, 1023
  %en = add i32 %e, 112
  %en2 = shl i32 %en, 23
  %m13 = shl i32 %m, 13
  %n1 = or i32 %s2, %en2
  %normal = or i32 %n1, %m13
  %i1 = or i32 %s2, 2139095040
  %infnan = or i32 %i1, %m13
  %mf = uitofp i32 %m to float
  %sub = fmul float %mf, 0x3E70000000000000
  %subb = bitcast float %sub to i32
  %subs = or i32 %subb, %s2
  %isz = icmp eq i32 %e, 0
  %isi = icmp eq i32 %e, 31
  %r1 = select i1 %isi, i32 %infnan, i32 %normal
  %r = select i1 %isz, i32 %subs, i32 %r1
  %f = bitcast i32 %r to float
  ret float %f
}
define linkonce_odr hidden half @__truncsfhf2(float %a) {
  %x = bitcast float %a to i32
  %s1 = lshr i32 %x, 16
  %sign = and i32 %s1, 32768
  %e1 = lshr i32 %x, 23
  %e = and i32 %e1, 255
  %m = and i32 %x, 8388607
  %ne = sub i32 %e, 112
  ; infinity and NaN
  %m13 = lshr i32 %m, 13
  %nanm = or i32 %m13, 512
  %hasm = icmp ne i32 %m, 0
  %nanbits = select i1 %hasm, i32 %nanm, i32 0
  %infnan = or i32 %nanbits, 31744
  ; normal
  %ne10 = shl i32 %ne, 10
  %hn = or i32 %ne10, %m13
  %rem = and i32 %m, 8191
  %gt = icmp ugt i32 %rem, 4096
  %eq = icmp eq i32 %rem, 4096
  %odd1 = and i32 %hn, 1
  %odd = icmp ne i32 %odd1, 0
  %tie = and i1 %eq, %odd
  %up = or i1 %gt, %tie
  %upi = zext i1 %up to i32
  %hn2 = add i32 %hn, %upi
  ; subnormal
  %mm = or i32 %m, 8388608
  %shift = sub i32 14, %ne
  %shiftc = call i32 @llvm.umin.i32(i32 %shift, i32 31)
  %hs = lshr i32 %mm, %shiftc
  %one = shl i32 1, %shiftc
  %mask = sub i32 %one, 1
  %rem2 = and i32 %mm, %mask
  %half1 = lshr i32 %one, 1
  %gt2 = icmp ugt i32 %rem2, %half1
  %eq2 = icmp eq i32 %rem2, %half1
  %odd2a = and i32 %hs, 1
  %odd2 = icmp ne i32 %odd2a, 0
  %tie2 = and i1 %eq2, %odd2
  %up2 = or i1 %gt2, %tie2
  %up2i = zext i1 %up2 to i32
  %hs2 = add i32 %hs, %up2i
  ; which
  %isinf = icmp eq i32 %e, 255
  %ovf = icmp sge i32 %ne, 31
  %isnorm = icmp sge i32 %ne, 1
  %issub = icmp sge i32 %ne, -10
  %r1 = select i1 %issub, i32 %hs2, i32 0
  %r2 = select i1 %isnorm, i32 %hn2, i32 %r1
  %r3 = select i1 %ovf, i32 31744, i32 %r2
  %r4 = select i1 %isinf, i32 %infnan, i32 %r3
  %r5 = or i32 %r4, %sign
  %r16 = trunc i32 %r5 to i16
  %h = bitcast i16 %r16 to half
  ret half %h
}
declare i32 @llvm.umin.i32(i32, i32)
; double to half: through float with the rounding to odd (inexact results get an odd last bit: the second rounding is then the one of the double), and half to double
define linkonce_odr hidden half @__truncdfhf2(double %a) {
  %f = fptrunc double %a to float
  %back = fpext float %f to double
  %exact = fcmp oeq double %back, %a
  %isnan = fcmp uno double %a, %a
  %fb = bitcast float %f to i32
  %odd = and i32 %fb, 1
  %isodd = icmp ne i32 %odd, 0
  %nb = fneg double %back
  %bneg = fcmp olt double %back, 0.0
  %ab = select i1 %bneg, double %nb, double %back
  %na = fneg double %a
  %aneg = fcmp olt double %a, 0.0
  %aa = select i1 %aneg, double %na, double %a
  %up = fcmp ogt double %ab, %aa
  %dec = sub i32 %fb, 1
  %inc = add i32 %fb, 1
  %adj = select i1 %up, i32 %dec, i32 %inc
  %isinf = fcmp oeq float %f, 0x7FF0000000000000
  %k1 = or i1 %exact, %isodd
  %k2 = or i1 %k1, %isnan
  %k3 = or i1 %k2, %isinf
  %r = select i1 %k3, i32 %fb, i32 %adj
  %rf = bitcast i32 %r to float
  %h = call half @__truncsfhf2(float %rf)
  ret half %h
}
define linkonce_odr hidden double @__extendhfdf2(half %a) {
  %f = call float @__extendhfsf2(half %a)
  %d = fpext float %f to double
  ret double %d
}
"""

# The same, for the convention of x86-64 macOS, where the library calls pass a `Float16` as an `i16` in an integer register 
# The `half` of the signatures and of the calls is an `i16`, and what is made of it by `bitcast` is the value itself.
# (the argument in `edi`, the result in `ax`). 
function macos_x86_half_builtins(text::AbstractString)
    replacements = [
        "define linkonce_odr hidden float @__extendhfsf2(half %a) {\n  %h = bitcast half %a to i16\n" => "define linkonce_odr hidden float @__extendhfsf2(i16 %h) {\n",
        "define linkonce_odr hidden half @__truncsfhf2(float %a) {" => "define linkonce_odr hidden i16 @__truncsfhf2(float %a) {",
        "  %h = bitcast i16 %r16 to half\n  ret half %h" => "  ret i16 %r16",
        "define linkonce_odr hidden half @__truncdfhf2(double %a) {" => "define linkonce_odr hidden i16 @__truncdfhf2(double %a) {",
        "  %h = call half @__truncsfhf2(float %rf)\n  ret half %h" => "  %h = call i16 @__truncsfhf2(float %rf)\n  ret i16 %h",
        "define linkonce_odr hidden double @__extendhfdf2(half %a) {\n  %f = call float @__extendhfsf2(half %a)" => "define linkonce_odr hidden double @__extendhfdf2(i16 %a) {\n  %f = call float @__extendhfsf2(i16 %a)",
    ]
    for (from, to) in replacements
        occursin(from, text) || error("the text of the conversions of `Float16` has changed: `$from` is not in it")
        text = replace(text, from => to)
    end
    return text
end
const MACOS_X86_HALF_BUILTINS = macos_x86_half_builtins(HALF_BUILTINS)

# The probe of the stack for x86-64 Windows (`___chkstk_ms` of libgcc and compiler-rt): the runtime of MinGW-w64 calls it itself (`pseudo-reloc.o`, which every program has), and the libraries that `Mingw_jll`
# has do not have it. It touches each page of the stack that a function of a large frame is about to use, as the system's guard page needs. It is assembly, which the module has as its own (`module asm`).
const MINGW_X64_BUILTINS = raw"""
module asm ".text"
module asm ".globl ___chkstk_ms"
module asm ".def ___chkstk_ms; .scl 2; .type 32; .endef"
module asm "___chkstk_ms:"
module asm "  pushq %rcx"
module asm "  pushq %rax"
module asm "  cmpq $0x1000, %rax"
module asm "  leaq 24(%rsp), %rcx"
module asm "  jb 2f"
module asm "1:"
module asm "  subq $0x1000, %rcx"
module asm "  orl $0, (%rcx)"
module asm "  subq $0x1000, %rax"
module asm "  cmpq $0x1000, %rax"
module asm "  ja 1b"
module asm "2:"
module asm "  subq %rax, %rcx"
module asm "  orl $0, (%rcx)"
module asm "  popq %rax"
module asm "  popq %rcx"
module asm "  ret"
"""

# The builtins that the IR needs for the target: the names of the constants above. What the IR has that needs them (`Float16`, the division of `i128`) is `has_half` and `has_i128div`; the system and the architecture are the triple's.
function needed_builtins(has_half::Bool, has_i128div::Bool, triple::AbstractString)
    family = llvm_family(first(split(triple, '-')))
    needed = Symbol[]
    x86_64 = family == "x86" && startswith(triple, "x86_64")
    x86_64 && has_half && push!(needed, occursin(r"apple|darwin|macos", triple) ? :MACOS_X86_HALF_BUILTINS : :HALF_BUILTINS)
    family == "wasm" && has_half && push!(needed, :HALF_BUILTINS)
    occursin("linux", triple) && has_i128div && push!(needed, :LINUX_INT128_BUILTINS)
    x86_64 && occursin(r"windows|mingw", triple) && has_i128div && push!(needed, :WINDOWS_INT128_BUILTINS)
    # (the runtime of MinGW-w64 needs the probe of the stack whatever the program is)
    startswith(triple, "x86_64") && occursin(r"windows|mingw", triple) && push!(needed, :MINGW_X64_BUILTINS)
    return needed
end
# (of the text of IR)
needed_builtins(text::AbstractString, triple::AbstractString) =
    needed_builtins(occursin(r"\bhalf\b", text), occursin(r"\b(udiv|sdiv|urem|srem) i128\b", text), triple)
# (of a module: by its instructions, without printing it)
function needed_builtins(mod::LLVM.Module, triple::AbstractString)
    has_half = has_i128div = false
    for f in LLVM.functions(mod), bb in LLVM.blocks(f), inst in LLVM.instructions(bb)
        has_half = has_half || mentions_half(LLVM.value_type(inst)) || any(op -> mentions_half(LLVM.value_type(op)), LLVM.operands(inst))
        if !has_i128div && LLVM.opcode(inst) in (LLVM.API.LLVMUDiv, LLVM.API.LLVMSDiv, LLVM.API.LLVMURem, LLVM.API.LLVMSRem)
            ty = LLVM.value_type(inst)
            has_i128div = ty isa LLVM.IntegerType && LLVM.width(ty) == 128
        end
        has_half && has_i128div && break
    end
    return needed_builtins(has_half, has_i128div, triple)
end
# (a `half`, or a vector of them)
mentions_half(ty::LLVM.LLVMType) = ty isa LLVM.HalfType || (ty isa LLVM.VectorType && LLVM.eltype(ty) isa LLVM.HalfType)

"""
    add_builtins(text::AbstractString, triple::AbstractString) -> String

The LLVM IR `text` with the definitions of the builtins that it needs for `triple` (see [`add_builtins!`](@ref)).
"""
function add_builtins(text::AbstractString, triple::AbstractString)
    for name in needed_builtins(text, triple)
        text = string(text, "\n", getfield(@__MODULE__, name))
    end
    return text
end

"""
    add_builtins!(mod::LLVM.Module, triple::AbstractString) -> mod

Define in the module the builtins that it needs for the target `triple`: the functions that the code generator calls for what the CPU has no instruction for, which a C runtime library (libgcc, compiler-rt) has and an object
that is linked by `lld` alone has not. Which are needed is what the module says: `i128` division on Linux, `Float16` conversions on x86-64 and WebAssembly.
"""
function add_builtins!(mod::LLVM.Module, triple::AbstractString)
    for name in needed_builtins(mod, triple)
        builtins = parse(LLVM.Module, getfield(@__MODULE__, name))
        for f in LLVM.functions(builtins)
            LLVM.isdeclaration(f) || LLVM.linkage!(f, LLVM.API.LLVMWeakODRLinkage)
        end
        LLVM.triple!(builtins, LLVM.triple(mod))
        LLVM.datalayout!(builtins, LLVM.datalayout(mod))
        LLVM.link!(mod, builtins)
    end
    return mod
end
